// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import chiseltest._
import chisel3.util._
import chisel3._
import chisel3.experimental.BundleLiterals._
import _root_.util._
import scala.util.control.Breaks
import scala.util.Random
import java.io._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import chisel3.stage.PrintFullStackTraceAnnotation
import scala.util.Success
import scala.util.Failure
import display.HUB75Controller
import display.HUB75IO

class HUB75TestSystem(pixels: Seq[Int]) extends Module {
    val io = IO(new Bundle{
        val hub75 = HUB75IO()
    })

    val dut = Module(new HUB75Controller)
    val mem = RegInit(VecInit(pixels.map(n => n.U(3.W))))
    dut.io.panelPixels(0).pixel := mem(dut.io.panelPixels(0).address)
    io.hub75 <> dut.io.hub75
}

class HUB75Tester extends AnyFlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "HUB75"
    behavior of dutName
    
    def run(c: HUB75TestSystem, pixels: Seq[Int]): Unit = {
        var outputEnableCounter = 0
        var latchY = 0
        c.clock.setTimeout(2000)
        c.clock.step(1)
        for(y <- 0 to 16) {
            for(x <- 0 to 63) {
                if( x == 63 ) {
                    outputEnableCounter = 7
                    latchY = y
                }
                val pixel = pixels((y & 15)*64 + x)
                c.io.hub75.oe.expect(outputEnableCounter > 0)
                c.io.hub75.lat.expect(x == 63)
                c.io.hub75.row_a.expect((latchY & 1) != 0)
                c.io.hub75.row_b.expect((latchY & 2) != 0)
                c.io.hub75.row_c.expect((latchY & 4) != 0)
                c.io.hub75.row_d.expect((latchY & 8) != 0)
                c.io.hub75.r.expect(if((pixel & 4) != 0) { 1.U } else { 0.U })
                c.io.hub75.g.expect(if((pixel & 2) != 0) { 1.U } else { 0.U })
                c.io.hub75.b.expect(if((pixel & 1) != 0) { 1.U } else { 0.U })
                if( outputEnableCounter > 0 ) {  
                    outputEnableCounter = outputEnableCounter - 1
                }
                c.clock.step(1)
            }
        }
    }


    val pixels = (0 to 64*16-1).map(n => n & 7).toIndexedSeq
    
    it should "run" in {
        test(new HUB75TestSystem(pixels)).withAnnotations(Seq(PrintFullStackTraceAnnotation, VerilatorBackendAnnotation, WriteFstAnnotation)) { c => run(c, pixels) }
    }
}

