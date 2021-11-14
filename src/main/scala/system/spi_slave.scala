// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package command

import chisel3._
import chisel3.util._
import _root_.util._

class SPIIO extends Bundle {
    val miso = Input(Bool())
    val mosi = Output(Bool())
    val cs = Output(Bool())
    val sck = Output(Bool())
}

class SPIData extends Bundle {
    val first = Bool()
    val data = UInt(8.W)
}

class SPISlave(idleSendData: Int = 0xff) extends Module {
    val io = IO(new Bundle(){
        val spi = Flipped(new SPIIO())
        val receive = Irrevocable(new SPIData())
        val send = Flipped(Irrevocable(UInt(8.W)))
    })

    val spiReset = io.spi.cs.asAsyncReset()
    val spiClock = io.spi.sck.asClock()
    val fifo = Module(new Queue(new SPIData(), 32))
    
    io.receive <> WithIrrevocableRegSlice(UnsafeIrrevocable(fifo.io.deq))

    val validSend = WireDefault(io.send.valid)
    val readySendRaw = Wire(Bool())
    val readySendSync = RegInit(0.U(4.W))
    val readySend = RegInit(false.B)
    val spiOut = RegInit(0.U(8.W))
    readySendSync := Cat(readySendRaw, readySendSync(3, 1))
    io.send.ready := readySend
    when( validSend ) {
        readySend := false.B
        spiOut := io.send.bits
    }
    when( readySendSync(1) && !readySendSync(0) ) {
        readySend := true.B
    }

    val validReceiveRaw = Wire(Bool())
    val validReceiveSync = RegInit(0.U(4.W))
    val validReceive = RegInit(false.B)
    validReceiveSync := Cat(validReceiveRaw, validReceiveSync(3,1))
    fifo.io.enq.valid := validReceive

    val csSync = RegInit(0.U(3.W))
    csSync := Cat(io.spi.cs, csSync(2, 1))
    
    val first = RegInit(Bool(), false.B)
    when( !csSync(1) && csSync(0) ) {
        first := true.B
    } .elsewhen ( validReceive ) {
        first := false.B
    }
    val spiIn = Wire(UInt(8.W))
    val data = RegInit(0.U(8.W))

    validReceive := false.B
    when( validReceiveSync(1) && !validReceiveSync(0) ) {
        data := spiIn
        validReceive := true.B
    }
    fifo.io.enq.bits.data := data
    fifo.io.enq.bits.first := first

    withClockAndReset(spiClock, spiReset) {
        val shiftReg = RegInit(idleSendData.U(8.W))
        val counter = RegInit("b1000_0000".U)
        val validReceive = RegInit(false.B)
        val input = Reg(UInt(8.W))
        
        val shiftRegNext = Cat(shiftReg(6,0), io.spi.mosi)
        io.spi.miso := shiftReg(7)
        shiftReg := shiftRegNext

        when( counter(0) ) {
            validReceive := true.B
        } .elsewhen( counter(4) ) {
            validReceive := false.B
        }
        when( counter(0) ) {
            input := shiftRegNext
            counter := "b1000_0000".U
        } .otherwise {
            counter := counter >> 1.U
        }
        validReceiveRaw := validReceive
        spiIn := input
    }

    withClockAndReset((!spiClock.asBool).asClock, spiReset) {
        val shiftReg = RegInit(idleSendData.U(8.W))
        val counter = RegInit("b1000_0000".U)
        val readySend = RegInit(false.B)
        
        val shiftRegNext = Cat(shiftReg(6,0), io.spi.mosi)
        io.spi.miso := shiftReg(7)
        when( counter(7) ) {
            shiftReg := Mux(validSend, spiOut, idleSendData.U(8.W))   // Set next data to the shift register
        } .otherwise {
            shiftReg := shiftRegNext
        }

        when( counter(3) ) {
            readySend := false.B
        } .elsewhen( counter(7) ) {
            readySend := validSend
        }
        when( counter(0) ) {
            counter := "b1000_0000".U
        } .otherwise {
            counter := counter >> 1.U
        }
        readySendRaw := readySend
    }
}
