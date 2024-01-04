// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import chisel3._
import chisel3.util._
import chisel3.experimental.BundleLiterals._
import chisel3.experimental.ChiselEnum
case class VideoParams
(
    pixelBits: Int,

    backPorchV: Int,
    pixelsV: Int,
    frontPorchV: Int,
    pulseWidthV: Int,

    backPorchH: Int,
    pixelsH: Int,
    frontPorchH: Int,

    pulseWidthH: Int,
) {
    val totalCountsH = backPorchH + pixelsH + frontPorchH + pulseWidthH
    val totalCountsV = backPorchV + pixelsV + frontPorchV + pulseWidthV
    val countHBits = log2Ceil(totalCountsH + 1)
    val countVBits = log2Ceil(totalCountsV + 1)
    val pixelBytes = (pixelBits + 7) / 8
    val framePixels = pixelsH * pixelsV
    val frameBytes = pixelBytes * framePixels
    val addressBits = log2Ceil(frameBytes*2)
    val bankOffset = frameBytes
}

class VideoConfig(val maxVideoParams: VideoParams) extends Bundle {
    val backPorchV = UInt(log2Ceil(maxVideoParams.backPorchV + 1).W)
    val pixelsV = UInt(log2Ceil(maxVideoParams.pixelsV + 1).W)
    val frontPorchV = UInt(log2Ceil(maxVideoParams.frontPorchV + 1).W)
    val pulseWidthV = UInt(log2Ceil(maxVideoParams.pulseWidthV + 1).W)
    val backPorchH = UInt(log2Ceil(maxVideoParams.backPorchH + 1).W)
    val pixelsH = UInt(log2Ceil(maxVideoParams.pixelsH + 1).W)
    val frontPorchH = UInt(log2Ceil(maxVideoParams.frontPorchH + 1).W)
    val pulseWidthH = UInt(log2Ceil(maxVideoParams.pulseWidthH + 1).W)

    def default(defaultVideoParams: VideoParams): VideoConfig = {
        WireInit(
            this.Lit(
                _.backPorchV -> defaultVideoParams.backPorchV.U,
                _.pixelsV -> defaultVideoParams.pixelsV.U,
                _.frontPorchV -> defaultVideoParams.frontPorchV.U,
                _.pulseWidthV -> defaultVideoParams.pulseWidthV.U,
                _.backPorchH -> defaultVideoParams.backPorchH.U,
                _.pixelsH -> defaultVideoParams.pixelsH.U,
                _.frontPorchH -> defaultVideoParams.frontPorchH.U,
                _.pulseWidthH -> defaultVideoParams.pulseWidthH.U,
            )
        )
    }
    def totalCountsH(): UInt = {
        this.pulseWidthH + this.backPorchH + this.pixelsH + this.frontPorchH
    }
    def totalCountsV(): UInt = {
        this.pulseWidthV + this.backPorchV + this.pixelsV + this.frontPorchV
    }
}
object VideoConfig {
    def apply(maxVideoParams: VideoParams): VideoConfig = {
        new VideoConfig(maxVideoParams)
    }
}

class VideoSignal(val pixelBits: Int) extends Bundle {
    val pixelData = Output(UInt(pixelBits.W))
    val startOfFrame = Output(Bool())
    val endOfLine = Output(Bool())
}

class VideoIO(val pixelBits: Int) extends Bundle {
    val pixelData = Output(UInt(pixelBits.W))
    val hSync = Output(Bool())
    val vSync = Output(Bool())
    val dataEnable = Output(Bool())

    def default(): VideoIO = {
        WireInit(
            this.Lit(
                _.dataEnable -> false.B,
                _.hSync -> true.B,
                _.vSync -> true.B,
                _.pixelData -> 0.U,
            )
        )
    }
}

class VideoMemoryIO(val pixelBits: Int, val addressWidth: Int) extends Bundle {
    val pixelData = Input(UInt(pixelBits.W))
    val address = Output(UInt(addressWidth.W))
}

class VideoMultiplicationConfig(val maxMultiplierH: Int = 1, val maxMultiplierV: Int = 1) extends Bundle {
    val multiplierH = UInt(log2Ceil(maxMultiplierH + 1).W)
    val multiplierV = UInt(log2Ceil(maxMultiplierV + 1).W)

    def default(): VideoMultiplicationConfig = {
        WireInit(
            this.Lit(
                _.multiplierH -> 1.U,
                _.multiplierV -> 1.U,
            )
        )
    }
}

class VideoSignalGenerator(defaultVideoParams: VideoParams, maxVideoParams: VideoParams, maxMultiplierH: Int = 1, maxMultiplierV: Int = 1) extends Module {
    val videoConfigType = new VideoConfig(maxVideoParams)
    val videoMultiplierConfigType = new VideoMultiplicationConfig(maxMultiplierH, maxMultiplierV)
    val io = IO(new Bundle {
        val video = new VideoIO(maxVideoParams.pixelBits)
        val data = Flipped(Irrevocable(new VideoSignal(maxVideoParams.pixelBits)))
        val triggerFrame = Output(Bool())
        val dataInSync = Output(Bool())
        val config = Flipped(Valid(videoConfigType))
        val multiplierConfig = Flipped(Valid(videoMultiplierConfigType))
        val vActive = Output(Bool())
    })

    val nextVideoConfig = RegInit(videoConfigType.default(defaultVideoParams))
    val videoConfig = RegInit(videoConfigType.default(defaultVideoParams))
    val nextMultiplierConfig = RegInit(WireInit(videoMultiplierConfigType.Lit(_.multiplierH -> 1.U, _.multiplierV -> 1.U)))
    val multiplierConfig = RegInit(WireInit(videoMultiplierConfigType.Lit(_.multiplierH -> 1.U, _.multiplierV -> 1.U)))
    object State extends ChiselEnum {
        val Sync, Back, Active, Front = Value
    }
    val stateH = RegInit(State.Sync)
    val stateV = RegInit(State.Sync)

    val activeCounterH = RegInit(0.U(log2Ceil(maxVideoParams.pixelsH).W))
    val activeCounterV = RegInit(0.U(log2Ceil(maxVideoParams.pixelsV).W))
    val inactiveMaxH = Seq(maxVideoParams.backPorchH, maxVideoParams.frontPorchH, maxVideoParams.pulseWidthH).max
    val inactiveMaxV = Seq(maxVideoParams.backPorchV, maxVideoParams.frontPorchV, maxVideoParams.pulseWidthV).max
    val inactiveCounterH = RegInit(0.U(log2Ceil(inactiveMaxH + 1).W))
    val inactiveCounterV = RegInit(0.U(log2Ceil(inactiveMaxV + 1).W))
    val multiplierH = RegInit(0.U(Seq(1, log2Ceil(maxMultiplierH)).max.W))
    val multiplierV = RegInit(0.U(Seq(1, log2Ceil(maxMultiplierV)).max.W))

    val multiplierBuffer = Mem(maxVideoParams.pixelsH, UInt(maxVideoParams.pixelBits.W))
    // Buffer the pixel data from the multiplier buffer to increase the timing margin.
    val nextActiveCounterH = Mux(activeCounterH === videoConfig.pixelsH - 1.U, 0.U, activeCounterH + 1.U)
    val pixelFromBuffer = RegNext(multiplierBuffer.read(nextActiveCounterH), 0.U)

    val advanceV = WireDefault(false.B) // advances vertical counter/state machine
    val nextFrame = WireDefault(false.B) // next frame

    val data = RegInit(0.U(maxVideoParams.pixelBits.W)) // Pixel data.
    val dataInSync = RegInit(false.B)
    val dataReady = WireDefault(!dataInSync && !io.data.bits.startOfFrame)

    // Horizontal state machine
    switch(stateH) {
        is(State.Sync) {
            inactiveCounterH := inactiveCounterH + 1.U
            when(inactiveCounterH === videoConfig.pulseWidthH - 1.U) {
                stateH := State.Back        // to back porch
                inactiveCounterH := 0.U
            }
            multiplierH := 0.U  // Reset multiplier counter
        }
        is(State.Back) {
            inactiveCounterH := inactiveCounterH + 1.U
            when(inactiveCounterH === videoConfig.backPorchH - 1.U) {
                stateH := State.Active      // to active
                inactiveCounterH := 0.U
            }
        }
        is(State.Active) {
            activeCounterH := activeCounterH + 1.U
            when(activeCounterH === videoConfig.pixelsH - 1.U) {
                stateH := State.Front       // to front porch
                activeCounterH := 0.U
            }
            // Active area?
            when( stateV === State.Active ) {
                when( multiplierV === 0.U ) {   // not vertical multiplication. load pixel from the data stream.
                    // Update multiplier counter
                    multiplierH := multiplierH + 1.U
                    when( multiplierH === multiplierConfig.multiplierH - 1.U ) {
                        multiplierH := 0.U
                    }
                    when( multiplierH === 0.U ) {   // This is the first pixel of multiplication. (or the multiplication is disabled at all.)
                        val pixelData = Mux(io.data.valid && dataInSync, io.data.bits.pixelData, 0.U)
                        dataReady := true.B         // Consume data from the stream.
                        dataInSync := io.data.valid // Data stream is in sync if the data is available.
                        multiplierBuffer.write(activeCounterH, pixelData)
                        data := pixelData
                    } .otherwise {  // This is not the first pixel of multiplication.
                        // No need to update the output pixel data. Just write it to the multiplier buffer.
                        multiplierBuffer.write(activeCounterH, data)
                    }
                } .otherwise {  // vertical multiplication. load pixel from the multiplier buffer.
                    data := pixelFromBuffer
                }
            }
        }
        is(State.Front) {
            inactiveCounterH := inactiveCounterH + 1.U
            when(inactiveCounterH === videoConfig.frontPorchH - 1.U) {
                stateH := State.Sync        // to sync
                inactiveCounterH := 0.U
                advanceV := true.B          // Advance vertical counter/statemachine
            }
        }
    }

    // Vertical state machine
    switch( stateV ) {
        is( State.Sync ) {
            when( advanceV ) {
                inactiveCounterV := inactiveCounterV + 1.U
                when( inactiveCounterV === videoConfig.pulseWidthV - 1.U ) {
                    stateV := State.Back        // to back porch
                    inactiveCounterV := 0.U
                }
                multiplierV := 0.U // reset multiplier
            }
        }
        is( State.Back ) {
            when( advanceV ) {
                inactiveCounterV := inactiveCounterV + 1.U
                when( inactiveCounterV === videoConfig.backPorchV - 1.U ) {
                    stateV := State.Active      // to active
                    inactiveCounterV := 0.U
                }
            }
        }
        is( State.Active ) {
            when( advanceV ) {
                activeCounterV := activeCounterV + 1.U
                when( activeCounterV === videoConfig.pixelsV - 1.U ) {
                    stateV := State.Front       // to front porch
                    activeCounterV := 0.U
                }

                multiplierV := multiplierV + 1.U
                when( multiplierV === multiplierConfig.multiplierV - 1.U ) {
                    multiplierV := 0.U
                }
            }
        }
        is( State.Front ) {
            when( advanceV ) {
                inactiveCounterV := inactiveCounterV + 1.U
                when( inactiveCounterV === videoConfig.frontPorchV - 1.U ) {
                    stateV := State.Sync        // to sync
                    inactiveCounterV := 0.U
                    nextFrame := true.B
                }
            }
        }
    }


    val dataEnable = stateH === State.Active && stateV === State.Active
    val dataEnableReg = RegNext(dataEnable, false.B)
    val hSync = RegNext(stateH === State.Sync, false.B)
    val vSync = RegNext(stateV === State.Sync, false.B)
    
    // Update video config
    when(io.config.valid) {
        nextVideoConfig := io.config.bits
    }
    when(io.multiplierConfig.valid) {
        nextMultiplierConfig := io.multiplierConfig.bits
    }

    // Fetch current config
    val triggerFrame = RegInit(true.B)
    triggerFrame := false.B
    when( nextFrame ) {
        videoConfig := nextVideoConfig
        multiplierConfig := nextMultiplierConfig
        triggerFrame := true.B
    }
    val vActive = RegNext(stateV === State.Active, false.B)

    // Output signals
    io.triggerFrame := triggerFrame
    io.vActive := vActive
    io.dataInSync := dataInSync
    io.data.ready := dataReady
    io.video.hSync := hSync
    io.video.vSync := vSync
    io.video.dataEnable := dataEnableReg
    io.video.pixelData := Mux(dataEnableReg, data, 0.U)
}