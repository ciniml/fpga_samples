// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._

class AudioBuffer(val width: Int, val entries: Int, val threshold: Int) extends Module {
    if(threshold > entries) {
        throw new IllegalArgumentException("threshold must be less than or equal to entries")
    }
    if(entries <= 0 ) {
        throw new IllegalArgumentException("entries must be greater than 0")
    }
    if(width <= 0 ) {
        throw new IllegalArgumentException("width must be greater than 0")
    }

    val counterBits = log2Ceil(entries + 1)

    val io = IO(new Bundle {
        val dataIn = Flipped(Decoupled(UInt(width.W)))
        val dataOut = Decoupled(UInt(width.W))
        val buffering = Output(Bool())
        val bufferedEntries = Output(UInt(counterBits.W))
    })

    val bufferOut = Queue(io.dataIn, entries)
    val buffering = RegInit(true.B)
    val bufferedEntries = RegInit(0.U(counterBits.W))

    // Do not output data while buffering is in progress.
    io.dataOut.valid := bufferOut.valid && !buffering
    bufferOut.ready := io.dataOut.ready && !buffering
    io.dataOut.bits := bufferOut.bits

    io.buffering := buffering
    io.bufferedEntries := bufferedEntries

    when( io.dataIn.fire && !io.dataOut.fire ) {
        bufferedEntries := bufferedEntries + 1.U
    } .elsewhen( !io.dataIn.fire && io.dataOut.fire ) {
        bufferedEntries := bufferedEntries - 1.U
    }

    // If the buffer is empty, start buffering.
    when( bufferedEntries === 0.U ) {
        buffering := true.B
    } .elsewhen( buffering && bufferedEntries >= threshold.U ) {
        // If number of items in the buffer is greater than or equal to the threshold, stop buffering and start outputting.
        buffering := false.B
    }
}