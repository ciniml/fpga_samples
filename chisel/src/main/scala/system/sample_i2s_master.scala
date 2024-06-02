// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._

import _root_.circt.stage.ChiselStage

import sound._


class I2sMasterSystem() extends RawModule {
  val clock = IO(Input(Clock()))
  val reset = IO(Input(Bool()))
  val out_ws = IO(Output(Bool()))
  val out_bclk = IO(Output(Bool()))
  val out_data = IO(Output(Bool()))

  withClockAndReset(clock, reset) {
    val clockHz = 36000000  // 36MHz
    val sampleRate = 48000
    val master = Module(new I2sMaster(16, clockHz / sampleRate / 2, 0))

    val clockEnable = RegInit(false.B)
    clockEnable := !clockEnable
    master.io.clockEnable := clockEnable
    out_bclk := clockEnable    
    out_data := master.io.dataOut
    out_ws := master.io.wordSelect

    val counter = RegInit(0.U(16.W))
    val duration = sampleRate / 440 / 2
    val out = Mux(counter < (duration/2).U, 0x7fff.U(16.W), 0x8000.U(16.W))
    //master.io.dataIn.bits := Cat(counter, counter + 16384.U)
    master.io.dataIn.bits := Cat(out, out)
    master.io.dataIn.valid := true.B
    when(master.io.dataIn.ready) {
      counter := counter + 1.U
      when(counter === (duration - 1).U) {
        counter := 0.U
      }
    }
  }
}

object ElaborateI2sMasterSystem extends App {
  ChiselStage.emitSystemVerilogFile(new I2sMasterSystem, Array(
    "-o", "i2s_master_system.v",
    "--target-dir", "rtl/chisel/i2s_master_system",
  ))
}
