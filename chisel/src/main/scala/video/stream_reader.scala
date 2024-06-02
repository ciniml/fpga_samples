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


class LineReaderCommand(val videoParams: VideoParams, val axiParams: AXI4Params) extends Bundle {
    val startAddress = UInt(axiParams.addressBits.W)
    val count = UInt(videoParams.countHBits.W)
    val startOfFrame = Bool()
}
object LineReaderCommand {
    def apply(videoParams: VideoParams, axiParams: AXI4Params): LineReaderCommand = {
        new LineReaderCommand(videoParams, axiParams)
    }
}

class LineReader(videoParams: VideoParams, axiParams: AXI4Params, burstPixels: Int = 128) extends Module {
    // Currently only supports 24bpp and 32bit bus
    assert(videoParams.pixelBits == 24)
    assert(axiParams.dataBits == 32)
    assert((burstPixels * videoParams.pixelBytes)%(axiParams.dataBits/8) == 0 )

    val io = IO(new Bundle{
        val data = Irrevocable(new VideoSignal(videoParams.pixelBits))
        val command = Flipped(Irrevocable(LineReaderCommand(videoParams, axiParams)))
        val axi = new AXI4IO(new AXI4Params(axiParams.addressBits, axiParams.dataBits, AXI4ReadOnly, axiParams.maxBurstLength))
        val isBusy = Output(Bool())
    })
    val addressBits = log2Ceil(videoParams.frameBytes) + 1
    val addressMaskBits = axiParams.dataBits/8 - 2
    val addressCounter = RegInit(0.U(addressBits.W))
    val readBurstWords = (burstPixels * videoParams.pixelBytes)/(axiParams.dataBits/8)
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

    val command = Reg(LineReaderCommand(videoParams, axiParams))
    val startAddressAligned = WireDefault(Cat(command.startAddress(axiParams.addressBits-1, addressMaskBits), Fill(addressMaskBits, 0.U)))
    val nextAddress = RegInit(0.U(axiParams.addressBits.W))
    val bytesToTransfer = WireDefault((command.startAddress(addressMaskBits-1, 0) + command.count * videoParams.pixelBytes.U))
    val wordsToTransfer = WireDefault((bytesToTransfer + 3.U) >> 2)
    val addressWordsRemainingBits = log2Ceil(videoParams.pixelBytes*videoParams.pixelsH)
    val addressWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val dataWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val issuedDataWordsRemaining = RegInit(0.U(addressWordsRemainingBits.W))
    val pixelsRemaining = RegInit(0.U(videoParams.countHBits.W))

    // Realignment buffer
    val realignInputBytes = axiParams.dataBits/8        // Input bytes = memory bus width
    val realignOutputBytes = videoParams.pixelBits/8    // Output bytes = bytes per pixel
    val realignBufferBytes = MathUtil.lcm(realignInputBytes, realignOutputBytes).toInt
    val realignBuffer = Reg(Vec(realignBufferBytes, UInt(8.W)))
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
        (axiParams.dataBits/8).U - address(addressMaskBits-1, 0)
    }
    def pixelPhaseToRealignIndex(phase: UInt) = {
        MuxLookup(phase, 0.U)(Seq(0.U -> 0.U, 1.U -> 3.U, 2.U -> 6.U, 3.U -> 9.U))
    }

    val arValid = RegInit(false.B)
    val arReady = WireDefault(io.axi.ar.get.ready)
    val arAddr = RegInit(0.U(addressBits.W))
    val arLen = RegInit(0.U(log2Ceil(axiParams.maxBurstLength.get).W))
    io.axi.ar.get.valid := arValid
    io.axi.ar.get.bits.addr := arAddr
    io.axi.ar.get.bits.len.get := arLen

    val rValid = WireDefault(io.axi.r.get.valid)
    val rReady = WireDefault(false.B)
    val rData = WireDefault(io.axi.r.get.bits.data)
    val rLast = WireDefault(io.axi.r.get.bits.last.get)
    io.axi.r.get.ready := rReady

    // Data signal connections
    val dataValid = RegInit(false.B)
    io.data.valid := dataValid
    val dataReady = WireDefault(io.data.ready)
    val dataBits = Reg(UInt(videoParams.pixelBits.W))
    io.data.bits.pixelData := dataBits
    val endOfLine = RegInit(false.B)
    io.data.bits.endOfLine := endOfLine
    val startOfFrame = RegInit(false.B)
    io.data.bits.startOfFrame := startOfFrame

    // Clear valid signals 
    when(arValid && arReady) {
        arValid := false.B
    }
    when(dataValid && dataReady) {
        dataValid := false.B
        startOfFrame := false.B
    }

    commandReady := state === State.sIdle
    io.isBusy := state =/= State.sIdle
    switch(state) {
        is(State.sIdle) {
            when(commandValid && commandReady) {
                printf(p"COMMAND address:${Hexadecimal(commandBits.startAddress)} count:${commandBits.count}\n")
                command := commandBits
                state := State.sDecode
            }
        }
        is(State.sDecode) {
            printf(p"DECODE bytesToTransfer:${bytesToTransfer} wordsToTransfer:${wordsToTransfer}\n")
            pixelsRemaining := command.count
            startOfFrame := command.startOfFrame
            val initialPointer = pixelPhaseToRealignIndex(addressToPixelPhase(command.startAddress))
            realignInputPointer := Cat(initialPointer(realignIndexBits-1, addressMaskBits), Fill(addressMaskBits, 0.U)) // Mask unaligned address bits.
            realignOutputPointer := initialPointer
            addressWordsRemaining := wordsToTransfer
            dataWordsRemaining := 0.U
            nextAddress := startAddressAligned
            state := State.sRunning
        }
        is(State.sRunning) {
            // Generate address
            when( (!arValid || arReady) && addressWordsRemaining > 0.U && issuedDataWordsRemaining === 0.U ) {
                arAddr := nextAddress
                arValid := true.B
                val nextLen = WireDefault((readBurstWords - 1).U)
                val nextDataWordsRemaining = WireDefault(readBurstWords.U)
                val nextAddressWordsRemaining = WireDefault(addressWordsRemaining - readBurstWords.U)
                val nextNextAddress = WireDefault(nextAddress + (readBurstWords * axiParams.dataBits/8).U)
                when( addressWordsRemaining < readBurstWords.U ) {
                    nextLen := addressWordsRemaining - 1.U
                    nextDataWordsRemaining := addressWordsRemaining
                    nextAddressWordsRemaining := 0.U
                } 
                arLen := nextLen
                issuedDataWordsRemaining := nextDataWordsRemaining
                addressWordsRemaining := nextAddressWordsRemaining
                nextAddress := nextNextAddress

                printf(p"AR address=${Hexadecimal(nextAddress)} len=$nextLen addressWordsRemaining=$nextAddressWordsRemaining dataWordsRemaining=$nextDataWordsRemaining nextAddress=${Hexadecimal(nextNextAddress)}\n")
            }
            // Set next output length if an address is already issued
            when(issuedDataWordsRemaining =/= 0.U && dataWordsRemaining === 0.U) {
                issuedDataWordsRemaining := 0.U
                dataWordsRemaining := issuedDataWordsRemaining
            }
            // Input data to the realignment buffer from memory bus
            val canInputData = !realignBufferFull && (dataWordsRemaining > 0.U || issuedDataWordsRemaining > 0.U)
            rReady := canInputData
            when( canInputData && rValid ) {
                printf(p"R realignInputPointer=${realignInputPointer} dataWordsRemaining=${dataWordsRemaining} input=${Hexadecimal(rData)}\n")
                for( i <- 0 to realignInputBytes-1 ) {
                    realignBuffer(realignInputIndex + i.U) := rData(8*(i+1)-1, 8*i)
                }
                dataWordsRemaining := dataWordsRemaining - 1.U
                realignInputPointer := realignNextInputPointer
            }
            // Output data from the realignment buffer
            when( !realignBufferEmpty && pixelsRemaining > 0.U && (!dataValid || dataReady) ) {
                val dataToOut = Cat((0 to realignOutputBytes - 1).map(i => realignBuffer(realignOutputIndex + i.U)).reverse)
                printf(p"OUT realignOutputPointer=${realignOutputPointer} pixelsRemaining=${pixelsRemaining} dataToOut=${Hexadecimal(dataToOut)}\n")
                dataValid := true.B
                dataBits := dataToOut
                endOfLine := pixelsRemaining === 1.U
                realignOutputPointer := realignNextOutputPointer
                pixelsRemaining := pixelsRemaining - 1.U
            }

            // Check if the transfer completes
            when( addressWordsRemaining === 0.U && issuedDataWordsRemaining === 0.U && dataWordsRemaining === 0.U && pixelsRemaining === 0.U ) {
                state := State.sIdle
            }
        }
    }
}


class StreamReaderCommand(val videoParams: VideoParams, val axiParams: AXI4Params) extends Bundle {
    val addressOffset = UInt(axiParams.addressBits.W)
    val startX = UInt(videoParams.countHBits.W)
    val endXInclusive = UInt(videoParams.countHBits.W)
    val startY = UInt(videoParams.countVBits.W)
    val endYInclusive = UInt(videoParams.countVBits.W)
}
object StreamReaderCommand {
    def apply(videoParams: VideoParams, axiParams: AXI4Params): StreamReaderCommand = {
        new StreamReaderCommand(videoParams, axiParams)
    }
}

class StreamReader(videoParams: VideoParams, axiParams: AXI4Params, burstPixels: Int = 128) extends Module {
    // Currently only supports 24bpp and 32bit bus
    assert(videoParams.pixelBits == 24)
    assert(axiParams.dataBits == 32)
    assert((burstPixels * videoParams.pixelBytes)%(axiParams.dataBits/8) == 0 )

    val io = IO(new Bundle{
        val data = Irrevocable(new VideoSignal(videoParams.pixelBits))
        val command = Flipped(Irrevocable(StreamReaderCommand(videoParams, axiParams)))
        val axi = new AXI4IO(new AXI4Params(axiParams.addressBits, axiParams.dataBits, AXI4ReadOnly, axiParams.maxBurstLength))
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

    val command = Reg(StreamReaderCommand(videoParams, axiParams))
    
    // LineWriter
    val lineReader = Module(new LineReader(videoParams, axiParams, burstPixels))
    val lineCommand = Reg(LineReaderCommand(videoParams, axiParams))
    val lineCommandValid = RegInit(false.B)
    val lineCommandReady = lineReader.io.command.ready
    lineReader.io.axi <> io.axi
    lineReader.io.data <> io.data
    lineReader.io.command.bits := lineCommand
    lineReader.io.command.valid := lineCommandValid

    when(lineReader.io.command.valid && lineReader.io.command.ready) {
        lineCommandValid := false.B
    }

    // Line start address
    val lineBytes = videoParams.pixelBytes * videoParams.pixelsH
    val lineStartAddress = RegInit(0.U(axiParams.addressBits.W))
    val linesRemaining = RegInit(0.U(videoParams.countVBits.W))
    val lineReadBusyPrev = RegInit(false.B)
    val isBackwardTransfer = RegInit(false.B)

    io.isBusy := state =/= State.sIdle
    commandReady := state === State.sIdle
    lineReadBusyPrev := lineReader.io.isBusy
    switch(state) {
        is(State.sIdle) {
            when(commandValid && commandReady) {
                printf(p"[STREAMREADER] COMMAND startX: ${commandBits.startX}, endXInclusive: ${commandBits.endXInclusive}, startY: ${commandBits.startY}, endYInclusive: ${commandBits.endYInclusive}}\n")
                command := commandBits
                isBackwardTransfer := commandBits.startY > commandBits.endYInclusive
                state := State.sDecode
            }
        }
        is(State.sDecode) {
            val calculatedLineStartAddress = command.addressOffset + command.startY * (videoParams.pixelsH*videoParams.pixelBytes).U + command.startX * videoParams.pixelBytes.U
            printf(p"[STREAMREADER] DECODE lineStartAddress: ${Hexadecimal(calculatedLineStartAddress)} isBackwardTransfer: ${isBackwardTransfer}\n")
            lineCommand.count := command.endXInclusive - command.startX + 1.U
            lineStartAddress := calculatedLineStartAddress
            linesRemaining := Mux(isBackwardTransfer, command.startY - command.endYInclusive + 1.U, command.endYInclusive - command.startY + 1.U)
            state := State.sRunning
        }
        is(State.sRunning) {
            when(linesRemaining === 0.U) {
                when( !lineCommandValid && lineReadBusyPrev && !lineReader.io.isBusy ) {
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
