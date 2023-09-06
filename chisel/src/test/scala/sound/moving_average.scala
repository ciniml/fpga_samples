// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._
import chiseltest._
import scala.util.control.Breaks
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers 
import scala.util.Random

class AudioMovingAverageFilterTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  def doTest(c: AudioMovingAverageFilter) = {
    val maxValue = (1 << c.width) - 1
    val positiveMaxValue = (1 << (c.width - 1)) - 1
    val random = new Random()

    c.io.dataIn.setSourceClock(c.clock)
    c.io.dataOut.setSinkClock(c.clock)
    c.reset.poke(true.B)
    c.clock.step(1)
    c.reset.poke(false.B)

    print(f"\nAudioMovingAverageFilterTest(${c.width}bits ${c.entries}tap)\n")
    fork {
      for(i <- 0 to maxValue) {
        val value = i & maxValue
        c.io.dataIn.enqueue(((value << c.width) | value).U)
      }
    } .fork {
      val entryBits = log2Ceil(c.entries)
      var accumulatorL = 0;
      var accumulatorR = 0;
      val queueL = new scala.collection.mutable.Queue[Int]()
      val queueR = new scala.collection.mutable.Queue[Int]()
      for(i <- 0 to maxValue) {
        var expectedL = 0
        var expectedR = 0
        val value = i & maxValue
        val valueSigned = if( value > positiveMaxValue ) {
          value - (1 << c.width)
        } else {
          value
        };
        val lastValueL = if(queueL.length >= c.entries ) {
          queueL.dequeue()
        } else {
          0
        };
        val lastValueR = if(queueR.length >= c.entries ) {
          queueR.dequeue()
        } else {
          0
        };
        // The output is calculated from the current accumulator value before updating the accumulator.
        expectedL = accumulatorL >> entryBits
        expectedR = accumulatorR >> entryBits
        if( expectedL < 0 ) {
          expectedL += (1 << c.width)
        }
        if( expectedR < 0 ) {
          expectedR += (1 << c.width)
        }
        print(f"value: 0x${value.toHexString} valueSigned: ${valueSigned} accumulatorL: 0x${accumulatorL.toHexString} accumulatorR: 0x${accumulatorR.toHexString} lastValueL: 0x${lastValueL.toHexString} lastValueR: 0x${lastValueL.toHexString} expectedL: 0x${expectedL.toHexString} expectedR: 0x${expectedR.toHexString} expectedOutput: 0x${(((expectedL & maxValue) << c.width) | (expectedR & maxValue)).toHexString}\n")

        // Update the accumulator.
        accumulatorL += valueSigned - lastValueL
        accumulatorR += valueSigned - lastValueR
        queueL.enqueue(valueSigned)
        queueR.enqueue(valueSigned)

        val expected = ((((expectedL & maxValue) << c.width) | (expectedR & maxValue))).U
        while( random.nextFloat() > 0.5 ) { c.clock.step(1) }
        c.io.dataOut.expectDequeue(expected)
      }
    } .join()
  }

  behavior of "AudioMovingAverageFilter"
  it must "4bits 8tap" in {
    test(new AudioMovingAverageFilter(4, 8)) { c => doTest(c) }
  }
  it must "8bits 8tap" in {
    test(new AudioMovingAverageFilter(8, 8)) { c => doTest(c) }
  }
}