// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import chisel3._
import chisel3.util._
import chisel3.experimental.ChiselEnum
import _root_.util._


// class TakeStreamData(bytesToTake: Int, streamWidth: Int = 1) extends Module {
//     assert(bytesToTake > 0)

//     val io = IO(new Bundle {
//         val in = Flipped(Irrevocable(MultiByteSymbol(streamWidth)))
//         val out = Irrevocable(MultiByteSymbol(streamWidth))
//         val taken = Irrevocable(Flushable(UInt((bytesToTake*8).W)))
//     })

//     val outValid = RegInit(false.B)
//     val outData = RegInit(0.U((streamWidth*8).W))
//     val outLast = RegInit(false.B)
//     val takenValid = RegInit(false.B)

//     val buffer = RegInit(VecInit(Seq.fill(streamWidth)(0.U(8.W))))
//     val bytesTaken = RegInit(0.U(log2Ceil(bytesToTake).W))
//     val isTakenLast = RegInit(false.B)

//     object State extends ChiselEnum {
//         val Take, Tail = Value
//     }
    
//     val state = RegInit(State.Take)

//     when(outValid && io.out.ready) {
//         outValid := false.B
//     }
//     when(takenValid && io.taken.ready) {
//         takenValid := false.B
//     }

//     switch(state) {
//         is(State.Take) {
//             io.in.ready := !takenValid
//             when( io.in.valid && io.in.ready ) {
//                 buffer(bytesTaken) := io.in.bits
                
//                 when(io.in.bits.last) {
//                     bytesTaken := 0.U
//                 } .otherwise {
//                     bytesTaken := bytesTaken + 1.U
//                 }

//                 when( bytesTaken === (bytesToTake - 1).U ) {
//                     takenValid := true.B
//                     when( io.in.bits.last ) {
//                         isTakenLast := true.B
//                         state := State.Take
//                     } .otherwise {
//                         isTakenLast := false.B
//                         state := State.Tail
//                     }
//                 }
//             }
//         }
//         is(State.Tail) {
//             io.in.ready := !outValid || io.out.ready
//             when( io.in.valid && io.in.ready ) {
//                 outValid := true.B
//                 outData := io.in.bits.data
//                 outLast := io.in.bits.last
//                 when( io.in.bits.last ) {
//                     state := State.Take
//                 }
//             }
//         }
//     }

//     io.out.valid := outValid
//     io.out.bits.data := outData
//     io.out.bits.keep := Fill(bytesToTake, 1.U(1.W))
//     io.out.bits.last := outLast

//     io.taken.valid := takenValid
//     io.taken.bits.body := Cat(buffer.reverse)
//     io.taken.bits.last := isTakenLast
// }

class EthernetHeader extends Bundle {
    val source = UInt((8*6).W)
    val destination = UInt((8*6).W)
    val protocol = UInt((8*2).W)
}
object EthernetHeader {
    def apply(value: UInt): EthernetHeader = {
        val header = Wire(new EthernetHeader)
        header.source := value(47, 0)
        header.destination := value(95, 48)
        header.protocol := value(111, 96)
        header
    }
}

class ArpFrame extends Bundle {
    val hardwareType = UInt(16.W)
    val protocolType = UInt(16.W)
    val hlen = UInt(8.W)
    val plen = UInt(8.W)
    val operation = UInt(16.W)
    val sha = UInt(48.W)
    val spa = UInt(32.W)
    val tha = UInt(48.W)
    val tpa = UInt(32.W)
}
object ArpFrame {
    def apply(value: UInt): ArpFrame = {
        val header = Wire(new ArpFrame)
        header.hardwareType := value(16 - 1, 0)
        header.protocolType := value(32 - 1, 16)
        header.hlen := value(40 - 1, 32)
        header.plen := value(48 - 1, 40)
        header.operation := value(64 -1, 48)
        header.sha := value(112 - 1, 64)
        header.spa := value(144 - 1, 112)
        header.tha := value(192 - 1, 144)
        header.tpa := value(224 - 1, 192)
        header
    }
}

class EthernetService(streamWidth: Int = 1) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(MultiByteSymbol(streamWidth)))
        val out = Irrevocable(MultiByteSymbol(streamWidth))
    })

    val maxFrameLength = 2048
    val ethernetHeaderLength = 6 + 6 + 2
    val arpFrameLength = 28
    val hardwareAddress = BigInt("112233445566", 16)
    val ipAddress = BigInt("c0a00a02", 16)  // 192.168.10.2

    val frameBuffer = SyncReadMem(maxFrameLength, UInt(8.W))
    val ethernetHeaderBuffer = RegInit(VecInit(Seq.fill(ethernetHeaderLength)(0.U(8.W))))
    val ethernetHeader = EthernetHeader(Cat(ethernetHeaderBuffer.reverse))

    val protocolHeaderBuffer = RegInit(VecInit(Seq.fill(arpFrameLength)(0.U(8.W))))
    val arpFrame = ArpFrame(Cat(protocolHeaderBuffer.reverse))

    val bytesReceived = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val bytesToWrite = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val bytesWritten = RegInit(0.U(log2Ceil(maxFrameLength).W))

    val inReady = WireDefault(false.B)
    io.in.ready := inReady

    val outData = RegInit(0.U(8.W))
    val outValid = RegInit(false.B)
    val outLast = RegInit(false.B)
    io.out.valid := outValid
    io.out.bits.data := outData
    io.out.bits.keep := Fill(streamWidth, 1.U(1.W))
    io.out.bits.last := outLast
    
    object State extends ChiselEnum {
        val ReadHeader, CheckHeader, Read, Discard, Finalize, Write, ARPLoad, ARPProcess = Value
    }
    
    val state = RegInit(State.ReadHeader)

    when(outValid && io.out.ready) {
        outValid := false.B
    }

    switch(state) {
        is(State.ReadHeader) {
            inReady := true.B
            bytesWritten := 0.U
            bytesToWrite := 0.U
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                ethernetHeaderBuffer(bytesReceived) := io.in.bits.data

                when(io.in.bits.last) { // last is asserted while receiving header.
                    bytesReceived := 0.U
                    state := State.ReadHeader
                } .elsewhen(bytesReceived === (ethernetHeaderLength - 1).U) {
                    state := State.CheckHeader
                }
            }
        }
        is(State.CheckHeader) {
            inReady := false.B
            state := State.Discard // By default, do not process the frame and discard it.
            bytesReceived := 0.U
            when( bytesReceived >= ethernetHeaderLength.U ) {
                switch(ethernetHeader.protocol) {
                    is(0x0806.U) {    // ARP
                        state := State.ARPLoad
                    }
                }
            }
        }
        is(State.Discard) {
            inReady := true.B
            when( io.in.valid && io.in.bits.last ) {
                bytesReceived := 0.U
                state := State.Read
            }
        }

        is(State.Finalize) {
            inReady := false.B
            bytesReceived := 0.U
            state := State.Read
        }

        is(State.Write) {
            inReady := false.B
            when(!outValid || io.out.ready) {
                val isLast = bytesWritten === bytesToWrite - 1.U
                outValid := true.B
                outLast := isLast
                outData := protocolHeaderBuffer(bytesWritten)
                bytesWritten := bytesWritten + 1.U
                when(isLast) {
                    state := State.Read
                }
            }
        }
        // ARP process
        is(State.ARPLoad) {
            inReady := true.B
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                protocolHeaderBuffer(bytesReceived) := io.in.bits.data
                when( io.in.bits.last ) {
                    state := State.Finalize
                    when( bytesReceived === arpFrameLength.U && arpFrame.operation === 0x0001.U && arpFrame.tpa === ipAddress.U ) {
                        state := State.ARPProcess
                    }
                } .elsewhen( bytesReceived === (arpFrameLength - 1).U ){
                    state := State.Discard  // Invalid ARP frame length. discard.
                }
            }
        }
        is(State.ARPProcess) {
            // Update headers.
            inReady := false.B
            arpFrame.operation := 0x0002.U
            arpFrame.tha := arpFrame.sha
            arpFrame.tpa := arpFrame.spa
            arpFrame.sha := hardwareAddress.U
            arpFrame.spa := ipAddress.U
            ethernetHeader.destination := ethernetHeader.source
            ethernetHeader.source := hardwareAddress.U
            bytesToWrite := arpFrameLength.U
            state := State.Write
        }
    }
}