// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package gowin

import org.scalatest._
import chiseltest._
import chisel3._
import chisel3.experimental.BundleLiterals._
import system.SDRAMTestSystem
import scala.util.control.Breaks
import scala.util.Random
import axi._

class SDRAMTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "SDRCBridge"
    behavior of dutName

    it should "no burst" in {
        test(new SDRAMTestSystem) { c =>
            val params = c.io.axi.params
            val arbits = chiselTypeOf(c.io.axi.ar.get.bits)
            val awbits = chiselTypeOf(c.io.axi.aw.get.bits)
            val wbits = chiselTypeOf(c.io.axi.w.get.bits)
            val rbits = chiselTypeOf(c.io.axi.r.get.bits)
            val bbits = chiselTypeOf(c.io.axi.b.get.bits)

            c.io.axi.aw.get.initSource().setSourceClock(c.clock)
            c.io.axi.ar.get.initSource().setSourceClock(c.clock)
            c.io.axi.w.get.initSource().setSourceClock(c.clock)
            c.io.axi.r.get.initSink().setSinkClock(c.clock)
            c.io.axi.b.get.initSink().setSinkClock(c.clock)

            c.io.axi.r.get.expectInvalid()
            c.io.axi.b.get.expectInvalid()

            val random = new Random(42)
            (0 to 128).foreach{ _ =>
                val address = (BigInt(params.addressBits, Random) >> 2) << 2
                val data = BigInt(params.dataBits, Random)
                println(f"Address: ${address}, Data: ${data}")
                c.io.axi.aw.get.enqueueNow(awbits.Lit(_.addr -> address.U, _.len.get -> 0.U))
                c.clock.step(1)
                c.io.axi.w.get.enqueueNow(wbits.Lit(_.data -> data.U, _.strb -> "b1111".U, _.last.get -> true.B))
                c.clock.step(1)
                c.io.axi.b.get.expectDequeue(bbits.Lit(_.resp -> AXI4Resp.OKAY))
                c.clock.step(1)
                c.io.axi.ar.get.enqueueNow(arbits.Lit(_.addr -> address.U, _.len.get -> 0.U))
                c.clock.step(1)
                c.io.axi.r.get.expectDequeue(rbits.Lit(_.data -> data.U, _.last.get -> true.B, _.resp -> AXI4Resp.OKAY))
            }
            c.clock.step(10)
        }
    }

    it should "random bursts" in {
        test(new SDRAMTestSystem) { c =>
            val params = c.io.axi.params
            val arbits = chiselTypeOf(c.io.axi.ar.get.bits)
            val awbits = chiselTypeOf(c.io.axi.aw.get.bits)
            val wbits = chiselTypeOf(c.io.axi.w.get.bits)
            val rbits = chiselTypeOf(c.io.axi.r.get.bits)
            val bbits = chiselTypeOf(c.io.axi.b.get.bits)

            c.io.axi.aw.get.initSource().setSourceClock(c.clock)
            c.io.axi.ar.get.initSource().setSourceClock(c.clock)
            c.io.axi.w.get.initSource().setSourceClock(c.clock)
            c.io.axi.r.get.initSink().setSinkClock(c.clock)
            c.io.axi.b.get.initSink().setSinkClock(c.clock)

            c.io.axi.r.get.expectInvalid()
            c.io.axi.b.get.expectInvalid()

            val random = new Random(42)
            (0 to 128).foreach{ _ =>
                val address = (BigInt(params.addressBits, Random) >> 2) << 2
                val burstLen = random.nextInt(7)
                val dataSeq = (0 to burstLen).map(_ => BigInt(params.dataBits, Random))
                println(f"""Address: ${address}, BurstLen: ${burstLen}, Data: ${dataSeq.map(value => value.toString(16)).mkString(",")}""")
                c.io.axi.aw.get.enqueueNow(awbits.Lit(_.addr -> address.U, _.len.get -> burstLen.U))
                c.clock.step(1)
                c.io.axi.w.get.enqueueSeq((0 to burstLen).map(index => 
                    wbits.Lit(_.data -> dataSeq(index).U, _.strb -> "b1111".U, _.last.get -> (index == burstLen).B)))
                c.clock.step(1)
                c.io.axi.b.get.expectDequeue(bbits.Lit(_.resp -> AXI4Resp.OKAY))
                c.clock.step(1)
                c.io.axi.ar.get.enqueueNow(arbits.Lit(_.addr -> address.U, _.len.get -> burstLen.U))
                c.clock.step(1)
                c.io.axi.r.get.expectDequeueSeq((0 to burstLen).map(index => 
                    rbits.Lit(_.data -> dataSeq(index).U, _.last.get -> (index == burstLen).B, _.resp -> AXI4Resp.OKAY)))
            }
            c.clock.step(10)
        }
    }
}
