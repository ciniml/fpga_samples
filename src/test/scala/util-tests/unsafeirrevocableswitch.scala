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

class UnsafeIrrevocableSwitchTestSystem extends Module {
    val numberOfChannels = 4
    val gen = UInt(8.W)
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
        val select = Input(UInt(log2Ceil(numberOfChannels + 1).W))
    })

    val demux = Module(new IrrevocableUnsafeDemux(gen, numberOfChannels))
    val mux = Module(new IrrevocableUnsafeMux(gen, numberOfChannels))
    demux.io.in <> io.in
    demux.io.out <> mux.io.in
    mux.io.out <> io.out
    demux.io.select <> io.select
    mux.io.select <> io.select
}

class UnsafeIrrevocableSwitchTest extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "UnsafeIrrevocableSwitch"
    behavior of dutName

    def checkResult(c: UnsafeIrrevocableSwitchTestSystem) {
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
        } .fork {
            var totalTransfers = 0
            while(totalTransfers < 256) {
                val channel = random.nextInt(c.numberOfChannels + 1)
                c.io.select.poke(channel.U)
                c.clock.step()
                if( channel < c.numberOfChannels ) {
                    totalTransfers = totalTransfers + 1
                }
            }
        } .join
    }

    it should "simple" in {
        test(new UnsafeIrrevocableSwitchTestSystem) { c => checkResult(c) }
    }
}
