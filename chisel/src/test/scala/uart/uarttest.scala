// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package uart

import org.scalatest._
import chiseltest._
import chisel3.util._
import chisel3._
import scala.util.control.Breaks
import scala.util.Random

class TestUartSystem() extends Module {
  val io = IO(new Bundle{
    val in = Flipped(Decoupled(UInt(8.W)))
    val out = Decoupled(UInt(8.W))
  })
  
  val uartRx = Module(new UartRx(8, 4, 3))
  val uartTx = Module(new UartTx(8, 4))

  uartRx.io.rx <> uartTx.io.tx
  io.in <> uartTx.io.in
  io.out <> uartRx.io.out
}


class UartSystemTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "UartSystem"
    behavior of dutName

    def checkResult(c: TestUartSystem) {
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

    it should "simple" in {
        test(new TestUartSystem) { c => checkResult(c) }
    }
}
