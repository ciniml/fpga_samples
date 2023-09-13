// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._

/**
  * XLS generated AudioMixer logic.
  */
class mixer extends BlackBox {
  val io = IO(new Bundle {
    val clk = Input(Clock())
    val reset = Input(Bool())
    val mixer__inputs_ch = Input(UInt(64.W))
    val mixer__inputs_ch_vld = Input(Bool())
    val mixer__inputs_ch_rdy = Output(Bool())
    val mixer__volumes_ch = Input(UInt(64.W))
    val mixer__volumes_ch_vld = Input(Bool())
    val mixer__volumes_ch_rdy = Output(Bool())
    val mixer__output_ch = Output(UInt(32.W))
    val mixer__output_ch_vld = Output(Bool())
    val mixer__output_ch_rdy = Input(Bool())
  })
}

class AudioMixerXls(val width: Int, val channels: Int, val defaultValue: BigInt) extends Module {
    if(width != 16 ) {
        throw new IllegalArgumentException("width must be 16")
    }
    if(channels != 2 ) {
        throw new IllegalArgumentException("channels must be 2")
    }

    val io = IO(new Bundle {
        val dataIn = Vec(channels, Flipped(Irrevocable(UInt((width*2).W))))
        val volumeIn = Vec(channels, Flipped(Irrevocable(UInt((width*2).W))))
        val dataOut = Irrevocable(UInt((width*2).W))
    })

    val xls = Module(new mixer)
    xls.io.clk := clock
    xls.io.reset := reset
    
    val ch0Bits = io.dataIn(0).bits
    val ch1Bits = io.dataIn(1).bits
    xls.io.mixer__inputs_ch := Cat(ch1Bits, ch0Bits)
    val inValid = io.dataIn(1).valid && io.dataIn(0).valid
    xls.io.mixer__inputs_ch_vld := inValid
    io.dataIn(0).ready := xls.io.mixer__inputs_ch_rdy && io.dataIn(1).valid
    io.dataIn(1).ready := xls.io.mixer__inputs_ch_rdy && io.dataIn(0).valid

    xls.io.mixer__volumes_ch := Cat(io.volumeIn(1).bits, io.volumeIn(0).bits)
    val volumeValid = io.volumeIn(1).valid && io.volumeIn(0).valid
    xls.io.mixer__volumes_ch_vld := volumeValid
    io.volumeIn(0).ready := xls.io.mixer__volumes_ch_rdy
    io.volumeIn(1).ready := xls.io.mixer__volumes_ch_rdy

    io.dataOut.bits := xls.io.mixer__output_ch
    io.dataOut.valid := xls.io.mixer__output_ch_vld
    xls.io.mixer__output_ch_rdy := io.dataOut.ready
}