// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021-2022
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._

class PacketQueue[T <: Data](gen: Flushable[T], val entries: Int) extends Module {
    val io = IO(new Bundle{
        val read = Irrevocable(gen)
        val write = Flipped(Irrevocable(gen))
    })

    val counterBits = log2Ceil(entries + 1)
    val writeCounter = RegInit(0.U(counterBits.W)) 
    val readCounter = RegInit(0.U(counterBits.W))
    val isPacketLast = RegInit(false.B)

    val queue = Module(new Queue(gen.body, entries = entries))

    val enqueueValid = !(readCounter > 0.U && io.write.bits.last)   // Cannot accept a new data if reading the previous packet is not finished and this is the last beat of the current packet.
    io.write.ready := enqueueValid && queue.io.enq.ready
    queue.io.enq.valid := enqueueValid && io.write.valid
    queue.io.enq.bits := io.write.bits.body

    when( io.write.valid && io.write.ready ) {
        when ( io.write.bits.last ) {
            readCounter := writeCounter + 1.U
            isPacketLast := true.B
            writeCounter := 0.U
        } .otherwise {
            writeCounter := writeCounter + 1.U
        }
    } .elsewhen( !queue.io.enq.ready && writeCounter === entries.U  ) {    // Queue is full without the "last" signal is asserted.
        isPacketLast := false.B
        readCounter := writeCounter
        writeCounter := 0.U
    }
    
    io.read.valid := queue.io.deq.valid && readCounter > 0.U
    queue.io.deq.ready := io.read.ready && readCounter > 0.U
    io.read.bits.body := queue.io.deq.bits
    io.read.bits.last := readCounter === 1.U && isPacketLast

    when( io.read.valid && io.read.ready ) {
        readCounter := readCounter - 1.U
    }    
}
