// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package segled

import chisel3._
import chisel3.util._

class SegmentLed(numberOfSegments: Int, numberOfDigits: Int, segmentUpdateDivider: Int, cathodeCommon: Boolean) extends Module {
    val io = IO(new Bundle {
        val segmentOut = Output(UInt(numberOfSegments.W))
        val digitSelector = Output(UInt(numberOfDigits.W))
        val digits = Input(Vec(numberOfDigits, UInt(numberOfSegments.W)))
    })

    val SEGMENT_UPDATE_COUNTER_BITS = log2Ceil(segmentUpdateDivider)
    val segmentUpdateCounter = RegInit(0.U(SEGMENT_UPDATE_COUNTER_BITS.W))

    val digitSelector = RegInit(0.U(numberOfDigits.W))
    io.digitSelector := (if( cathodeCommon ) ~digitSelector else digitSelector)
    val digitIndex = OHToUInt(digitSelector, numberOfDigits)

    val segmentOut = RegInit(0.U(numberOfSegments.W))
    segmentOut := io.digits(digitIndex)
    io.segmentOut := segmentOut

    when(segmentUpdateCounter === 0.U) {
        digitSelector := Mux(digitSelector === 0.U, 1.U, Cat(digitSelector(numberOfDigits-2, 0), digitSelector(numberOfDigits-1)))
        //digitIndex := Mux(digitSelector === 0.U || digitIndex === (numberOfDigits - 1).U, 0.U, digitIndex + 1.U)
        segmentUpdateCounter := (segmentUpdateDivider - 1).U
    } .otherwise {
        segmentUpdateCounter := segmentUpdateCounter - 1.U
    }
}

class SevenSegmentLed(numberOfDigits: Int, segmentUpdateDivider: Int, cathodeCommon: Boolean) extends Module {
    val numberOfSegments = 8
    val io = IO(new Bundle {
        val segmentOut = Output(UInt(numberOfSegments.W))
        val digitSelector = Output(UInt(numberOfDigits.W))
        val digits = Input(Vec(numberOfDigits, UInt(5.W)))
    })

    val led = Module(new SegmentLed(numberOfSegments, numberOfDigits, segmentUpdateDivider, cathodeCommon))
    io.segmentOut := led.io.segmentOut
    io.digitSelector := led.io.digitSelector

    val segmentDigits = Wire(Vec(numberOfDigits, UInt(numberOfSegments.W)))
    led.io.digits := segmentDigits

    for(digit <- 0 to numberOfDigits - 1) {
        segmentDigits(digit) := Cat(io.digits(digit)(4), MuxLookup(io.digits(digit)(3, 0), 0.U, Seq(
            0x0.U -> "b0111111".U,
            0x1.U -> "b0000110".U,
            0x2.U -> "b1011011".U,
            0x3.U -> "b1001111".U,
            0x4.U -> "b1100110".U,
            0x5.U -> "b1101101".U,
            0x6.U -> "b1111101".U,
            0x7.U -> "b0000111".U,
            0x8.U -> "b1111111".U,
            0x9.U -> "b1101111".U,
            0xa.U -> "b1110111".U,
            0xb.U -> "b1111100".U,
            0xc.U -> "b0111001".U,
            0xd.U -> "b1011110".U,
            0xe.U -> "b1111001".U,
            0xf.U -> "b1110001".U,
        )))
    }
}
