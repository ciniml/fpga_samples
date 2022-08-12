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
import chisel3.experimental.BundleLiterals._
import scala.util.control.Breaks
import scala.util.Random


class WidthConverterTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "WidthConverter"
    behavior of dutName

    def checkResult(c: WidthConverter, maxRate: Boolean) {
        val bytesPerInput = c.inputWidth / 8
        val bytesPerOutput = c.outputWidth / 8
        c.io.enq.initSource().setSourceClock(c.clock)
        c.io.deq.initSink().setSinkClock(c.clock)
        val enqBitsType = chiselTypeOf(c.io.enq.bits)
        val deqBitsType = chiselTypeOf(c.io.deq.bits)
        val random = new Random
        fork {
            (0 to 255 by bytesPerOutput).foreach(i => {
                val idleCycles = if (random.nextInt(10) < 5 && !maxRate) {random.nextInt(1 + bytesPerOutput*2) + 1} else {0}
                (0 to idleCycles - 1).foreach(i => {
                    c.clock.step(1)
                })
                val bytesExpected = Math.min(256 - i, bytesPerOutput)
                val isLast = i + bytesPerOutput >= 256
                var body = BigInt(0)
                (0 to bytesExpected - 1).foreach(f => {
                    body = body | (BigInt(i + f) << (8*f))
                })
                c.io.deq.expectDequeue(Flushable(c.outputWidth.W).Lit(_.body -> body.U, _.last -> isLast.B))
            })
        } .fork {
            (0 to 255 by bytesPerInput).foreach(i => {
                val idleCycles = if (random.nextInt(10) < 5 && !maxRate) {random.nextInt(1 + bytesPerInput*2) + 1} else {0}
                (0 to idleCycles - 1).foreach(i => {
                    c.clock.step(1)
                })
                val bytesToWrite = Math.min(256 - i, bytesPerInput)
                val isLast = i + bytesPerInput >= 256
                var body = BigInt(0)
                (0 to bytesToWrite - 1).foreach(f => {
                    body = body | (BigInt(i + f) << (8*f))
                })
                c.io.enq.enqueue(Flushable(c.inputWidth.W).Lit(_.body -> body.U, _.last -> isLast.B))
            })
        } .join
    }

    it should "8to16" in {
        test(new WidthConverter(8, 16)) { c => checkResult(c, false) }
    }
    it should "8to24" in {
        test(new WidthConverter(8, 24)) { c => checkResult(c, false) }
    }
    it should "8to32" in {
        test(new WidthConverter(8, 32)) { c => checkResult(c, false) }
    }
    it should "24to32" in {
        test(new WidthConverter(24, 32)) { c => checkResult(c, false) }
    }
    it should "32to24" in {
        test(new WidthConverter(32, 24)) { c => checkResult(c, false) }
    }
    it should "32to24 MaxRate" in {
        test(new WidthConverter(32, 24)) { c => checkResult(c, true) }
    }
}
