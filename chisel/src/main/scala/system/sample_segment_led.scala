// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._

import segled._
import _root_.circt.stage.ChiselStage


class SegmentLedSystem() extends RawModule {
  val clock = IO(Input(Clock()))
  val resetn = IO(Input(Bool()))
  val seg_a = IO(Output(Bool()))
  val seg_b = IO(Output(Bool()))
  val seg_c = IO(Output(Bool()))
  val seg_d = IO(Output(Bool()))
  val seg_e = IO(Output(Bool()))
  val seg_f = IO(Output(Bool()))
  val seg_g = IO(Output(Bool()))
  val seg_dp = IO(Output(Bool()))
  val seg_dig1 = IO(Output(Bool()))
  val seg_dig2 = IO(Output(Bool()))
  val seg_dig3 = IO(Output(Bool()))
  val seg_dig4 = IO(Output(Bool()))
  val key_5 = IO(Input(Bool()))
  val key_6 = IO(Input(Bool()))
  val key_7 = IO(Input(Bool()))
  val key_8 = IO(Input(Bool()))

  withClockAndReset(clock, !resetn) {
    val clockFreq = 12000000
    val updateFreq = 1000
    val led = Module(new SevenSegmentLed(4, clockFreq / updateFreq, true))

    seg_dig1 := led.io.digitSelector(0)
    seg_dig2 := led.io.digitSelector(1)
    seg_dig3 := led.io.digitSelector(2)
    seg_dig4 := led.io.digitSelector(3)

    seg_a  := led.io.segmentOut(0)
    seg_b  := led.io.segmentOut(1)
    seg_c  := led.io.segmentOut(2)
    seg_d  := led.io.segmentOut(3)
    seg_e  := led.io.segmentOut(4)
    seg_f  := led.io.segmentOut(5)
    seg_g  := led.io.segmentOut(6)
    seg_dp := led.io.segmentOut(7)

    val counters = RegInit(VecInit((0 to 3).map(_ => 0.U(5.W))))
    val keys = VecInit(key_5, key_6, key_7, key_8)
    val keysReg = RegInit(VecInit((0 to 3).map(_ => 0.U(3.W))))

    for(keyIndex <- 0 to 3) {
      keysReg(keyIndex) := Cat(keys(keyIndex), keysReg(keyIndex)(2, 1))
      when(!keysReg(keyIndex)(1) && keysReg(keyIndex)(0)) {
        counters(keyIndex) := counters(keyIndex) + 1.U
      }
      led.io.digits(keyIndex) := counters(keyIndex);
    }
    // led.io.digits(0) := "x1f".U
    // led.io.digits(1) := "x0a".U
    // led.io.digits(2) := "x05".U
    // led.io.digits(3) := "x11".U
  }
}

object ElaborateSegLed extends App {
  ChiselStage.emitSystemVerilogFile(new SegmentLedSystem, Array(
    "-o", "segment_led.v",
    "--target-dir", "rtl/chisel/segment_led",
  ))
}
