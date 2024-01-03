// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import chisel3._
import chisel3.util._
import video._
import sdram.SDRAMBridgeParams
import axi._
import _root_.util.MathUtil
import chisel3.experimental.ChiselEnum

class LineWriterCommand(val videoParams: VideoParams, val axiParams: AXI4Params) extends Bundle {
    val startAddress = UInt(axiParams.addressBits.W)
    val count = UInt(videoParams.countHBits.W)
    val doFill = Bool()
    val color = UInt(videoParams.pixelBits.W)
}
object LineWriterCommand {
    def apply(videoParams: VideoParams, axiParams: AXI4Params): LineWriterCommand = {
        new LineWriterCommand(videoParams, axiParams)
    }
}

class LineWriter(videoParams: VideoParams, axiParams: AXI4Params, writeBurstPixels: Int = 128) extends Module {
    // Currently only supports 24bpp and 32bit bus
    assert(videoParams.pixelBits == 16 || videoParams.pixelBits == 24)
    assert(axiParams.dataBits == 32)
    assert((writeBurstPixels * videoParams.pixelBytes)%(axiParams.dataBits/8) == 0 )

    val io = IO(new Bundle{
        val data = Flipped(Irrevocable(new VideoSignal(videoParams.pixelBits)))
        val command = Flipped(Irrevocable(LineWriterCommand(videoParams, axiParams)))
        val axi = new AXI4IO(new AXI4Params(axiParams.addressBits, axiParams.dataBits, AXI4WriteOnly, axiParams.maxBurstLength))
        val isBusy = Output(Bool())
    })
    val addressBits = log2Ceil(videoParams.frameBytes) + 1
    val addressMaskBits = axiParams.dataBits/8 - 2
    val addressCounter = RegInit(0.U(addressBits.W))
    val writeBurstWords = (writeBurstPixels * videoParams.pixelBytes)/(axiParams.dataBits/8)
    val frameBytes = videoParams.frameBytes

    object State extends ChiselEnum {
        val sIdle, sDecode, sRunning = Value
    }
    val state = RegInit(State.sIdle)
    
    // Command signal connections
    val commandValid = WireDefault(io.command.valid)
    val commandReady = Wire(Bool())
    io.command.ready := commandReady
    val commandBits = WireDefault(io.command.bits)

    val command = Reg(LineWriterCommand(videoParams, axiParams))
    val startAddressAligned = WireDefault(Cat(command.startAddress(axiParams.addressBits-1, addressMaskBits), Fill(addressMaskBits, 0.U)))
    val nextAddress = RegInit(0.U(axiParams.addressBits.W))
    val bytesToTransfer = WireDefault((command.startAddress(addressMaskBits-1, 0) + command.count * videoParams.pixelBytes.U))
    val isLastPartialWrite = (bytesToTransfer & 3.U) =/= 0.U
    val wordsToTransfer = WireDefault((bytesToTransfer + 3.U) >> 2)
    val addressWordsRemainingBits = log2Ceil(videoParams.pixelBytes*videoParams.pixelsH)
    val addressWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val dataWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val issuedDataWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val pixelsRemaining = RegInit(0.U(videoParams.countHBits.W))

    // Realignment buffer
    val realignInputBytes = videoParams.pixelBits/8
    val realignOutputBytes = axiParams.dataBits/8
    val realignBufferBytes = MathUtil.lcm(realignInputBytes, realignOutputBytes).toInt
    val realignBuffer = Reg(Vec(realignBufferBytes, UInt(8.W)))
    val realignBufferValid = Reg(Vec(realignBufferBytes, Bool()))
    val realignPointerBits = log2Ceil(realignBufferBytes*2)
    val realignIndexBits   = log2Ceil(realignBufferBytes)
    val realignInputPointer = RegInit(0.U(realignPointerBits.W))
    val realignOutputPointer = RegInit(0.U(realignPointerBits.W))
    
    def advanceRealignPointer(pointer: UInt, advance: Int): UInt = {
        Mux(pointer < (realignBufferBytes*2 - advance).U, pointer + advance.U, 0.U)
    }
    val realignNextInputPointer = advanceRealignPointer(realignInputPointer, realignInputBytes)
    val realignNextOutputPointer = advanceRealignPointer(realignOutputPointer, realignOutputBytes)

    def realignPointerSide(pointer: UInt): Bool = {
        pointer >= realignBufferBytes.U
    }
    def realignPointerIndex(pointer: UInt): UInt = {
        Mux(pointer >= realignBufferBytes.U, pointer - realignBufferBytes.U, pointer)
    }
    val realignInputIndex = realignPointerIndex(realignInputPointer)
    val realignOutputIndex = realignPointerIndex(realignOutputPointer)
    val realignInputSide = realignPointerSide(realignInputPointer)
    val realignOutputSide = realignPointerSide(realignOutputPointer)

    val realignBufferFull = WireDefault(realignInputIndex + realignInputBytes.U > realignOutputIndex && realignInputSide =/= realignOutputSide)
    val realignBufferEmpty = WireDefault(realignOutputIndex + realignOutputBytes.U > realignInputIndex && realignInputSide === realignOutputSide)
    val realignBufferHasPartialData = WireDefault(realignOutputIndex < realignInputIndex && realignInputSide === realignOutputSide)

    def addressToPixelPhase(address: UInt): UInt = {
        videoParams.pixelBits match {
            case 16 => address(1)
            case 24 => (axiParams.dataBits/8).U - address(addressMaskBits-1, 0)
        }
    }
    def pixelPhaseToRealignIndex(phase: UInt) = {
        videoParams.pixelBits match {
            case 16 => phase * 2.U
            case 24 => MuxLookup(phase, 0.U, Seq(0.U -> 0.U, 1.U -> 3.U, 2.U -> 6.U, 3.U -> 9.U))
        }
    }

    val awValid = RegInit(false.B)
    val awReady = WireDefault(io.axi.aw.get.ready)
    val awAddr = RegInit(0.U(addressBits.W))
    val awLen = RegInit(0.U(log2Ceil(axiParams.maxBurstLength.get).W))
    io.axi.aw.get.valid := awValid
    io.axi.aw.get.bits.addr := awAddr
    io.axi.aw.get.bits.len.get := awLen

    val wValid = RegInit(false.B)
    val wReady = WireDefault(io.axi.w.get.ready)
    val wData = RegInit(0.U(32.W))
    val wLast = RegInit(false.B)
    val wStrb = RegInit(0.U((axiParams.dataBits/8).W))
    io.axi.w.get.valid := wValid
    io.axi.w.get.bits.data := wData
    io.axi.w.get.bits.last.get := wLast
    io.axi.w.get.bits.strb := wStrb
    io.axi.b.get.ready := true.B

    // Data signal connections
    val dataValid = WireDefault(io.data.valid)
    val dataReady = WireDefault(false.B)
    io.data.ready := dataReady
    val dataBits = WireDefault(io.data.bits.pixelData)

    val pixelData = Mux(command.doFill, command.color, dataBits)

    // Clear valid signals 
    when(awValid && awReady) {
        awValid := false.B
    }
    when(wValid && wReady) {
        wValid := false.B
    }

    commandReady := state === State.sIdle
    io.isBusy := state =/= State.sIdle
    switch(state) {
        is(State.sIdle) {
            when(commandValid && commandReady) {
                printf(p"COMMAND address:${Hexadecimal(commandBits.startAddress)} count:${commandBits.count} doFill:${commandBits.doFill} color:${Hexadecimal(commandBits.color)}\n")
                command := commandBits
                state := State.sDecode
            }
        }
        is(State.sDecode) {
            printf(p"DECODE bytesToTransfer:${bytesToTransfer} wordsToTransfer:${wordsToTransfer} isLastPartialWrite:${isLastPartialWrite}\n")
            pixelsRemaining := command.count
            realignBufferValid := (0 to realignBufferBytes-1).map(i => false.B)
            val initialPointer =  pixelPhaseToRealignIndex(addressToPixelPhase(command.startAddress))
            realignInputPointer := initialPointer
            realignOutputPointer := (if( realignIndexBits > addressMaskBits ) { 
                Cat(initialPointer(realignIndexBits-1, addressMaskBits), Fill(addressMaskBits, 0.U)) // Mask unaligned address bits.
            } else {
                0.U // Just put the output data from the realign buffer to the memory location.
            })
            addressWordsRemaining := wordsToTransfer
            dataWordsRemaining := 0.U
            nextAddress := startAddressAligned
            state := State.sRunning
        }
        is(State.sRunning) {
            // Generate address
            when( (!awValid || awReady) && addressWordsRemaining > 0.U && issuedDataWordsRemaining === 0.U ) {
                awAddr := nextAddress
                awValid := true.B
                val nextLen = WireDefault((writeBurstWords - 1).U)
                val nextDataWordsRemaining = WireDefault(writeBurstWords.U)
                val nextAddressWordsRemaining = WireDefault(addressWordsRemaining - writeBurstWords.U)
                val nextNextAddress = WireDefault(nextAddress + (writeBurstWords * axiParams.dataBits/8).U)
                when( addressWordsRemaining < writeBurstWords.U ) {
                    nextLen := addressWordsRemaining - 1.U
                    nextDataWordsRemaining := addressWordsRemaining
                    nextAddressWordsRemaining := 0.U
                } 
                awLen := nextLen
                issuedDataWordsRemaining := nextDataWordsRemaining
                addressWordsRemaining := nextAddressWordsRemaining
                nextAddress := nextNextAddress

                printf(p"AW address=${Hexadecimal(nextAddress)} len=$nextLen addressWordsRemaining=$nextAddressWordsRemaining dataWordsRemaining=$nextDataWordsRemaining nextAddress=${Hexadecimal(nextNextAddress)}\n")
            }
            // Set next output length if an address is already issued
            when(issuedDataWordsRemaining =/= 0.U && dataWordsRemaining === 0.U) {
                issuedDataWordsRemaining := 0.U
                dataWordsRemaining := issuedDataWordsRemaining
            }
            // Output data from the realignment buffer
            when( (!wValid || wReady) && (!realignBufferEmpty || (addressWordsRemaining === 0.U && issuedDataWordsRemaining === 0.U && dataWordsRemaining === 1.U && isLastPartialWrite && realignBufferHasPartialData)) && dataWordsRemaining > 0.U) {
                printf(p"W realignOutputPointer=${realignOutputPointer}\n")
                wData := Cat((0 to realignOutputBytes - 1).map(i => realignBuffer(realignOutputIndex + i.U)).reverse)
                wValid := true.B
                wStrb := Cat((0 to realignOutputBytes - 1).map(i => realignBufferValid(realignOutputIndex + i.U)).reverse)
                wLast := dataWordsRemaining === 1.U
                dataWordsRemaining := dataWordsRemaining - 1.U
                for( i <- 0 to realignOutputBytes-1 ) {
                    realignBufferValid(realignOutputIndex + i.U) := false.B
                }
                realignOutputPointer := realignNextOutputPointer
            }
            // Input data to the realignment buffer
            when( !realignBufferFull && pixelsRemaining > 0.U && (command.doFill || dataValid) ) {
                printf(p"IN realignInputPointer=${realignInputPointer}\n")
                dataReady := !command.doFill
                for( i <- 0 to realignInputBytes-1 ) {
                    realignBuffer(realignInputIndex + i.U) := pixelData(8*(i+1)-1, 8*i)
                    realignBufferValid(realignInputIndex + i.U) := true.B
                }
                realignInputPointer := realignNextInputPointer
                pixelsRemaining := pixelsRemaining - 1.U
            }

            // Check if the transfer completes
            when( addressWordsRemaining === 0.U && issuedDataWordsRemaining === 0.U && dataWordsRemaining === 0.U && pixelsRemaining === 0.U ) {
                state := State.sIdle
            }
        }
    }
}


class StreamWriterCommand(val videoParams: VideoParams, val axiParams: AXI4Params) extends Bundle {
    val addressOffset = UInt(axiParams.addressBits.W)
    val startX = UInt(videoParams.countHBits.W)
    val endXInclusive = UInt(videoParams.countHBits.W)
    val startY = UInt(videoParams.countVBits.W)
    val endYInclusive = UInt(videoParams.countVBits.W)
    val doFill = Bool()
    val color = UInt(videoParams.pixelBits.W)
}
object StreamWriterCommand {
    def apply(videoParams: VideoParams, axiParams: AXI4Params): StreamWriterCommand = {
        new StreamWriterCommand(videoParams, axiParams)
    }
}

class StreamWriter(videoParams: VideoParams, axiParams: AXI4Params, writeBurstPixels: Int = 128) extends Module {
    // Currently only supports 16/24bpp and 32bit bus
    assert(videoParams.pixelBits == 16 || videoParams.pixelBits == 24)
    assert(axiParams.dataBits == 32)
    assert((writeBurstPixels * videoParams.pixelBytes)%(axiParams.dataBits/8) == 0 )

    val io = IO(new Bundle{
        val data = Flipped(Irrevocable(new VideoSignal(videoParams.pixelBits)))
        val command = Flipped(Irrevocable(StreamWriterCommand(videoParams, axiParams)))
        val axi = new AXI4IO(new AXI4Params(axiParams.addressBits, axiParams.dataBits, AXI4WriteOnly, axiParams.maxBurstLength))
        val isBusy = Output(Bool())
    })

    
    object State extends ChiselEnum {
        val sIdle, sDecode, sRunning = Value
    }
    val state = RegInit(State.sIdle)
    
    // Command signal connections
    val commandValid = WireDefault(io.command.valid)
    val commandReady = Wire(Bool())
    io.command.ready := commandReady
    val commandBits = WireDefault(io.command.bits)

    val command = Reg(StreamWriterCommand(videoParams, axiParams))
    
    // LineWriter
    val lineWriter = Module(new LineWriter(videoParams, axiParams, writeBurstPixels))
    val lineCommand = Reg(LineWriterCommand(videoParams, axiParams))
    val lineCommandValid = RegInit(false.B)
    val lineCommandReady = lineWriter.io.command.ready
    lineWriter.io.axi <> io.axi
    lineWriter.io.data <> io.data
    lineWriter.io.command.bits := lineCommand
    lineWriter.io.command.valid := lineCommandValid

    when(lineWriter.io.command.valid && lineWriter.io.command.ready) {
        lineCommandValid := false.B
    }

    // Line start address
    val lineBytes = videoParams.pixelBytes * videoParams.pixelsH
    val lineStartAddress = RegInit(0.U(axiParams.addressBits.W))
    val linesRemaining = RegInit(0.U(videoParams.countVBits.W))
    val lineWriteBusyPrev = RegInit(false.B)
    val isBackwardTransfer = RegInit(false.B)

    io.isBusy := state =/= State.sIdle
    commandReady := state === State.sIdle
    lineWriteBusyPrev := lineWriter.io.isBusy
    switch(state) {
        is(State.sIdle) {
            when(commandValid && commandReady) {
                printf(p"[STREAM] COMMAND startX: ${commandBits.startX}, endXInclusive: ${commandBits.endXInclusive}, startY: ${commandBits.startY}, endYInclusive: ${commandBits.endYInclusive}, doFill: ${commandBits.doFill}, color: ${Hexadecimal(commandBits.color)}\n")
                command := commandBits
                isBackwardTransfer := commandBits.startY > commandBits.endYInclusive
                state := State.sDecode
            }
        }
        is(State.sDecode) {
            val calculatedLineStartAddress = command.addressOffset + command.startY * (videoParams.pixelsH*videoParams.pixelBytes).U + command.startX * videoParams.pixelBytes.U
            printf(p"[STREAM] DECODE lineStartAddress: ${Hexadecimal(calculatedLineStartAddress)} isBackwardTransfer: ${isBackwardTransfer}\n")
            lineCommand.doFill := command.doFill
            lineCommand.color := command.color
            lineCommand.count := command.endXInclusive - command.startX + 1.U
            lineStartAddress := calculatedLineStartAddress
            linesRemaining := Mux(isBackwardTransfer, command.startY - command.endYInclusive + 1.U, command.endYInclusive - command.startY + 1.U)
            state := State.sRunning
        }
        is(State.sRunning) {
            when(linesRemaining === 0.U) {
                when( !lineCommandValid &&  lineWriteBusyPrev && !lineWriter.io.isBusy ) {
                    state := State.sIdle
                }
            } .otherwise {
                when(!lineCommandValid || lineCommandReady ) {
                    lineCommand.startAddress := lineStartAddress
                    lineCommandValid := true.B
                    linesRemaining := linesRemaining - 1.U
                    lineStartAddress := Mux(isBackwardTransfer, lineStartAddress - lineBytes.U, lineStartAddress + lineBytes.U)
                }
            }
        }
    }
}
