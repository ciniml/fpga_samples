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
import chisel3.experimental.BundleLiterals._

class IrrevocableSwitchTestSystem extends Module {
    val numberOfChannels = 4
    val maxCount = 8
    val gen = UInt(8.W)
    val commandType = CountingIrrevocableSwitchCommand(numberOfChannels, maxCount)
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
        val selectCommand = Flipped(Irrevocable(commandType))
    })

    val demux = Module(new CountingIrrevocableDemux(gen, numberOfChannels, maxCount))
    val mux = Module(new CountingIrrevocableMux(gen, numberOfChannels, maxCount))
    val broadcaster = Module(new IrrevocableBroadcaster(commandType, 2))
    demux.io.in <> io.in
    demux.io.out <> mux.io.in
    mux.io.out <> io.out

    demux.io.selectCommand <> broadcaster.io.out(0)
    mux.io.selectCommand <> broadcaster.io.out(1)
    broadcaster.io.in <> io.selectCommand
}

class IrrevocableSwitchTest extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "IrrevocableSwitch"
    behavior of dutName

    def checkResult(c: IrrevocableSwitchTestSystem) {
        c.io.in.initSource().setSourceClock(c.clock)
        c.io.out.initSink().setSinkClock(c.clock)
        c.io.selectCommand.initSource().setSourceClock(c.clock)
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
        } .fork {
            var totalTransfers = 0
            while(totalTransfers < 256) {
                val channel = random.nextInt(c.numberOfChannels)
                val count = random.nextInt(c.maxCount).min(256 - totalTransfers)
                c.io.selectCommand.enqueue(c.commandType.Lit(_.select -> channel.U, _.count -> count.U))
                totalTransfers = totalTransfers + count
            }
        } .join
    }

    it should "simple" in {
        test(new IrrevocableSwitchTestSystem) { c => checkResult(c) }
    }
}
