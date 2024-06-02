// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package ethernet

import chisel3._
import chisel3.util._

import chisel3.experimental.BundleLiterals._
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


class UdpHeader extends Bundle {
    val sourcePort = UInt(16.W)
    val destinationPort = UInt(16.W)
    val dataLength = UInt(16.W)
    val checksum = UInt(16.W)

    

    def toUInt(): UInt = {
        Cat(Seq(
            FlipBytes(sourcePort),
            FlipBytes(destinationPort),
            FlipBytes(dataLength),
            FlipBytes(checksum),
        ).reverse)
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}

object UdpHeader {
    val length = 8
    def apply(value: UInt): UdpHeader = {
        val header = Wire(new UdpHeader)
        header.sourcePort := NetworkBytes(value, 0, 1)
        header.destinationPort := NetworkBytes(value, 2, 3)
        header.dataLength := NetworkBytes(value, 4, 5)
        header.checksum := NetworkBytes(value, 6, 7)
        header
    }
}

class PseudoIpv4Header extends Bundle {
    val sourceAddress = UInt(32.W)
    val destinationAddress = UInt(32.W)
    val reservedZero = UInt(8.W)
    val protocolNumber = UInt(8.W)
    val udpLength = UInt(16.W)
    val sourcePort = UInt(16.W)
    val destinationPort = UInt(16.W)
    val dataLength = UInt(16.W)
    val checksum = UInt(16.W)

    def toUInt(): UInt = {
        Cat(Seq(
            FlipBytes(sourceAddress),
            FlipBytes(destinationAddress),
            FlipBytes(reservedZero),
            FlipBytes(protocolNumber),
            FlipBytes(udpLength),
            FlipBytes(sourcePort),
            FlipBytes(destinationPort),
            FlipBytes(dataLength),
            FlipBytes(checksum),
        ).reverse)
    }
    def toBytes(): Vec[UInt] = {
        Bytes(this.toUInt())
    }
}

object PseudoIpv4Header {
    def apply(value: UInt): PseudoIpv4Header = {
        val header = Wire(new PseudoIpv4Header)
        header.sourceAddress := NetworkBytes(value, 0, 3)
        header.destinationAddress := NetworkBytes(value, 4, 7)
        header.reservedZero := NetworkBytes(value, 8, 8)
        header.protocolNumber := NetworkBytes(value, 9, 9)
        header.udpLength := NetworkBytes(value, 10, 11)
        header.sourcePort := NetworkBytes(value, 12, 13)
        header.destinationPort := NetworkBytes(value, 14, 15)
        header.dataLength := NetworkBytes(value, 16, 17)
        header.checksum := NetworkBytes(value, 18, 19)
        header
    }
    def fromHeaders(ipv4: Ipv4Header, udp: UdpHeader): PseudoIpv4Header = {
        val header = Wire(new PseudoIpv4Header)
        header.sourceAddress := ipv4.source
        header.destinationAddress := ipv4.destination
        header.reservedZero := 0.U
        header.protocolNumber := ipv4.protocol
        header.udpLength := udp.dataLength + 8.U
        header.sourcePort := udp.sourcePort
        header.destinationPort := udp.destinationPort
        header.dataLength := udp.dataLength
        header.checksum := udp.checksum
        header
    }
}

class UdpContext extends Bundle {
    val sourceMacAddress = UInt(48.W)
    val destinationMacAddress = UInt(48.W)
    val sourceAddress = UInt(32.W)
    val destinationAddress = UInt(32.W)
    val sourcePort = UInt(16.W)
    val destinationPort = UInt(16.W)
    val dataLength = UInt(16.W)
}

object UdpContext {
    def apply(ethernet: EthernetHeader, ipv4: Ipv4Header, udp: UdpHeader): UdpContext = {
        val context = Wire(new UdpContext)
        context.sourceMacAddress := ethernet.source
        context.destinationMacAddress := ethernet.destination
        context.sourceAddress := ipv4.source
        context.destinationAddress := ipv4.destination
        context.sourcePort := udp.sourcePort
        context.destinationPort := udp.destinationPort
        context.dataLength := udp.dataLength
        context
    }
    def default(): UdpContext = {
        val context = Wire(new UdpContext)
        context.sourceMacAddress := 0.U
        context.destinationMacAddress := 0.U
        context.sourceAddress := 0.U
        context.destinationAddress := 0.U
        context.sourcePort := 0.U
        context.destinationPort := 0.U
        context.dataLength := 0.U
        context
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
        val port = Flipped(new UdpServicePort(streamWidth))
    })

    val maxFrameLength = 2048
    val minFrameLength = 64
    val ethernetHeaderLength = 6 + 6 + 2
    val arpFrameLength = 28
    val ipv4HeaderLength = 20
    val icmpHeaderLength = 8
    val udpHeaderLength = UdpHeader.length
    val pseudoIpv4HeaderLength = udpHeaderLength + 12
    val maxProtocolHeaderLength = Seq(arpFrameLength, ipv4HeaderLength + icmpHeaderLength, ipv4HeaderLength + udpHeaderLength).max(Ordering.Int)

    val ipv4HeaderChecksumOffset = 10   // IPv4 Header Checksum field offset to partially update.

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
    val udpHeader = UdpHeader(Cat(protocolHeaderBuffer.iterator.drop(ipv4HeaderLength).toIndexedSeq.reverse))
    val pseudoIpv4Header = PseudoIpv4Header.fromHeaders(ipv4Header, udpHeader)
    val pseudoIpv4HeaderBytes = pseudoIpv4Header.toBytes()
    val udpContext = UdpContext(ethernetHeader, ipv4Header, udpHeader)
    
    val sendIpv4Header = WireDefault((new Ipv4Header).Lit( _.version -> 0x45.U, _.length -> 0.U, _.identification -> 0x1234.U, _.flags_and_offset -> 0x4000.U, _.time_to_live -> 255.U, _.protocol -> 0x11.U, _.source -> ipAddress.U, _.destination -> 0.U, _.type_ -> 0.U ))
    val sendIpv4HeaderChecksum = sendIpv4Header.toBytes().zipWithIndex.map { case (byte, i) => if( i % 2 == 0 ) { Cat(byte, 0.U(8.W)) } else { Cat(0.U(8.W), byte) } }.foldLeft(0.U(16.W))(onesComplementAdd)

    val bytesReceived = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val headerBytesToWrite = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val payloadBytesToWrite = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val bytesWritten = RegInit(0.U(log2Ceil(maxFrameLength).W))
    val paddingRemaining = RegInit(0.U(log2Ceil(minFrameLength).W))
    
    object PayloadSource extends ChiselEnum {
        val Buffer,             // From internal payload buffer.
            UdpStream = Value   // From external UDP payload stream.
    }
    val payloadSource = RegInit(PayloadSource.Buffer)   // Source of packet payload.

    val checksum = RegInit(0.U(16.W))
    val bytePhase = RegInit(false.B)

    val inReady = WireDefault(false.B)
    io.in.ready := inReady

    val outData = RegInit(0.U(8.W))
    val outValid = RegInit(false.B)
    val outLast = RegInit(false.B)
    io.out.valid := outValid
    io.out.bits.data := outData
    io.out.bits.keep := Fill(streamWidth, 1.U(1.W))
    io.out.bits.last := outLast
    
    val udpReceiveData = RegInit(0.U(8.W))
    val udpReceiveDataValid = RegInit(false.B)
    val udpReceiveDataLast = RegInit(false.B)
    io.port.udpReceiveData.valid := udpReceiveDataValid
    io.port.udpReceiveData.bits.data := udpReceiveData
    io.port.udpReceiveData.bits.keep := Fill(streamWidth, 1.U(1.W))
    io.port.udpReceiveData.bits.last := udpReceiveDataLast
    val udpReceivedDataConsumed = RegInit(false.B)
    val udpReceiveContextValid = RegInit(false.B)
    io.port.udpReceiveContext.valid := udpReceiveContextValid
    io.port.udpReceiveContext.bits := udpContext

    val udpSendContextReady = WireDefault(false.B)
    val udpSendContext = Reg(new UdpContext)
    io.port.udpSendContext.ready := udpSendContextReady
    val udpSendReady = WireDefault(false.B)
    io.port.udpSendData.ready := udpSendReady

    def onesComplementAdd(lhs: UInt, rhs: UInt): UInt = {
        val add = lhs +& rhs    // +& is widening add operator, which automatically widen the width of the result to hold the carry bit.
        add(15, 0) + add(16)
    }

    object State extends ChiselEnum {
        val Idle, CheckHeader, Discard, Finalize, 
            WriteEthernetHeader, WriteProtocolHeader, WritePayloadFromBuffer, WritePayloadFromUDPStream, WritePadding, 
            ARPLoad, ARPProcess, 
            IPv4Load, IPv4Process, 
            ICMPLoad, ICMPProcess,
            UDPLoad, UDPProcessReceive,
            UDPPrepareSend, UDPUpdateChecksum, UDPSend = Value
    }
    
    val state = RegInit(State.Idle)

    when(outValid && io.out.ready) {
        outValid := false.B
    }
    when(udpReceiveDataValid && io.port.udpReceiveData.ready) {
        udpReceiveDataValid := false.B
    }
    when(udpReceiveContextValid && io.port.udpReceiveContext.ready) {
        udpReceiveContextValid := false.B
    }

    switch(state) {
        is(State.Idle) {
            inReady := !io.port.udpSendContext.valid
            udpSendContextReady := true.B // Prioritize transmitter over receiver.

            bytesWritten := 0.U
            headerBytesToWrite := 0.U
            when( io.port.udpSendContext.valid ) {
                // Send request 
                udpSendContext := io.port.udpSendContext.bits
                state := State.UDPPrepareSend
            } .elsewhen( io.in.valid ) {
                // Some data is available.
                bytePhase := true.B
                bytesReceived := bytesReceived + 1.U
                ethernetHeaderBuffer(bytesReceived) := io.in.bits.data

                when(io.in.bits.last) { // last is asserted while receiving header.
                    bytesReceived := 0.U
                    state := State.Idle
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
                state := State.Idle
            }
        }

        is(State.Finalize) {
            inReady := false.B
            bytesReceived := 0.U
            state := State.Idle
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
                         switch(payloadSource) {
                            is(PayloadSource.Buffer) { state := State.WritePayloadFromBuffer }
                            is(PayloadSource.UdpStream) { state := State.WritePayloadFromUDPStream }
                        }
                    } .elsewhen( paddingRemaining > 0.U) {
                        state := State.WritePadding
                    } .otherwise {
                        state := State.Finalize
                    }
                }
            }
        }
        is(State.WritePayloadFromBuffer) {
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
        is(State.WritePayloadFromUDPStream) {
            inReady := false.B
            udpSendReady := !outValid || io.out.ready
            when(io.port.udpSendData.valid && udpSendReady) {
                val isLast = io.port.udpSendData.bits.last
                val payloadBytesWrittenNext = bytesWritten + 1.U
                val requirePadding = payloadBytesWrittenNext < (minFrameLength - ethernetHeaderLength).U
                outValid := true.B
                outLast := isLast && !requirePadding
                outData := io.port.udpSendData.bits.data
                bytesWritten := bytesWritten + 1.U
                when(isLast) {
                    when( requirePadding ) {
                        paddingRemaining :=  (minFrameLength - ethernetHeaderLength).U - payloadBytesWrittenNext
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

            payloadSource := PayloadSource.Buffer
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
                checksum := 0.U
                switch(ipv4Header.protocol) {
                    is(0x01.U) {  // ICMP
                        state := State.ICMPLoad
                    }
                    is(0x11.U) {  // UDP
                        state := State.UDPLoad
                    }
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

            payloadSource := PayloadSource.Buffer   // Use payload in the payload buffer.
            when(icmpHeader.type_ === 0x08.U) { // Check if this is ICMP Echo Request packet or not.
                state := State.WriteEthernetHeader
            } .otherwise {
                state := State.Finalize
            }
        }
        // UDP receive process
        is(State.UDPLoad) {
            inReady := true.B
            when( io.in.valid ) {
                bytesReceived := bytesReceived + 1.U
                when(bytesReceived < (ipv4HeaderLength + udpHeaderLength).U) {
                    protocolHeaderBuffer(bytesReceived) := io.in.bits.data
                } .otherwise {
                    // Store payload to the frame buffer
                    frameBuffer.write(bytesReceived - (ipv4HeaderLength + udpHeaderLength).U, io.in.bits.data)
                }
                
                when( io.in.bits.last ) {
                    // Not enough length
                    state := State.Finalize
                } .elsewhen( bytesReceived === (ipv4HeaderLength + udpHeaderLength - 1).U) {
                    udpReceiveContextValid := true.B
                    udpReceivedDataConsumed := false.B
                    state := State.UDPProcessReceive
                }
            }
        }
        is(State.UDPProcessReceive) {
            inReady := !udpReceiveDataValid || io.port.udpReceiveData.ready
            
            when(!udpReceivedDataConsumed && io.in.valid && inReady) {
                udpReceiveDataValid := true.B
                udpReceiveData := io.in.bits.data
                udpReceiveDataLast := io.in.bits.last
                when(io.in.bits.last) {
                    udpReceivedDataConsumed := true.B
                }
            }
            when(udpReceivedDataConsumed && !udpReceiveContextValid) {
                state := State.Finalize
            }
        }
        // UDP send process
        is(State.UDPPrepareSend) {
            val totalHeaderLength = ipv4HeaderLength + udpHeaderLength
            val newIpv4Header = WireDefault(sendIpv4Header)
            newIpv4Header.length := udpSendContext.dataLength + ipv4HeaderLength.U  // dataLength contains UDP header length.
            newIpv4Header.destination := udpSendContext.destinationAddress
            // Checksum calculation (phase 1) - Add pre-calculated base checksum and destination IP adddress.
            val headerChecksum = onesComplementAdd(onesComplementAdd(sendIpv4HeaderChecksum, udpSendContext.destinationAddress(31, 16)), udpSendContext.destinationAddress(15, 0))
            newIpv4Header.header_checksum := headerChecksum
            
            val newEthernetHeader = Wire(new EthernetHeader)
            newEthernetHeader.destination := udpSendContext.destinationMacAddress
            newEthernetHeader.source := hardwareAddress.U
            newEthernetHeader.protocol := 0x0800.U  // IP

            val newUdpHeader = Wire(new UdpHeader)
            newUdpHeader.checksum := 0.U
            newUdpHeader.destinationPort := udpSendContext.destinationPort
            newUdpHeader.sourcePort := udpSendContext.sourcePort
            newUdpHeader.dataLength := udpSendContext.dataLength

            protocolHeaderBuffer := newIpv4Header.toBytes() ++ newUdpHeader.toBytes() ++ Seq.fill(maxProtocolHeaderLength - totalHeaderLength)(0.U(8.W))
            ethernetHeaderBuffer := newEthernetHeader.toBytes()
            headerBytesToWrite := totalHeaderLength.U
            payloadBytesToWrite := udpSendContext.dataLength
            state := State.UDPUpdateChecksum
        }
        is(State.UDPUpdateChecksum) {
            val newChecksum = ~onesComplementAdd(ipv4Header.header_checksum, ipv4Header.length)
            protocolHeaderBuffer(ipv4HeaderChecksumOffset + 0) := newChecksum(15, 8)
            protocolHeaderBuffer(ipv4HeaderChecksumOffset + 1) := newChecksum(7, 0)
            payloadSource := PayloadSource.UdpStream
            state := State.WriteEthernetHeader
        }
    }   
}

class UdpLoopback(config: EthernetServiceConfig = EthernetServiceConfig.default(), streamWidth: Int = 1) extends Module {
    val io = IO(new Bundle {
        val port = new UdpServicePort(streamWidth)
    })

    object State extends ChiselEnum {
        val Idle, Sending = Value
    }

    val state = RegInit(State.Idle)
    val udpContext = Reg(new UdpContext)
    
    val udpReceiveContextReady = WireDefault(false.B)
    io.port.udpReceiveContext.ready := udpReceiveContextReady

    val udpSendContextValid = RegInit(false.B)
    io.port.udpSendContext.valid := udpSendContextValid
    io.port.udpSendContext.bits := udpContext

    val queue = Module(new PacketQueue(Flushable((streamWidth*8).W), 2048))
    queue.io.write.valid <> io.port.udpReceiveData.valid
    queue.io.write.ready <> io.port.udpReceiveData.ready
    queue.io.write.bits.data <> io.port.udpReceiveData.bits.data
    queue.io.write.bits.last <> io.port.udpReceiveData.bits.last
    queue.io.read.valid <> io.port.udpSendData.valid
    queue.io.read.ready <> io.port.udpSendData.ready
    queue.io.read.bits.data <> io.port.udpSendData.bits.data
    queue.io.read.bits.last <> io.port.udpSendData.bits.last
    io.port.udpSendData.bits.keep := 1.U
    
    when(udpSendContextValid && io.port.udpSendContext.ready) {
        udpSendContextValid := false.B
    }

    udpReceiveContextReady := !udpSendContextValid
    when( io.port.udpReceiveContext.valid && udpReceiveContextReady ) {
        // Store UDP context with swapping source <-> destination
        udpContext.dataLength := io.port.udpReceiveContext.bits.dataLength
        udpContext.sourceAddress := io.port.udpReceiveContext.bits.destinationAddress
        udpContext.sourcePort := io.port.udpReceiveContext.bits.destinationPort
        udpContext.sourceMacAddress := io.port.udpReceiveContext.bits.destinationMacAddress
        udpContext.destinationAddress := io.port.udpReceiveContext.bits.sourceAddress
        udpContext.destinationPort := io.port.udpReceiveContext.bits.sourcePort
        udpContext.destinationMacAddress := io.port.udpReceiveContext.bits.sourceMacAddress
        udpSendContextValid := true.B
        state := State.Sending
    }
}

class UdpGpio(config: EthernetServiceConfig = EthernetServiceConfig.default(), streamWidth: Int = 1, numInputBits: Int = 8, numOutputBits: Int = 8) extends Module {
    val io = IO(new Bundle {
        val port = new UdpServicePort(streamWidth)
        val gpioIn = Input(UInt(numInputBits.W))
        val gpioOut = Output(UInt(numOutputBits.W))
    })

    object State extends ChiselEnum {
        val Idle, Receiving, Sending = Value
    }

    val state = RegInit(State.Idle)
    val udpContext = Reg(new UdpContext)
    
    val udpReceiveContextReady = WireDefault(false.B)
    io.port.udpReceiveContext.ready := udpReceiveContextReady
    val udpReceiveDataReady = WireDefault(false.B)
    io.port.udpReceiveData.ready := udpReceiveDataReady

    val udpSendContextValid = RegInit(false.B)
    io.port.udpSendContext.valid := udpSendContextValid
    io.port.udpSendContext.bits := udpContext
    val udpSendDataValid = RegInit(false.B)
    val udpSendData = RegInit(0.U(8.W))
    val udpSendDataLast = RegInit(false.B)
    io.port.udpSendData.valid := udpSendDataValid
    io.port.udpSendData.bits.data := udpSendData
    io.port.udpSendData.bits.keep := 1.U
    io.port.udpSendData.bits.last := udpSendDataLast

    when(udpSendContextValid && io.port.udpSendContext.ready) {
        udpSendContextValid := false.B
    }
    when(udpSendDataValid && io.port.udpSendData.ready) {
        udpSendDataValid := false.B
    }

    val numInputBytes = (numInputBits + 7) / 8
    val numOutputBytes = (numOutputBits + 7) / 8
    val gpioIn = RegInit(VecInit(Seq.fill(numInputBytes)(0.U(8.W))))
    val gpioOut = RegInit(VecInit(Seq.fill(numOutputBytes)(0.U(8.W))))
    val bytesInput = RegInit(0.U(log2Ceil(numInputBytes + 1).W))
    val bytesOutput = RegInit(0.U(log2Ceil(numOutputBytes + 1).W))

    io.gpioOut := Cat(gpioOut.reverse)

    switch(state) {
        is(State.Idle) {
            udpReceiveContextReady := !udpSendContextValid
            when( !udpSendContextValid && io.port.udpReceiveContext.valid ) {
                // Store UDP context with swapping source <-> destination
                udpContext.dataLength := (8 + numInputBytes).U
                udpContext.sourceAddress := io.port.udpReceiveContext.bits.destinationAddress
                udpContext.sourcePort := io.port.udpReceiveContext.bits.destinationPort
                udpContext.sourceMacAddress := io.port.udpReceiveContext.bits.destinationMacAddress
                udpContext.destinationAddress := io.port.udpReceiveContext.bits.sourceAddress
                udpContext.destinationPort := io.port.udpReceiveContext.bits.sourcePort
                udpContext.destinationMacAddress := io.port.udpReceiveContext.bits.sourceMacAddress
                udpSendContextValid := true.B
                bytesInput := 0.U
                bytesOutput := 0.U
                gpioIn := ((0 to numInputBytes - 1).map(i => io.gpioIn(((i+1)*8).min(numInputBits) - 1, i*8)))
                state := State.Receiving
            }
        }
        is(State.Receiving) {
            udpReceiveDataReady := true.B
            when( io.port.udpReceiveData.valid ) {
                when(bytesOutput < numOutputBytes.U) {
                    gpioOut(bytesOutput) := io.port.udpReceiveData.bits.data
                    bytesOutput := bytesOutput + 1.U
                }
                when(io.port.udpReceiveData.bits.last) {
                    state := State.Sending
                }
            }
        }
        is(State.Sending) {
            when( !udpSendDataValid || io.port.udpSendData.ready ) {
                udpSendData := gpioIn(bytesInput)
                bytesInput := bytesInput + 1.U
                udpSendDataValid := true.B
                udpSendDataLast := false.B
                when( bytesInput === (numInputBytes - 1).U) {
                    udpSendDataLast := true.B
                    state := State.Idle
                }
            }
        }
    }
}


class UdpMemoryWriter(config: EthernetServiceConfig = EthernetServiceConfig.default(), streamWidth: Int = 1, numMemoryBytes: Int = 1024, backPressureDataSize: Option[Int] = None, enableDebug: Boolean = false) extends Module {
    val io = IO(new Bundle {
        val port = new UdpServicePort(streamWidth)
        val address = Output(UInt(log2Ceil(numMemoryBytes).W))
        val data = Output(UInt((streamWidth*8).W))
        val writeEnable = Output(Bool())
        val backPressure = backPressureDataSize match {
            case Some(backPressureDataSize) => Some(Flipped(Irrevocable(UInt(backPressureDataSize.W))))
            case None => None
        }
        val sendPortValid = if(enableDebug) Some(Output(Bool())) else None
        val sendContextValid = if(enableDebug) Some(Output(Bool())) else None
    })

    object State extends ChiselEnum {
        val Idle, OffsetUpper, OffsetLower, Receiving = Value
    }

    val state = RegInit(State.Idle)
    
    val udpReceiveContextReady = WireDefault(false.B)
    io.port.udpReceiveContext.ready := udpReceiveContextReady
    val udpReceiveDataReady = WireDefault(false.B)
    io.port.udpReceiveData.ready := udpReceiveDataReady

    io.port.udpSendContext.valid := false.B
    io.port.udpSendContext.bits := UdpContext.default()
    io.port.udpSendData.valid := false.B
    io.port.udpSendData.bits.data := 0.U
    io.port.udpSendData.bits.keep := 0.U
    io.port.udpSendData.bits.last := false.B

    val address = RegInit(0.U(log2Ceil(numMemoryBytes).W))
    val writeEnable = WireDefault(false.B)

    io.address := address
    io.data := io.port.udpReceiveData.bits.data
    io.writeEnable := writeEnable

    switch(state) {
        is(State.Idle) {
            udpReceiveContextReady := true.B
            when( io.port.udpReceiveContext.valid ) {
                state := State.OffsetUpper
            }
        }
        is(State.OffsetUpper) {
            udpReceiveDataReady := true.B
            when( io.port.udpReceiveData.valid ) {
                address := Cat(address(7, 0), io.port.udpReceiveData.bits.data)
                state := State.OffsetLower
                when(io.port.udpReceiveData.bits.last) {
                    state := State.Idle
                }
            }
        }
        is(State.OffsetLower) {
            udpReceiveDataReady := true.B
            when( io.port.udpReceiveData.valid ) {
                address := Cat(address(7, 0), io.port.udpReceiveData.bits.data)
                state := State.Receiving
                when(io.port.udpReceiveData.bits.last) {
                    state := State.Idle
                }
            }
        }
        is(State.Receiving) {
            udpReceiveDataReady := true.B
            when( io.port.udpReceiveData.valid ) {
                when(address < numMemoryBytes.U) {
                    writeEnable := true.B
                    address := address + 1.U
                }
                when(io.port.udpReceiveData.bits.last) {
                    state := State.Idle
                }
            }
        }
    }
    
    backPressureDataSize match {
        case Some(backPressureDataSize) => {
            object BackPressureState extends ChiselEnum {
                val Idle, SendBackPressurePayload = Value
            }

            val state = RegInit(BackPressureState.Idle)

            val backPressurePort = io.backPressure.get
            val backPressure = RegInit(0.U(backPressureDataSize.W))
            val backPressureDataSizeBytes = (backPressureDataSize + 7) / 8  // Number of bytes required to store back pressure data.
            val backPressurePayloadSize = backPressureDataSizeBytes         // Number of bytes of back pressure payload.
            val sendPortValid = RegInit(false.B)

            // Store send context.
            val sendContext = RegInit(UdpContext.default())
            val sendContextValid = RegInit(false.B)
            when( io.port.udpReceiveContext.fire && state === BackPressureState.Idle ) {
                sendContext.dataLength := (8 + backPressurePayloadSize).U
                sendContext.sourceAddress := io.port.udpReceiveContext.bits.destinationAddress
                sendContext.sourcePort := io.port.udpReceiveContext.bits.destinationPort
                sendContext.sourceMacAddress := io.port.udpReceiveContext.bits.destinationMacAddress
                sendContext.destinationAddress := io.port.udpReceiveContext.bits.sourceAddress
                sendContext.destinationPort := io.port.udpReceiveContext.bits.sourcePort
                sendContext.destinationMacAddress := io.port.udpReceiveContext.bits.sourceMacAddress
                sendContextValid := true.B
            }

            when(io.port.udpSendContext.fire) {
                sendPortValid := false.B
            }

            // Payload bytes
            // 0 - backPressureDataSizeBytes                                 : back pressure byte
            val payloadIndex = RegInit(0.U(log2Ceil(backPressurePayloadSize + 1).W))
            val backPressureValue = Cat(0.U((8 - backPressureDataSize%8).W),  backPressure)
            
            io.port.udpSendData.valid := state === BackPressureState.SendBackPressurePayload
            io.port.udpSendData.bits.keep := 1.U
            val backPressureData = WireDefault(0.U(8.W))
            io.port.udpSendData.bits.data := backPressureData
            for(i <- 0 to backPressureDataSizeBytes - 1) {
                when(payloadIndex === i.U) {
                    backPressureData := backPressureValue(8 * (backPressureDataSizeBytes - i) - 1, 8 * (backPressureDataSizeBytes - i - 1))
                }
            }

            // Assert last when the last byte is sent.
            io.port.udpSendData.bits.last := payloadIndex === (backPressurePayloadSize - 1).U

            backPressurePort.ready := state === BackPressureState.Idle && sendContextValid && !sendPortValid
            switch(state) {
                is(BackPressureState.Idle) {
                    // If back pressure is asserted and send context is available, send back pressure payload.
                    when( backPressurePort.fire ) {
                        backPressure := backPressurePort.bits
                        state := BackPressureState.SendBackPressurePayload
                        payloadIndex := 0.U
                        sendPortValid := true.B // Send context
                    }
                }
                is(BackPressureState.SendBackPressurePayload) {
                    when( io.port.udpSendData.fire ) {
                        payloadIndex := payloadIndex + 1.U
                        when( payloadIndex === (backPressurePayloadSize - 1).U ) {
                            state := BackPressureState.Idle
                        }
                    }
                }
            }

            io.port.udpSendContext.valid := sendPortValid
            io.port.udpSendContext.bits := sendContext

            if( enableDebug ) {
                io.sendPortValid.get := sendPortValid
                io.sendContextValid.get := sendContextValid
            }
        }
        case None => {
            // No backpressure.
            io.port.udpSendContext.valid := false.B
            io.port.udpSendContext.bits := UdpContext.default()
            io.port.udpSendData.valid := false.B
            io.port.udpSendData.bits.data := 0.U
            io.port.udpSendData.bits.keep := 0.U
            io.port.udpSendData.bits.last := false.B

            if( enableDebug ) {
                io.sendPortValid.get := false.B
                io.sendContextValid.get := false.B
            }
        }
    }
}

class UdpStreamWriter(config: EthernetServiceConfig = EthernetServiceConfig.default(), streamWidth: Int = 1, backPressureMaxBufferSize: Option[Int] = None) extends Module {
    val io = IO(new Bundle {
        val port = new UdpServicePort(streamWidth)
        val dataReceived = Irrevocable(MultiByteSymbol(streamWidth))
        val backPressure = backPressureMaxBufferSize match {
            case Some(maxBufferSize) => Some(Flipped(Irrevocable(UInt(log2Ceil(maxBufferSize + 1).W))))
            case None => None
        }
    })

    object State extends ChiselEnum {
        val Idle, SendBackPressurePayload = Value
    }

    val state = RegInit(State.Idle)
    
    val udpReceiveContextReady = RegInit(false.B)
    udpReceiveContextReady := true.B
    io.port.udpReceiveContext.ready := udpReceiveContextReady
    
    io.dataReceived <> io.port.udpReceiveData

    backPressureMaxBufferSize match {
        case Some(maxBufferSize) => {
            val backPressurePort = io.backPressure.get
            val backPressure = RegInit(0.U(log2Ceil(maxBufferSize + 1).W))
            val backPressureDataSizeBits = log2Ceil(maxBufferSize + 1)
            val backPressureDataSizeBytes = (backPressureDataSizeBits + 7) / 8  // Number of bytes required to store back pressure data.
            val backPressurePayloadSize = 1 + backPressureDataSizeBytes * 2     // Number of bytes of back pressure payload. length(1byte) + current buffer usage(n bytes) + max buffer size(n bytes)
            val sendPortValid = RegInit(false.B)

            // Store send context.
            val sendContext = RegInit(UdpContext.default())
            val sendContextValid = RegInit(false.B)
            when( io.port.udpReceiveContext.fire && state === State.Idle ) {
                sendContext.dataLength := (8 + backPressurePayloadSize).U
                sendContext.sourceAddress := io.port.udpReceiveContext.bits.destinationAddress
                sendContext.sourcePort := io.port.udpReceiveContext.bits.destinationPort
                sendContext.sourceMacAddress := io.port.udpReceiveContext.bits.destinationMacAddress
                sendContext.destinationAddress := io.port.udpReceiveContext.bits.sourceAddress
                sendContext.destinationPort := io.port.udpReceiveContext.bits.sourcePort
                sendContext.destinationMacAddress := io.port.udpReceiveContext.bits.sourceMacAddress
                sendContextValid := true.B
            }

            when(io.port.udpSendContext.fire) {
                sendPortValid := false.B
            }

            // Payload bytes
            // 0                                                             : payload size
            // 1 - backPressureDataSizeBytes                                 : current buffer usage from io.backPressure
            // backPressureDataSizeBytes + 1 - backPressureDataSizeBytes * 2 : max buffer size
            val payloadIndex = RegInit(0.U(log2Ceil(backPressurePayloadSize + 1).W))
            val backPressureValue = Cat(0.U((8 - backPressureDataSizeBits%8).W),  backPressure)
            val backPressureMaxValue = maxBufferSize.U((backPressureDataSizeBytes * 8).W)
            
            io.port.udpSendData.valid := state === State.SendBackPressurePayload
            io.port.udpSendData.bits.keep := 1.U
            val sendData = WireDefault(0.U(8.W))
            io.port.udpSendData.bits.data := sendData
            when( payloadIndex === 0.U ) {
                sendData := backPressurePayloadSize.U
            }
            for(i <- 0 to backPressureDataSizeBytes - 1) {
                when( payloadIndex === (i + 1).U ) {
                    sendData := backPressureValue(8 * (backPressureDataSizeBytes - i) - 1, 8 * (backPressureDataSizeBytes - i - 1))
                }
                when( payloadIndex === (i + 1 + backPressureDataSizeBytes).U ) {
                    sendData := backPressureMaxValue(8 * (backPressureDataSizeBytes - i) - 1, 8 * (backPressureDataSizeBytes - i - 1))
                }
            }
            // Assert last when the last byte is sent.
            io.port.udpSendData.bits.last := payloadIndex === (backPressurePayloadSize - 1).U

            backPressurePort.ready := state === State.Idle && sendContextValid && !sendPortValid
            switch(state) {
                is(State.Idle) {
                    // If back pressure is asserted and send context is available, send back pressure payload.
                    when( backPressurePort.fire ) {
                        backPressure := backPressurePort.bits
                        state := State.SendBackPressurePayload
                        payloadIndex := 0.U
                        sendPortValid := true.B // Send context
                    }
                }
                is(State.SendBackPressurePayload) {
                    when( io.port.udpSendData.fire ) {
                        payloadIndex := payloadIndex + 1.U
                        when( payloadIndex === (backPressurePayloadSize - 1).U ) {
                            state := State.Idle
                        }
                    }
                }
            }

            io.port.udpSendContext.valid := sendPortValid
            io.port.udpSendContext.bits := sendContext
        }
        case None => {
            // No backpressure.
            io.port.udpSendContext.valid := false.B
            io.port.udpSendContext.bits := UdpContext.default()
            io.port.udpSendData.valid := false.B
            io.port.udpSendData.bits.data := 0.U
            io.port.udpSendData.bits.keep := 0.U
            io.port.udpSendData.bits.last := false.B
        }
    }
}
