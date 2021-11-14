// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import chisel3.experimental.ChiselEnum
import chisel3.experimental.BundleLiterals._
import axi._

class FrameBufferReaderConfig(val pixelBits: Int, val maxWidth: Int, val maxHeight: Int) extends Bundle {
    val scaleX = UInt(4.W)
    val scaleY = UInt(4.W)
    val startX = UInt(log2Ceil(maxWidth).W)
    val startY = UInt(log2Ceil(maxHeight).W)
    val pixelsH = UInt(log2Ceil(maxWidth + 1).W)
    val pixelsV = UInt(log2Ceil(maxHeight + 1).W)
}

@chiselName
class FrameBufferReader(pixelBits: Int, maxWidth: Int, maxHeight: Int, memBusWidthBits: Int, maxBurst: Int) extends Module {
    assert((pixelBits % 8) == 0)
    val pixelBytes = pixelBits / 8
    val frameBytes = pixelBytes * maxWidth * maxHeight
    val addressBits = log2Ceil(frameBytes * 2)
    val addressMaskBits = log2Ceil(memBusWidthBits/8)
    val videoParams = new VideoParams(pixelBits, 0, maxHeight, 0, 0, 0, maxWidth, 0, 0)
    val axiParams = new AXI4Params(addressBits, memBusWidthBits, AXI4ReadOnly, Some(maxBurst))
    val maxBurstPixels = maxBurst * 4 / 3
    val frameBufferConfigType = new FrameBufferReaderConfig(pixelBits, maxWidth, maxHeight)
    val io = IO(new Bundle{
        val data = Irrevocable(new VideoSignal(pixelBits))
        val mem = new AXI4IO(axiParams)
        val trigger = Input(Bool())
        val active = Output(Bool())
        val config = Input(frameBufferConfigType)
    })

    val running = RegInit(false.B)
    // Workaround for issue 1787 https://github.com/chipsalliance/chisel3/issues/1787
    // Wrap BundleLiteral with WireInit
    val config = RegInit(WireInit(frameBufferConfigType.Lit(_.scaleX -> 0.U, _.scaleY -> 0.U, _.startX -> 0.U, _.startY -> 0.U, _.pixelsH -> maxWidth.U, _.pixelsV -> maxHeight.U)))

    val reader = Module(new LineReader(videoParams, axiParams, maxBurstPixels))
    val readerCommand = Reg(LineReaderCommand(videoParams, axiParams))
    reader.io.command.bits := readerCommand
    val readerCommandValid = RegInit(false.B)
    reader.io.command.valid := readerCommandValid
    val readerCommandReady = reader.io.command.ready
    val readerIsBusy = reader.io.isBusy
    io.mem <> reader.io.axi

    val pixelDataBits = Reg(chiselTypeOf(io.data.bits))
    val pixelValid = RegInit(false.B)
    val pixelReady = io.data.ready
    io.data.valid := pixelValid
    io.data.bits := pixelDataBits

    val readerValid = reader.io.data.valid
    val readerReady = WireDefault(false.B)
    reader.io.data.ready := readerReady
    val readerBits = reader.io.data.bits
    val pixelMultiplierCounter = RegInit(0.U(4.W))
    when(pixelValid && pixelReady) {
        pixelValid := false.B
    }
    when(readerValid && (!pixelValid || pixelReady)) {
        readerReady := pixelMultiplierCounter === 0.U
        pixelMultiplierCounter := Mux(pixelMultiplierCounter === 0.U, config.scaleX - 1.U, pixelMultiplierCounter - 1.U)
        pixelValid := true.B
        pixelDataBits.startOfFrame := readerBits.startOfFrame && pixelMultiplierCounter === config.scaleX - 1.U
        pixelDataBits.endOfLine := readerBits.endOfLine && pixelMultiplierCounter === 0.U
        pixelDataBits.pixelData := readerBits.pixelData
    }

    val counterV = RegInit(0.U(log2Ceil(maxHeight).W))
    val lineMultiplierCounter = RegInit(0.U(4.W))
    val startAddress = RegInit(0.U(axiParams.addressBits.W))
    val startAddressX = RegInit(0.U(axiParams.addressBits.W))
    val startAddressY = RegInit(0.U(axiParams.addressBits.W))

    object State extends ChiselEnum {
        val sIdle, sDecode, sDecode2, sRunning, sWaitTransfer = Value
    }
    val state = RegInit(State.sIdle)
    io.active := state =/= State.sIdle
    
    val startOfFrame = RegInit(false.B)
    when(readerCommandValid && readerCommandReady) {
        readerCommandValid := false.B
    }

    switch(state) {
        is(State.sIdle) {
            config := io.config
            when(io.trigger) {
                state := State.sDecode
            }
        }
        is(State.sDecode) {
            startOfFrame := true.B
            counterV := config.pixelsV - 1.U
            lineMultiplierCounter := config.scaleY - 1.U
            pixelMultiplierCounter := config.scaleX - 1.U
            readerCommand.count := config.pixelsH
            startAddressY := config.startY * (maxWidth * pixelBytes).U   // Calculate Y start address
            startAddressX := config.startX * pixelBytes.U               // Calculate X offset
            state := State.sDecode2
        }
        is(State.sDecode2) {
            startAddress := startAddressY + startAddressX    // Calculate total start address.
            state := State.sRunning
        }
        is(State.sRunning) {
            when(!readerCommandValid || readerCommandReady ) {
                readerCommandValid := true.B
                readerCommand.startAddress := startAddress
                readerCommand.startOfFrame := startOfFrame
                startOfFrame := false.B
                when(lineMultiplierCounter === 0.U) {
                    lineMultiplierCounter := config.scaleY - 1.U
                    startAddress := startAddress + (maxWidth * pixelBytes).U
                    when( counterV === 0.U ) {
                        state := State.sWaitTransfer
                    } .otherwise {
                        counterV := counterV - 1.U
                    }
                } .otherwise {
                    lineMultiplierCounter := lineMultiplierCounter - 1.U
                }
            }
        }
        is(State.sWaitTransfer) {
            when( !reader.io.isBusy ) {
                state := State.sIdle
            }
        }
    }
}
