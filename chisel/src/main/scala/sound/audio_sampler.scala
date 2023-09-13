// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._

class AudioSampler(val width: Int, val channels: Int, val defaultValue: BigInt, val interval: Int) extends Module {
    if(width <= 0 ) {
        throw new IllegalArgumentException("width must be greater than 0")
    }
    if(channels <= 0 ) {
        throw new IllegalArgumentException("channels must be greater than 0")
    }

    val io = IO(new Bundle {
        val dataIn = Vec(channels, Flipped(Decoupled(UInt((width*2).W))))
        val dataOut = Vec(channels, Decoupled(UInt((width*2).W)))
    })

    val counter = RegInit(0.U(log2Ceil(interval).W))

    val dataOutValid = RegInit(VecInit((0 until channels).map(_ => false.B)))
    val dataOutBits = RegInit(VecInit((0 until channels).map(_ => 0.U((width*2).W))))
    val channelDefaultValue = Cat(defaultValue.U(width.W), defaultValue.U(width.W))

    for(ch <- 0 until channels) {
        io.dataIn(ch).ready := counter === 0.U
        io.dataOut(ch).bits := dataOutBits(ch)
        io.dataOut(ch).valid := dataOutValid(ch)
        when( io.dataOut(ch).fire ) {
            dataOutValid(ch) := false.B
        }
    }

    // Samples the input data at the specified interval.
    when(counter === 0.U) {
        for(ch <- 0 until channels) {
            when(!dataOutValid(ch) || io.dataOut(ch).ready) {
                // Output a value even if the input data is not available.
                dataOutValid(ch) := true.B
                // If no data is available, use the default value.
                dataOutBits(ch) := Mux(io.dataIn(ch).valid, io.dataIn(ch).bits, channelDefaultValue)
            }
        }
        counter := (interval - 1).U
    } .otherwise {
        counter := counter - 1.U
    }
}