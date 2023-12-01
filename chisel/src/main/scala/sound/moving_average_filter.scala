// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2023.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sound

import chisel3._
import chisel3.util._

class AudioMovingAverageFilter(val width: Int, val entries: Int) extends Module {
    if(entries <= 0 ) {
        throw new IllegalArgumentException("entries must be greater than 0")
    }
    if( (entries & (entries - 1)) != 0 ) {
        throw new IllegalArgumentException("entries must be a power of 2")
    }
    if(width <= 0 ) {
        throw new IllegalArgumentException("width must be greater than 0")
    }

    val counterBits = log2Ceil(entries + 1)

    val io = IO(new Bundle {
        val dataIn = Flipped(Decoupled(UInt((width*2).W)))
        val dataOut = Decoupled(UInt((width*2).W))
    })
    
    val accumulatorBits = width + log2Ceil(entries)
    val accumulator = RegInit(VecInit((0 to 1).map(_ => 0.S(accumulatorBits.W))))
    
    val dataValid = RegInit(false.B)
    val dataBits = RegInit(0.U((width * 2).W))
    io.dataOut.valid := dataValid
    io.dataOut.bits := dataBits

    when( io.dataOut.fire ) {
        dataValid := false.B
    }

    val next = (!dataValid || io.dataOut.ready) && io.dataIn.valid
    val queue = Module(new Queue(UInt((width * 2).W), entries))
    val filled = RegInit(false.B)
    val lastValue = RegInit(0.U((width * 2).W))
    
    when( queue.io.count === (entries - 1).U && next ) {
        filled := true.B
    }
    
    // The last value queue is must be controlled NOT to be full to enqueue the latest value.
    // So the condition to assert ready signal is the count of the queue is equal to the number of entries - 1 and a new value is available.
    val updateLastValue = next && (queue.io.count === (entries - 1).U || filled)
    io.dataIn.ready := !dataValid || io.dataOut.ready
    queue.io.enq.valid := next
    queue.io.enq.bits := io.dataIn.bits

    queue.io.deq.ready := updateLastValue
    when(updateLastValue) {
        lastValue := queue.io.deq.bits
    }
    when( next ) {
        for( ch <- 0 to 1 ) {
            val value = io.dataIn.bits(width*(ch + 1) - 1, width*ch).asSInt
            val lastChannelValue = lastValue(width*(ch + 1) - 1, width*ch).asSInt
            accumulator(ch) := (accumulator(ch) - lastChannelValue) + value
        }
        dataBits := Cat(accumulator(1)(accumulatorBits - 1, accumulatorBits - width), accumulator(0)(accumulatorBits - 1, accumulatorBits - width))
        dataValid := true.B

        val lastChannelValue = (0 to 1).map(ch => lastValue(width*(ch + 1) - 1, width*ch).asSInt)
        printf(p"[AudioMovingAverageFilter] accumulator(0): ${Hexadecimal(accumulator(0))} accumulator(1): ${Hexadecimal(accumulator(1))} lastChannelValue(0): ${Hexadecimal(lastChannelValue(0))} lastChannelValue(1): ${Hexadecimal(lastChannelValue(1))} dataBits: ${Hexadecimal(dataBits)}\n")
    }
}