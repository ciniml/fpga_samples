// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
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

class I2sMasterTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  def doTest(c: I2sMaster) = {
    val maxValue = (1 << (c.numberOfBitsPerChannel - 1)) - 1
    val phaseBit = (1 << (c.numberOfBitsPerChannel - 1))
    val mask = (1 << c.numberOfBitsPerChannel) - 1

    print(f"\nbits: ${c.numberOfBitsPerChannel} cycles: ${c.numberOfCyclesPerChannel} default: ${c.defaultValue}\n")
    c.io.dataIn.setSourceClock(c.clock)
    c.reset.poke(true.B)
    c.io.clockEnable.poke(true.B)
    c.clock.step(1)
    c.reset.poke(false.B)
    fork {
      for(i <- 0 to maxValue) {
        c.io.dataIn.enqueue((((i + 0) << c.numberOfBitsPerChannel) | (i + phaseBit)).U)
      }
    } .fork {
      for(i <- -1 to maxValue) {
        for(phase <- 0 to 1) {
          var data = if( i < 0 ) { c.defaultValue } else { BigInt(i + phase * phaseBit) }
          for(count <- 0 to (c.numberOfCyclesPerChannel - c.numberOfBitsPerChannel) - 1) {
            print(f"skip: ${count}\n")
            c.clock.step(1)
          }
          for(count <- 0 to (c.numberOfBitsPerChannel - 1)) {
            c.clock.step(1)
            print(f"phase: ${phase} count: ${count} data: ${data}\n")
            val msb = (data >> (c.numberOfBitsPerChannel - 1)) & 1
            c.io.dataOut.expect(msb == 1)
            c.io.wordSelect.expect(phase == 1)
            data = (data << 1) & mask
          }
        }
      }
    } .join()
  }

  behavior of "I2sMaster"
  it must "4bits 4cycles 0x07" in {
    test(new I2sMaster(4, 4, 0x7)) { c => doTest(c) }
  }
  it must "4bits 5cycles 0x07" in {
    test(new I2sMaster(4, 5, 0x7)) { c => doTest(c) }
  }
  it must "4bits 8cycles 0x07" in {
    test(new I2sMaster(4, 8, 0x7)) { c => doTest(c) }
  }
}