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

object NetworkBytes {
    def apply(value: UInt, from: Int, toInclusive: Int): UInt = {
        Cat((from to toInclusive).map(i => value((i+1)*8-1, i*8)))
    }
}
object FlipBytes {
    def apply(value: UInt): UInt = {
        val bytes = value.getWidth / 8
        Cat((0 to bytes-1).map(i => value((i+1)*8-1, i*8)))
    }
}
object Bytes {
    def apply(value: UInt): Vec[UInt] = {
        val bytes = value.getWidth / 8
        VecInit((0 to bytes-1).map(i => value((i+1)*8-1, i*8)))
    }
}
class EthernetHeader extends Bundle {
    val source = UInt((8*6).W)
    val destination = UInt((8*6).W)
    val protocol = UInt((8*2).W)

    def toUInt(): UInt = {
        Cat(
            FlipBytes(protocol),
            FlipBytes(source),
            FlipBytes(destination),
        )
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}
object EthernetHeader {
    def apply(value: UInt): EthernetHeader = {
        val header = Wire(new EthernetHeader)
        header.destination := NetworkBytes(value, 0, 5)
        header.source := NetworkBytes(value, 6, 11)
        header.protocol := NetworkBytes(value, 12, 13)
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

    def toUInt(): UInt = {
        Cat(Seq(
            FlipBytes(hardwareType),
            FlipBytes(protocolType),
            FlipBytes(hlen),
            FlipBytes(plen),
            FlipBytes(operation),
            FlipBytes(sha),
            FlipBytes(spa),
            FlipBytes(tha),
            FlipBytes(tpa),
        ).reverse)
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}
object ArpFrame {
    def apply(value: UInt): ArpFrame = {
        val header = Wire(new ArpFrame)
        header.hardwareType := NetworkBytes(value, 0, 1)
        header.protocolType := NetworkBytes(value, 2, 3)
        header.hlen := NetworkBytes(value, 4, 4)
        header.plen := NetworkBytes(value, 5, 5)
        header.operation := NetworkBytes(value, 6, 7)
        header.sha := NetworkBytes(value, 8, 13)
        header.spa := NetworkBytes(value, 14, 17)
        header.tha := NetworkBytes(value, 18, 23)
        header.tpa := NetworkBytes(value, 24, 27)
        header
    }
}

class Ipv4Header extends Bundle {
    val version = UInt(8.W)
    val type_ = UInt(8.W)
    val length = UInt(16.W)
    val identification = UInt(16.W)
    val flags_and_offset = UInt(16.W)
    val time_to_live = UInt(8.W)
    val protocol = UInt(8.W)
    val header_checksum = UInt(16.W)
    val source = UInt(32.W)
    val destination = UInt(32.W)

    def toUInt(): UInt = {
        Cat(Seq(
            FlipBytes(version),
            FlipBytes(type_),
            FlipBytes(length),
            FlipBytes(identification),
            FlipBytes(flags_and_offset),
            FlipBytes(time_to_live),
            FlipBytes(protocol),
            FlipBytes(header_checksum),
            FlipBytes(source),
            FlipBytes(destination),
        ).reverse)
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}
object Ipv4Header {
    def apply(value: UInt): Ipv4Header = {
        val header = Wire(new Ipv4Header)
        header.version := NetworkBytes(value, 0, 0)
        header.type_ := NetworkBytes(value, 1, 1)
        header.length := NetworkBytes(value, 2, 3)
        header.identification := NetworkBytes(value, 4, 5)
        header.flags_and_offset := NetworkBytes(value, 6, 7)
        header.time_to_live := NetworkBytes(value, 8, 8)
        header.protocol := NetworkBytes(value, 9, 9)
        header.header_checksum := NetworkBytes(value, 10, 11)
        header.source := NetworkBytes(value, 12, 15)
        header.destination := NetworkBytes(value, 16, 19)
        header
    }
}


class IcmpHeader extends Bundle {
    val type_ = UInt(8.W)
    val code = UInt(8.W)
    val checksum = UInt(16.W)
    val identifier = UInt(16.W)
    val sequence_number = UInt(16.W)

    def toUInt(): UInt = {
        Cat(Seq(
            FlipBytes(type_),
            FlipBytes(code),
            FlipBytes(checksum),
            FlipBytes(identifier),
            FlipBytes(sequence_number),
        ).reverse)
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}

object IcmpHeader {
    def apply(value: UInt): IcmpHeader = {
        val header = Wire(new IcmpHeader)
        header.type_ := NetworkBytes(value, 0, 0)
        header.code := NetworkBytes(value, 1, 1)
        header.checksum := NetworkBytes(value, 2, 3)
        header.identifier := NetworkBytes(value, 4, 5)
        header.sequence_number := NetworkBytes(value, 6, 7)
        header
    }
}

case class EthernetServiceConfig(val hardwareAddress: BigInt, val ipAddress: BigInt)
object EthernetServiceConfig {
    def default(): EthernetServiceConfig = {
        new EthernetServiceConfig(
            BigInt("112233445566", 16), // 11:22:33:44:55:66
            BigInt("c0a80a02", 16),     // 192.168.10.2
        )
    }
}

class EthernetService(config: EthernetServiceConfig = EthernetServiceConfig.default(), streamWidth: Int = 1) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(Irrevocable(MultiByteSymbol(streamWidth)))
        val out = Irrevocable(MultiByteSymbol(streamWidth))
    })

    val maxFrameLength = 2048
    val minFrameLength = 64
    val ethernetHeaderLength = 6 + 6 + 2
    val arpFrameLength = 28
    val ipv4HeaderLength = 20
    val icmpHeaderLength = 8
    val maxProtocolHeaderLength = Seq(arpFrameLength, ipv4HeaderLength + icmpHeaderLength).max(Ordering.Int)

    val hardwareAddress = config.hardwareAddress
    val ipAddress = config.ipAddress

    val frameBuffer = Mem(maxFrameLength, UInt(8.W))
    val frameBufferReg = RegInit(0.U(8.W))
    val ethernetHeaderBuffer = RegInit(VecInit(Seq.fill(ethernetHeaderLength)(0.U(8.W))))
    val ethernetHeader = EthernetHeader(Cat(ethernetHeaderBuffer.reverse))
    
    val protocolHeaderBuffer = RegInit(VecInit(Seq.fill(maxProtocolHeaderLength)(0.U(8.W))))
    val arpFrame = ArpFrame(Cat(protocolHeaderBuffer.reverse))
    val ipv4Header = Ipv4Header(Cat(protocolHeaderBuffer.reverse))
    val icmpHeader = IcmpHeader(Cat(protocolHeaderBuffer.iterator.drop(ipv4HeaderLength).toIndexedSeq.reverse))

    val bytesReceived = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val headerBytesToWrite = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val payloadBytesToWrite = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val bytesWritten = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val paddingRemaining = RegInit(0.U(log2Ceil(minFrameLength).W))


    val inReady = WireDefault(false.B)
    io.in.ready := inReady

    val outData = RegInit(0.U(8.W))
    val outValid = RegInit(false.B)
    val outLast = RegInit(false.B)
    io.out.valid := outValid
    io.out.bits.data := outData
    io.out.bits.keep := Fill(streamWidth, 1.U(1.W))
    io.out.bits.last := outLast
    
    def onesComplementAdd(lhs: UInt, rhs: UInt): UInt = {
        val add = lhs +& rhs    // +& is widening add operator, which automatically widen the width of the result to hold the carry bit.
        add(15, 0) + add(16)
    }

    object State extends ChiselEnum {
        val ReadHeader, CheckHeader, Discard, Finalize, WriteEthernetHeader, WriteProtocolHeader, WritePayload, WritePadding, 
            ARPLoad, ARPProcess, 
            IPv4Load, IPv4Process, 
            ICMPLoad, ICMPProcess = Value
    }
    
    val state = RegInit(State.ReadHeader)

    when(outValid && io.out.ready) {
        outValid := false.B
    }

    switch(state) {
        is(State.ReadHeader) {
            inReady := true.B
            bytesWritten := 0.U
            headerBytesToWrite := 0.U
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
            switch(ethernetHeader.protocol) {
                is(0x0800.U) {  // IP
                    state := State.IPv4Load
                }
                is(0x0806.U) {  // ARP
                    state := State.ARPLoad
                }

            }
            printf(p"[ETHERNET] header src=${Hexadecimal(ethernetHeader.source)} dst=${Hexadecimal(ethernetHeader.destination)} proto=${Hexadecimal(ethernetHeader.protocol)}\n")
        }
        is(State.Discard) {
            inReady := true.B
            when( io.in.valid && io.in.bits.last ) {
                bytesReceived := 0.U
                state := State.ReadHeader
            }
        }

        is(State.Finalize) {
            inReady := false.B
            bytesReceived := 0.U
            state := State.ReadHeader
        }
        is(State.WriteEthernetHeader) {
            inReady := false.B
            when(!outValid || io.out.ready) {
                val isLast = bytesWritten === (ethernetHeaderLength - 1).U
                outValid := true.B
                outLast := isLast && headerBytesToWrite === 0.U
                outData := ethernetHeaderBuffer(bytesWritten)
                bytesWritten := bytesWritten + 1.U
                when(isLast) {
                    bytesWritten := 0.U
                    when( headerBytesToWrite === 0.U ) {
                        state := State.Finalize
                    } .otherwise {
                        state := State.WriteProtocolHeader
                    }
                }
            }
            when( (headerBytesToWrite + payloadBytesToWrite) < (minFrameLength - ethernetHeaderLength).U ) {
                paddingRemaining := (minFrameLength - ethernetHeaderLength).U - (headerBytesToWrite + payloadBytesToWrite)
            }
        }
        is(State.WriteProtocolHeader) {
            inReady := false.B
            when(!outValid || io.out.ready) {
                val isLast = bytesWritten === headerBytesToWrite - 1.U
                outValid := true.B
                outLast := isLast && paddingRemaining === 0.U && payloadBytesToWrite === 0.U
                outData := protocolHeaderBuffer(bytesWritten)
                bytesWritten := bytesWritten + 1.U
                when(isLast) {
                    when( payloadBytesToWrite > 0.U ) {
                        bytesWritten := 0.U
                        frameBufferReg := frameBuffer.read(0.U)
                        state := State.WritePayload
                    } .elsewhen( paddingRemaining > 0.U) {
                        state := State.WritePadding
                    } .otherwise {
                        state := State.Finalize
                    }
                }
            }
        }
        is(State.WritePayload) {
            inReady := false.B
            when(!outValid || io.out.ready) {
                val isLast = bytesWritten === payloadBytesToWrite - 1.U
                outValid := true.B
                outLast := isLast && paddingRemaining === 0.U
                outData := frameBufferReg
                frameBufferReg := frameBuffer.read(bytesWritten + 1.U)
                bytesWritten := bytesWritten + 1.U
                when(isLast) {
                    when( paddingRemaining > 0.U) {
                        state := State.WritePadding
                    } .otherwise {
                        state := State.Finalize
                    }
                }
            }
        }
        is(State.WritePadding) {
            inReady := false.B
            when(!outValid || io.out.ready) {
                paddingRemaining := paddingRemaining - 1.U
                val isLast = paddingRemaining === 1.U
                outValid := true.B
                outLast := isLast
                outData := 0.U
                when(isLast) {
                    state := State.Finalize
                }
            }
        }
        // ARP process
        is(State.ARPLoad) {
            inReady := true.B
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                when(bytesReceived < arpFrameLength.U) {
                    protocolHeaderBuffer(bytesReceived) := io.in.bits.data
                }
                when( io.in.bits.last ) {
                    when( bytesReceived >= (arpFrameLength - 1).U ) {
                        state := State.ARPProcess
                    } .otherwise {
                        // Incomplete frame length
                        state := State.Finalize
                    }
                }
            }
        }
        is(State.ARPProcess) {
            val isValid = arpFrame.operation === 0x0001.U && arpFrame.tpa === ipAddress.U
            state := State.Finalize
            printf(p"[ETHERNET] arp bytesReceived=${bytesReceived} op=${arpFrame.operation} tpa=${Hexadecimal(arpFrame.tpa)}  valid=${isValid}\n")
            // Update headers.
            val newArpFrame = WireDefault(arpFrame)
            val newEthernetHeader = WireDefault(ethernetHeader)
            inReady := false.B
            newArpFrame.operation := 0x0002.U
            newArpFrame.tha := arpFrame.sha
            newArpFrame.tpa := arpFrame.spa
            newArpFrame.sha := hardwareAddress.U
            newArpFrame.spa := ipAddress.U
            newEthernetHeader.destination := ethernetHeader.source
            newEthernetHeader.source := hardwareAddress.U
            protocolHeaderBuffer := newArpFrame.toBytes() ++ Seq.fill(maxProtocolHeaderLength - arpFrameLength)(0.U(8.W))
            ethernetHeaderBuffer := newEthernetHeader.toBytes()
            headerBytesToWrite := arpFrameLength.U
            payloadBytesToWrite := 0.U

            when(isValid) {
                state := State.WriteEthernetHeader
            } .otherwise {
                state := State.Finalize
            }
        }
        // IPv4 process
        is(State.IPv4Load) {
            inReady := true.B
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                when(bytesReceived < ipv4HeaderLength.U) {
                    protocolHeaderBuffer(bytesReceived) := io.in.bits.data
                }
                when( io.in.bits.last ) {
                    // Not enough length
                    state := State.Finalize
                } .elsewhen( bytesReceived === (ipv4HeaderLength - 1).U ) {
                    state := State.IPv4Process
                }
            }
        }
        is(State.IPv4Process) {
            inReady := false.B
            printf(p"[ETHERNET] ipv4 bytesReceived=${bytesReceived} destination=${Hexadecimal(ipv4Header.destination)} protocol=${Hexadecimal(ipv4Header.protocol)}\n")
            state := State.Discard
            when( ipv4Header.destination === ipAddress.U ) {    // Is this for me?
                switch(ipv4Header.protocol) {
                    is(0x01.U) {  // ICMP
                        state := State.ICMPLoad
                    }
                    // TODO: add UDP handler
                }
            }
        }
        // ICMP process
        is(State.ICMPLoad) {
            inReady := true.B
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                when(bytesReceived < (ipv4HeaderLength + icmpHeaderLength).U) {
                    protocolHeaderBuffer(bytesReceived) := io.in.bits.data
                } .otherwise {
                    // Store payload to the frame buffer
                    frameBuffer.write(bytesReceived - (ipv4HeaderLength + icmpHeaderLength).U, io.in.bits.data)
                }
                when( io.in.bits.last ) {
                    when( bytesReceived < (ipv4HeaderLength + icmpHeaderLength - 1).U) {
                        // Not enough length
                        state := State.Finalize
                    } .otherwise {
                        state := State.ICMPProcess
                    }
                }
            }
        }
        is(State.ICMPProcess) {
            // Refers RFC1624 Eqn.3 (https://datatracker.ietf.org/doc/html/rfc1624)
            val checksumUpdated = ~onesComplementAdd(~icmpHeader.checksum, ~0x0800.U(16.W))
            printf(p"[ETHERNET] icmp bytesReceived=${bytesReceived} checksum=${Hexadecimal(icmpHeader.checksum)} updated=${Hexadecimal(checksumUpdated)}\n")

            val totalHeaderLength = ipv4HeaderLength + icmpHeaderLength
            val newIpv4Header = WireDefault(ipv4Header)
            newIpv4Header.destination := ipv4Header.source
            newIpv4Header.source := ipAddress.U
            // No need to change IPv4 header checksum. (exchanging address does not affect to the checksum.)
            
            val newIcmpHeader = WireDefault(icmpHeader)
            newIcmpHeader.type_ := 0.U  // Set to ICMP echo reply.
            newIcmpHeader.checksum := checksumUpdated // Just subtracting the original `type` field value (ICMP Echo Request)
            
            val newEthernetHeader = WireDefault(ethernetHeader)
            newEthernetHeader.destination := ethernetHeader.source
            newEthernetHeader.source := hardwareAddress.U

            protocolHeaderBuffer := newIpv4Header.toBytes() ++ newIcmpHeader.toBytes() ++ Seq.fill(maxProtocolHeaderLength - totalHeaderLength)(0.U(8.W))
            ethernetHeaderBuffer := newEthernetHeader.toBytes()
            headerBytesToWrite := totalHeaderLength.U
            payloadBytesToWrite := bytesReceived - totalHeaderLength.U

            when(icmpHeader.type_ === 0x08.U) { // Check if this is ICMP Echo Request packet or not.
                state := State.WriteEthernetHeader
            } .otherwise {
                state := State.Finalize
            }
        }
    }
}