// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._

class AudioMixer(val width: Int, val channels: Int, val defaultValue: BigInt) extends Module {
    if(width <= 0 ) {
        throw new IllegalArgumentException("width must be greater than 0")
    }
    if(channels <= 0 ) {
        throw new IllegalArgumentException("channels must be greater than 0")
    }

    val io = IO(new Bundle {
        val dataIn = Vec(channels, Flipped(Decoupled(UInt((width*2).W))))
        val dataOut = Decoupled(UInt((width*2).W))
    })

    val accumulatorBits = log2Ceil(channels) + width
    val accumulator = RegInit(VecInit((0 to 1).map(_ => 0.S(accumulatorBits.W))))
    val channelSelector = RegInit(1.U(channels.W))
    

    val dataOutValid = RegInit(false.B)
    val dataOutBits = RegInit(0.U((width*2).W))
    io.dataOut.bits := dataOutBits
    io.dataOut.valid := dataOutValid

    when(io.dataOut.fire) {
        dataOutValid := false.B
    }

    val running = RegInit(false.B)
    val dataPending = RegInit(false.B)

    when( !running && !dataPending ) {
        running := true.B
    } .elsewhen( running && channelSelector(channels - 1) ) {
        running := false.B
        dataPending := true.B
    }

    when( running ) {
        if( channels > 1 ) {
            channelSelector := Cat(channelSelector(channels - 2, 0), channelSelector(channels - 1)) // Rotate left the channel selector.
        } else {
            // No need to update channel selector if there is only one channel.
        }
    }
    
    for(channelIndex <- 0 until channels) {
        io.dataIn(channelIndex).ready := running && channelSelector(channelIndex)
        when( running && channelSelector(channelIndex) ) {
            when(io.dataIn(channelIndex).valid) {
                val channel0 = io.dataIn(channelIndex).bits(width - 1, 0)
                val channel1 = io.dataIn(channelIndex).bits(width*2 - 1, width)
                if( channelIndex == 0 ) {
                    accumulator(0) := channel0.asSInt
                    accumulator(1) := channel1.asSInt
                } else {
                    accumulator(0) := accumulator(0).asSInt + channel0.asSInt
                    accumulator(1) := accumulator(1).asSInt + channel1.asSInt
                }
            } .otherwise {
                if( channelIndex == 0 ) {
                    accumulator(0) := defaultValue.S
                    accumulator(1) := defaultValue.S
                } else {
                    accumulator(0) := accumulator(0).asSInt + defaultValue.S
                    accumulator(1) := accumulator(1).asSInt + defaultValue.S
                }
            }
        }
    }

    // Output the accumulator value.
    when( dataPending && (!dataOutValid || io.dataOut.ready) ) {
        dataOutBits := Cat(accumulator(1)(accumulatorBits - 1, accumulatorBits - width), accumulator(0)(accumulatorBits - 1, accumulatorBits - width))
        dataOutValid := true.B
        dataPending := false.B
    }
}