// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import org.scalatest._
import chiseltest._
import chisel3._
import scala.util.control.Breaks
import chisel3._
import chisel3.util._
import java.io.FileInputStream
import scala.collection.mutable
import _root_.util.AsyncFIFO

class VideoTestSystem() extends Module {
  val params = new VideoParams(16, 2, 16, 4, 3, 32, 5, 2, 1)  
  val io = IO(new Bundle{
    val video = new VideoIO(params.pixelBits)
    val dataInSync = Output(Bool())
  })

  val dut = Module(new VideoSignalGenerator(params, params))
  val tpg = Module(new TestPatternGenerator(params.pixelBits, params.pixelsH, params.pixelsV, rectSize = 2))

  io.dataInSync <> dut.io.dataInSync
  io.video <> dut.io.video
  dut.io.data <> tpg.io.data
  dut.io.config.bits := VideoConfig(params).default(params)
  dut.io.config.valid := false.B
}

class VideoTester extends FlatSpec with ChiselScalatestTester with Matchers {
    val dutName = "VideoSignalGenerator"
    behavior of dutName

    it should "simple" in {
        test(new VideoTestSystem) { c =>
            c.clock.setTimeout(2000)
            c.clock.step(1)
            c.io.dataInSync.expect(false.B)
            while(!c.io.dataInSync.peek.litToBoolean) {
                c.clock.step(1)
            }
            c.io.dataInSync.expect((true.B))
            (0 to 1500).foreach(i => {
                c.io.dataInSync.expect(true.B, f"Data not sync at ${i}")
                c.clock.step(1)
            })
        }
    }
}
