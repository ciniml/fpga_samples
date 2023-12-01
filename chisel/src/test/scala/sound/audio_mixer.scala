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

class AudioMixerTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  def doTest(c: AudioMixer) = {
    val maxValue = (1 << c.width) - 1
    val positiveMaxValue = (1 << (c.width - 1)) - 1
    val random = new Random()

    for(ch <- 0 until c.channels) {
      c.io.dataIn(ch).setSourceClock(c.clock)
    }
    c.io.dataOut.setSinkClock(c.clock)
    c.reset.poke(true.B)
    c.clock.step(1)
    c.reset.poke(false.B)
    fork {
      for(i <- 0 to maxValue) {
        for(ch <- 0 until c.channels) {
          //val value = (i + ch * (1 << c.width) / 2) & maxValue
          val value = i & maxValue
          c.io.dataIn(ch).enqueue(((value << c.width) | value).U)
        }
      }
    } .fork {
      for(i <- 0 to maxValue) {
        var expectedL = 0
        var expectedR = 0
        for(ch <- 0 until c.channels) {
          val value = i & maxValue
          val valueSigned = if( value > positiveMaxValue ) {
            value - (1 << c.width)
          } else {
            value
          };
          expectedL += valueSigned
          expectedR += valueSigned
        }
        expectedL /= c.channels
        expectedR /= c.channels
        //print(f"expectedL: ${expectedL} expectedR: ${expectedR}\n")
        if( expectedL < 0 ) {
          expectedL += (1 << c.width)
        }
        if( expectedR < 0 ) {
          expectedR += (1 << c.width)
        }
        print(f"expectedL: ${expectedL} expectedR: ${expectedR} value: ${((expectedL & maxValue) << c.width) | (expectedR & maxValue)}\n")

        val expected = ((((expectedL & maxValue) << c.width) | (expectedR & maxValue))).U
        while( random.nextFloat() > 0.5 ) { c.clock.step(1) }
        c.io.dataOut.expectDequeue(expected)
      }
    } .join()
  }

  behavior of "AudioMixer"
  it must "4bits 1channel" in {
    test(new AudioMixer(4, 1, 0)) { c => doTest(c) }
  }
  it must "8bits 1channel" in {
    test(new AudioMixer(8, 1, 0)) { c => doTest(c) }
  }
  it must "8bits 2channels" in {
    test(new AudioMixer(8, 2, 0)) { c => doTest(c) }
  }
}