// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._

class AsyncFIFO[T <: Data](gen: T, depthBits: Int) extends Module {
    val io = IO(new Bundle{
        val readClock = Input(Clock())
        val readReset = Input(Reset())
        val read = Decoupled(gen)

        val writeClock = Input(Clock())
        val writeReset = Input(Reset())
        val write = Flipped(Decoupled(gen))
        val writeHalfFull = Output(Bool())
    })

    val indexBits = depthBits + 1
    val halfDepthCount = BigInt(1) << (depthBits - 1) 
    val rIndexGray = Wire(UInt(indexBits.W))
    val wIndexGray = Wire(UInt(indexBits.W))
    val mem = Mem(BigInt(1) << depthBits, gen)

    withClockAndReset(io.readClock, io.readReset) {
        val index = RegInit(0.U(indexBits.W))
        val bin2gray = Module(new Bin2Gray(indexBits))
        bin2gray.io.in := index
        val indexGray = Wire(UInt(indexBits.W))
        indexGray := bin2gray.io.out
        val gray2bin = Module(new Gray2Bin(indexBits))

        val wIndexGrayReg = RegInit(0.U(indexBits.W))
        val wIndexGraySync = RegInit(0.U(indexBits.W))
        wIndexGrayReg := wIndexGray
        wIndexGraySync := wIndexGrayReg

        val wIndex = Wire(UInt(indexBits.W))
        gray2bin.io.in := wIndexGraySync
        wIndex := gray2bin.io.out

        val empty = Wire(Bool())
        empty := wIndexGraySync === indexGray

        val readData = Reg(gen)
        val readValid = RegInit(false.B)

        io.read.valid := readValid
        io.read.bits := readData

        val memData = Reg(gen)
        val memDataValid = RegInit(false.B)

        when(readValid && io.read.ready) {
            readValid := false.B
        }
        when( memDataValid && (!readValid  || (readValid && io.read.ready)) )  {
            readData := memData
            readValid := true.B
            memDataValid := false.B
        } 
        when( !empty && (!memDataValid || !readValid  || (readValid && io.read.ready))) {
            memDataValid := true.B
            memData := mem(index(depthBits -1, 0))
            index := index + 1.U
        }
        rIndexGray := indexGray
    }

    withClockAndReset(io.writeClock, io.writeReset) {
        val index = RegInit(0.U(indexBits.W))
        val bin2gray = Module(new Bin2Gray(indexBits))
        bin2gray.io.in := index
        val indexGray = Wire(UInt(indexBits.W))
        indexGray := bin2gray.io.out
        val gray2bin = Module(new Gray2Bin(indexBits))

        val rIndexGrayReg = RegInit(0.U(indexBits.W))
        val rIndexGraySync = RegInit(0.U(indexBits.W))
        rIndexGrayReg := rIndexGray
        rIndexGraySync := rIndexGrayReg

        val rIndex = Wire(UInt(indexBits.W))
        gray2bin.io.in := rIndexGraySync
        rIndex := gray2bin.io.out

        val full = Wire(Bool())
        full := rIndex(indexBits-2, 0) === index(indexBits-2, 0) && rIndex(indexBits-1) =/= index(indexBits-1)
        io.write.ready := !full
        io.writeHalfFull := (index(depthBits-1, 0) - rIndex(depthBits-1, 0)) >= halfDepthCount.U || full
        when( io.write.valid && io.write.ready ) {
            mem.write(index(depthBits - 1, 0), io.write.bits)
            index := index + 1.U
        }

        wIndexGray := indexGray
    }

    
}
