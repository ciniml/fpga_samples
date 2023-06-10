// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import segled._
import chisel3.stage.ChiselStage
import segled.SegmentLedWithShiftRegs

@chiselName
class MultiSegmentLed() extends RawModule {
  val clock = IO(Input(Clock()))
  val resetn = IO(Input(Bool()))
  
  val com_ser = IO(Output(Bool()))
  val com_rclk = IO(Output(Bool()))
  val com_srclk = IO(Output(Bool()))
  val com_oe = IO(Output(Bool()))
  val seg_ser = IO(Output(Bool()))
  val seg_rclk = IO(Output(Bool()))
  val seg_srclk = IO(Output(Bool()))
  val seg_oe = IO(Output(Bool()))

  withClockAndReset(clock, !resetn) {
    val led = Module(new SegmentLedWithShiftRegs(8, 6, 2, 2700, true, true))
    com_ser   := led.io.digitSelector.data
    com_rclk  := led.io.digitSelector.latch
    com_srclk := led.io.digitSelector.shiftClock
    com_oe    := led.io.digitSelector.outputEnable
    seg_ser   := led.io.segmentOut.data
    seg_rclk  := led.io.segmentOut.latch
    seg_srclk := led.io.segmentOut.shiftClock
    seg_oe    := led.io.segmentOut.outputEnable

    val numberOfAllSegments = 8 * 6;
    val allSegments = RegInit(1.U(numberOfAllSegments.W))
    val segmentUpdateInterval = 500 * 27*1000
    val segmentUpdateCounter = RegInit(0.U(log2Ceil(segmentUpdateInterval - 1).W))

    when(segmentUpdateCounter === (segmentUpdateInterval - 1).U) {
      segmentUpdateCounter := 0.U
      allSegments := Cat(allSegments(numberOfAllSegments - 2, 0), allSegments(numberOfAllSegments - 1))
    } .otherwise {
      segmentUpdateCounter := segmentUpdateCounter + 1.U
    }

    //led.io.digits := VecInit((0 until 6).map(i => allSegments((i + 1) * 8 - 1, i * 8)))
    led.io.digits := VecInit(Seq.fill(6)(0xff.U(8.W)))
  }
}

object ElaborateMultiSegmentLed extends App {
  (new ChiselStage).emitVerilog(new MultiSegmentLed, Array(
    "-o", "multi_segment_led.v",
    "--target-dir", "rtl/chisel/segment_led",
  ))
}
