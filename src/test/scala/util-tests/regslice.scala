// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import org.scalatest._
import chiseltest._
import chisel3.util._
import chisel3._
import scala.util.control.Breaks
import scala.util.Random


class RegSliceTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "IrrevocableRegSlice"
    behavior of dutName

    def checkResult(c: IrrevocableRegSlice[UInt]) {
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        val random = new Random
        fork {
            (0 to 255).foreach(i => {
                val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                (0 to idleCycles - 1).foreach(i => {
                    c.clock.step(1)
                })
                c.io.out.expectDequeue(i.U)
            })
        } .fork {
            (0 to 255).foreach(i => {
                val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
                (0 to idleCycles - 1).foreach(i => {
                    c.clock.step(1)
                })
                c.io.in.enqueue(i.U)
            })
        } .join
    }

    it should "8bit" in {
        test(new IrrevocableRegSlice(UInt(8.W))) { c => checkResult(c) }
    }
}
