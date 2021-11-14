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


class AsyncFIFOTesterSystem(depthBits: Int, slowWrite: Boolean) extends Module {
    val io = IO(new Bundle{
        val read = Decoupled(UInt(8.W))
        val slowClock = Output(Clock())
        val done = Output(Bool())
    })

    val slowClock = RegInit(true.B)
    slowClock := !slowClock

    io.slowClock := slowClock.asClock

    val readClock = if( slowWrite ) { clock } else { slowClock.asClock }
    val writeClock = if( slowWrite ) { slowClock.asClock } else { clock }
    val dut = Module(new AsyncFIFO(UInt(8.W), depthBits))

    dut.io.readClock := readClock
    dut.io.readReset := reset
    io.read <> dut.io.read 
    dut.io.writeClock := writeClock
    dut.io.writeReset := reset

    val halfFullPrev = RegNext(dut.io.writeHalfFull, false.B)
    when(!halfFullPrev && dut.io.writeHalfFull) {
        printf(p"Half Full")
    }

    withClockAndReset(writeClock, reset) {
        val done = RegInit(false.B)
        val counter = RegInit(0.U(8.W))
        when( !done && dut.io.write.ready ) {
            when(counter === 255.U) {
                done := true.B
            } .otherwise {
                counter := counter + 1.U
            }
        }
        dut.io.write.valid := true.B
        dut.io.write.bits := counter
        io.done := done
    }
}

class AsyncFIFOTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "AsyncFIFO"
    behavior of dutName

    def checkResult(c: AsyncFIFOTesterSystem) {
        c.io.done.expect(false.B)
        c.io.read.initSink.setSinkClock(c.clock)
        val random = new Random
        (0 to 255).foreach(i => {
            val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(1) + 1} else {0}
            (0 to idleCycles - 1).foreach(i => {
                c.io.slowClock.step(1)
            })
            c.io.read.expectDequeue(i.U)
        })
        c.io.done.expect(true.B)
    }

    def checkResultSlow(c: AsyncFIFOTesterSystem) {
        c.io.done.expect(false.B)
        c.io.read.initSink.setSinkClock(c.io.slowClock)
        val random = new Random
        (0 to 255).foreach(i => {
            val idleCycles = if (random.nextInt(10) < 1) {random.nextInt(2) + 1} else {0}
            (0 to idleCycles - 1).foreach(i => {
                c.io.slowClock.step(1)
            })
            c.io.read.expectDequeue(i.U)
        })
        c.io.done.expect(true.B)
    }

    it should "depth 1bit slowWrite" in {
        test(new AsyncFIFOTesterSystem(1, true)) { c => checkResult(c) }
    }
    it should "depth 2bit slowWrite" in {
        test(new AsyncFIFOTesterSystem(2, true)) { c => checkResult(c) }
    }
    it should "depth 3bit slowWrite" in {
        test(new AsyncFIFOTesterSystem(3, true)) { c => checkResult(c) }
    }
    it should "depth 4bit slowWrite" in {
        test(new AsyncFIFOTesterSystem(4, true)) { c => checkResult(c) }
    }
    it should "depth 16bit slowWrite" in {
        test(new AsyncFIFOTesterSystem(16, true)) { c => checkResult(c) }
    }

    it should "depth 1bit slowRead" in {
        test(new AsyncFIFOTesterSystem(1, false)) { c => checkResultSlow(c) }
    }
    it should "depth 2bit slowRead" in {
        test(new AsyncFIFOTesterSystem(2, false)) { c => checkResultSlow(c) }
    }
    it should "depth 3bit slowRead" in {
        test(new AsyncFIFOTesterSystem(3, false)) { c => checkResultSlow(c) }
    }
    it should "depth 4bit slowRead" in {
        test(new AsyncFIFOTesterSystem(4, false)) { c => checkResultSlow(c) }
    }
    it should "depth 16bit slowRead" in {
        test(new AsyncFIFOTesterSystem(16, false)) { c => checkResultSlow(c) }
    }
}
