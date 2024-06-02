// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

// See README.md for license details.

package spi

import chisel3._
import chisel3.util._


import axi._
import _root_.util._

class SPIMaster(val halfClockDivider: Int, val dataBits: Int, val manualCS: Boolean = false) extends Module {
    val DataType = UInt(dataBits.W)
    val io = IO(new Bundle{
        val spi = SPIIO()
        val tx = Flipped(Irrevocable(DataType))
        val rx = Irrevocable(DataType)
        val cs = if( manualCS ) { Some(Input(Bool())) } else { None }
    })

    val shiftReg = RegInit(0.U(dataBits.W))
    val misoReg = RegInit(false.B)
    val rxData = RegInit(0.U(dataBits.W))    
    val rxValid = RegInit(false.B)
    val running = RegInit(false.B)

    val bitCounter = RegInit(0.U(dataBits.W))
    val sck = RegInit(false.B)
    val cs = RegInit(true.B)
    val csDelay = RegInit(false.B)
    val dividerCounter = RegInit(0.U(scala.math.max(log2Ceil(halfClockDivider + 1), 1).W))

    when( rxValid && io.rx.ready ) {
        rxValid := false.B
    }

    val externalCS = if( manualCS ) { io.cs.get } else { false.B }
    io.tx.ready := false.B

    when(!running && io.tx.valid && (!rxValid || io.rx.ready) && !externalCS ) {
        io.tx.ready := true.B
        shiftReg := io.tx.bits
        bitCounter := (1 << (dataBits - 1)).U(dataBits.W)
        running := true.B
        csDelay := cs
        cs := false.B
    } .elsewhen( running && csDelay ) {
        when(dividerCounter < halfClockDivider.U) {
            dividerCounter := dividerCounter + 1.U
        } .otherwise {
            csDelay := false.B
            dividerCounter := 0.U
        }
    } .elsewhen( running && !cs) {
        when(dividerCounter === 0.U) {
            sck := !sck // Toggle SCK
            when( sck ) {   // falling edge = shift
                val nextShiftReg = Cat(shiftReg(dataBits-2, 0), misoReg)
                when(bitCounter(0)) {
                    rxData := nextShiftReg
                    rxValid := true.B
                    running := false.B
                    cs := !io.tx.valid  // Deassert CS if the next data is not ready.
                }
                shiftReg := nextShiftReg
                bitCounter := bitCounter >> 1.U
            } .otherwise {  // rising edge = latch
                misoReg := io.spi.miso
            }
            dividerCounter := dividerCounter + 1.U
        } .elsewhen(dividerCounter === (halfClockDivider - 1).U) {
            dividerCounter := 0.U
        } .otherwise {
            dividerCounter := dividerCounter + 1.U
        }
    }

    io.spi.sck := sck
    io.spi.mosi := shiftReg(dataBits-1)
    io.rx.bits := rxData
    io.rx.valid := rxValid

    if( manualCS ) {
        io.spi.cs := io.cs.get
    } else {
        io.spi.cs := cs
    }
}