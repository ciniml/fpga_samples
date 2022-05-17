// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import org.scalatest._
import chiseltest._
import chisel3._
import scala.util.control.Breaks
import _root_.util._

class GrayCodeTestSystem(bits: Int) extends Module {
    val io = IO(new Bundle{
        val gray = Output(UInt(bits.W))
        val bin = Output(UInt(bits.W))
        val equal = Output(Bool())
    })

    val bin2Gray = Module(new Bin2Gray(bits))
    val gray2Bin = Module(new Gray2Bin(bits))

    val counter = RegInit(0.U(bits.W))
    bin2Gray.io.in := counter
    gray2Bin.io.in := bin2Gray.io.out

    io.gray := bin2Gray.io.out
    io.bin := gray2Bin.io.out
    io.equal := gray2Bin.io.out === counter

    counter := counter + 1.U
}

class GrayCodeTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "GrayCodeCounter"
    behavior of dutName

    it should "count bit 4" in {
        test(new GrayCodeTestSystem(4)) { c =>
            (0 to 15).foreach(i => {
                c.io.equal.expect(true.B)
                c.clock.step(1)
            })
        }
    }
    it should "count bit 8" in {
        test(new GrayCodeTestSystem(8)) { c =>
            (0 to 255).foreach(i => {
                c.io.equal.expect(true.B)
                c.clock.step(1)
            })
        }
    }
    it should "count bit 10" in {
        test(new GrayCodeTestSystem(10)) { c =>
            c.clock.setTimeout(1030)
            (0 to 1023).foreach(i => {
                c.io.equal.expect(true.B)
                c.clock.step(1)
            })
        }
    }
}
