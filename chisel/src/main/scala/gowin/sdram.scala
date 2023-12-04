// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package sdram

import chisel3._
import chisel3.util._
import axi._
import chisel3.experimental.ChiselEnum
import chisel3.util.experimental.loadMemoryFromFileInline
import _root_.util.IrrevocableRegSlice
import firrtl.annotations.MemoryLoadFileType

case class SDRAMBridgeParams
(
    addressBits: Int,
    dataBytes: Int,
    maxBurstLength: Int,
) {
    val dataBits = dataBytes * 8
    val burstLengthBits = log2Ceil(maxBurstLength)
}

class SDRCIO(val params: SDRAMBridgeParams) extends Bundle {
    val selfRefresh = Output(Bool())
    val powerDown = Output(Bool())
    val wr_n = Output(Bool())
    val rd_n = Output(Bool())
    val addr = Output(UInt(params.addressBits.W))
    val dataLen = Output(UInt(log2Ceil(params.maxBurstLength + 1).W))
    val dqm = Output(UInt(params.dataBytes.W))
    val dataRead = Input(UInt(params.dataBits.W))
    val dataWrite = Output(UInt(params.dataBits.W))
    val initDone = Input(Bool())
    val busy_n = Input(Bool())
    val rdValid = Input(Bool())
    val wrdAck = Input(Bool())
}

class SimSDRC(params: SDRAMBridgeParams, size: Int, initializationFile: Option[String] = None) extends Module {
    val io = IO(new Bundle {
        val sdrc = Flipped(new SDRCIO(params))
    })
    
    val mem = Mem(size, UInt(params.dataBits.W))
    initializationFile match {
        case Some(path) => {
            loadMemoryFromFileInline(mem, path, MemoryLoadFileType.Binary)
        }
        case _ => 
    }

    object State extends ChiselEnum {
        val sReset, sIdle, sRead, sWrite, sWriteDelay = Value
    }

    val state = RegInit(State.sReset)
    val initCount = RegInit(100.U(8.W))
    val address = RegInit(0.U(params.addressBits.W))
    val burstCount = RegInit(0.U((params.burstLengthBits + 1).W))
    val data = RegInit(0.U(params.dataBits.W))
    val nextDataMask = RegInit(0.U(params.dataBits.W))
    val nextWriteData = RegInit(0.U(params.dataBits.W))
    val delay = RegInit(0.U(8.W))
    val readValid = RegInit(false.B)
    val busyAssertDelay = RegInit(0.U(3.W))

    readValid := false.B
    busyAssertDelay := busyAssertDelay >> 1.U

    switch(state) {
        is( State.sReset ) {
            when( initCount === 0.U ) {
                state := State.sIdle
            } .otherwise {
                initCount := initCount - 1.U
            }
        }
        is( State.sIdle ) {
            when( !io.sdrc.rd_n ) {
                printf(p"[SimSDRC] REQ READ Address: ${Hexadecimal(io.sdrc.addr)}\n")
                address := io.sdrc.addr
                burstCount := io.sdrc.dataLen
                delay := 16.U   // From the actual waveform measured by GAO
                busyAssertDelay := "b111".U
                state := State.sRead
            } .elsewhen ( !io.sdrc.wr_n ) {
                printf(p"[SimSDRC] REQ WRITE Address: ${Hexadecimal(io.sdrc.addr)}, Data: ${Hexadecimal(io.sdrc.dataWrite)}, DQM: ${Hexadecimal(io.sdrc.dqm)}\n")
                address := io.sdrc.addr
                data := mem(io.sdrc.addr)
                nextDataMask := FillInterleaved(8, ~io.sdrc.dqm)
                nextWriteData := io.sdrc.dataWrite
                burstCount := io.sdrc.dataLen
                delay := 3.U
                busyAssertDelay := "b111".U
                state := State.sWrite
            }
        }
        is( State.sRead ) {
            when( delay === 0.U ) {
                val readData = Mux( address < mem.length.U, mem(address), 0.U)
                printf(p"[SimSDRC] READ Address: ${Hexadecimal(address)}, Data: ${Hexadecimal(readData)}\n")
                address := address + 1.U
                data := readData
                readValid := true.B
                when( burstCount === 0.U ) {
                    state := State.sIdle
                } .otherwise {
                    burstCount := burstCount - 1.U
                }
            } .otherwise {
                delay := delay - 1.U
                readValid := false.B
            }
        }
        is( State.sWrite ) {
            address := address + 1.U
            nextWriteData := io.sdrc.dataWrite
            nextDataMask := FillInterleaved(8, ~io.sdrc.dqm)
            when( address + 1.U < mem.length.U ) {
                data := mem(address + 1.U)
            }
            when( address < mem.length.U ) {
                val writeData = (data & ~nextDataMask) | (nextWriteData & nextDataMask)
                printf(p"[SimSDRC] WRITE Address: ${Hexadecimal(address)}, Data: ${Hexadecimal(writeData)}\n")
                mem(address) := writeData
            }
            when( burstCount === 0.U ) {
                state := State.sWriteDelay
            } .otherwise {
                burstCount := burstCount - 1.U
            }
        }
        is( State.sWriteDelay ) {
            when( delay === 0.U ) {
                state := State.sIdle
            } .otherwise {
                delay := delay - 1.U
            }
        }
    }

    io.sdrc.initDone := initCount === 0.U
    io.sdrc.busy_n := state === State.sIdle || busyAssertDelay(0)
    io.sdrc.rdValid := readValid
    io.sdrc.dataRead := data
    io.sdrc.wrdAck := false.B
}

class SDRCBridge(params: SDRAMBridgeParams) extends Module {
    val byteAddressShift = log2Ceil(params.dataBytes)
    val axi4Params = AXI4Params(params.addressBits + byteAddressShift, params.dataBits, AXI4ReadWrite, Some(params.maxBurstLength))
    val io = IO(new Bundle {
        val sdrc = new SDRCIO(params)
        val axi = Flipped(new AXI4IO(axi4Params))
    })

    val fifo_ar = Module(new Queue(new AXI4A(axi4Params), entries = 2))
    val fifo_aw = Module(new Queue(new AXI4A(axi4Params), entries = 2))
    val fifo_b = Module(new Queue(new AXI4B(axi4Params), entries = 2))
    
    val fifo_w = Module(new Queue(new AXI4W(axi4Params), entries = params.maxBurstLength*2))
    val fifo_r = Module(new Queue(new AXI4R(axi4Params), entries = params.maxBurstLength*2))
    
    fifo_ar.io.enq <> io.axi.ar.get
    fifo_aw.io.enq <> io.axi.aw.get
    fifo_w.io.enq <> io.axi.w.get
    fifo_r.io.deq <> io.axi.r.get
    fifo_b.io.deq <> io.axi.b.get

    val fifo_ar_deq = Module(new IrrevocableRegSlice(new AXI4A(axi4Params)))
    val fifo_aw_deq = Module(new IrrevocableRegSlice(new AXI4A(axi4Params)))
    fifo_ar.io.deq <> fifo_ar_deq.io.in
    fifo_aw.io.deq <> fifo_aw_deq.io.in

    object State extends ChiselEnum {
        val sReset, sWaitReset, sIdle, sRead, sBeginWrite, sWrite = Value
    }

    val state = RegInit(State.sReset)

    val arready = Wire(Bool())
    val awready = Wire(Bool())
    val wready = Wire(Bool())
    val rvalid = RegInit(false.B)
    val rsignal = Reg(new AXI4R(axi4Params))
    val bvalid = RegInit(false.B)
    val bsignal = Reg(new AXI4B(axi4Params))

    val sdrcBusyDelay = RegInit(0.U(4.W))   // SDRC busy_n signal delays 3 cycles, so we have to mask internally to avoid issuing command.
    val sdrcBusy = Wire(Bool())
    sdrcBusy := !io.sdrc.busy_n || sdrcBusyDelay(0)
    sdrcBusyDelay := sdrcBusyDelay >> 1.U

    val rd_n = RegInit(true.B)
    val wr_n = RegInit(true.B)
    val data = RegInit(0.U(params.dataBits.W))
    val dqm = RegInit(0.U(params.dataBytes.W))
    val address = RegInit(0.U(params.addressBits.W))
    val dataLen = RegInit(0.U(params.burstLengthBits.W))
    val readBurstCount = RegInit(0.U(params.burstLengthBits.W))
    val writeBurstCount = RegInit(0.U(params.burstLengthBits.W))
    
    // Delay one cycle to improve timing requirements.
    val vacancyCountWidth = log2Ceil(params.maxBurstLength*2+1)
    val readFifoVacancy = RegInit(0.U(vacancyCountWidth.W))
    readFifoVacancy := (params.maxBurstLength*2).U - fifo_r.io.count
    val readFifoVacancyRequired = RegInit((params.maxBurstLength*2).U(vacancyCountWidth.W))
    readFifoVacancyRequired := Mux(fifo_ar_deq.io.out.valid, fifo_ar_deq.io.out.bits.len.get + 1.U, (params.maxBurstLength*2).U)

    when( state === State.sIdle ) {
        // start READ transaction if there are enough space in the R channel FIFO to run the requested burst read. 
        // Note that the AxLEN equals to (transfer count - 1) e.g. AxLEN == 0 means 1 transfer, AxLEN == 2 means 3 transfers, so we can compare vacant count and ARLEN with "greater than" operator to ensure the space.
        arready := !sdrcBusy && readFifoVacancy > readFifoVacancyRequired
        // start WRITE transaction if there are enough data in the W channel FIFO to run the requested burst write, READ transaction is not ready, and B channel FIFO is not full.
        awready := !sdrcBusy && fifo_aw_deq.io.out.valid && fifo_w.io.deq.valid && fifo_w.io.count > fifo_aw_deq.io.out.bits.len.get && !arready && fifo_b.io.enq.ready
        wready := false.B
    } .elsewhen ( state === State.sBeginWrite ) {
        arready := false.B
        awready := false.B
        wready := true.B
    } .elsewhen ( state === State.sWrite ) {
        arready := false.B
        awready := false.B
        wready := true.B
    } .otherwise {
        arready := false.B
        awready := false.B
        wready := false.B
    }

    
    rd_n := true.B
    wr_n := true.B
    bvalid := false.B
    rvalid := false.B

    switch(state) {
        is ( State.sReset ) {
            state := State.sWaitReset
        }
        is ( State.sWaitReset ) {
            when( io.sdrc.initDone ) {
                state := State.sIdle
            }
        }
        is ( State.sIdle ) {
            when( arready ) {
                address := fifo_ar_deq.io.out.bits.addr >> byteAddressShift.U
                dataLen := fifo_ar_deq.io.out.bits.len.get
                readBurstCount := fifo_ar_deq.io.out.bits.len.get
                rd_n := false.B
                sdrcBusyDelay := Fill(sdrcBusyDelay.getWidth, 1.U(1.W))
                state := State.sRead
            } .elsewhen( awready ) {    // The first write request has enough data in the write channel FIFO to begin burst transfer. 
                address := fifo_aw_deq.io.out.bits.addr >> byteAddressShift.U
                dataLen := fifo_aw_deq.io.out.bits.len.get
                writeBurstCount := fifo_aw_deq.io.out.bits.len.get
                state := State.sBeginWrite
            }
        }
        is ( State.sRead ) {
            when( io.sdrc.rdValid ) {
                printf(p"[SDRCBridge] READ Remaining: ${readBurstCount} Data: ${Hexadecimal(io.sdrc.dataRead)}\n")
                rvalid := true.B
                rsignal.data := io.sdrc.dataRead
                rsignal.resp := AXI4Resp.OKAY
                rsignal.last.get := readBurstCount === 0.U
                when( readBurstCount === 0.U ) {
                    state := State.sIdle
                } .otherwise {
                    readBurstCount := readBurstCount - 1.U
                }
            }
        }
        is ( State.sBeginWrite ) {
            wr_n := false.B
            data := fifo_w.io.deq.bits.data
            dqm := ~fifo_w.io.deq.bits.strb
            sdrcBusyDelay := Fill(sdrcBusyDelay.getWidth, 1.U(1.W))

            printf(p"[SDRCBridge] WRITE Data: ${Hexadecimal(fifo_w.io.deq.bits.data)} Strb: ${Hexadecimal(fifo_w.io.deq.bits.strb)} Count: ${writeBurstCount}\n")

            when( writeBurstCount === 0.U ) {
                // Single beat transaction. put the response to B channel.
                // Note that fifo_bready is already checked in `fifo_awready` signal.
                // So we can assume that B channel fifo is not full.
                bvalid := true.B
                bsignal.resp := AXI4Resp.OKAY
                state := State.sIdle
            } .otherwise {
                writeBurstCount := writeBurstCount - 1.U
                state := State.sWrite
            }
        }
        is ( State.sWrite ) {
            printf(p"[SDRCBridge] WRITE Data: ${Hexadecimal(fifo_w.io.deq.bits.data)} Strb: ${Hexadecimal(fifo_w.io.deq.bits.strb)} Count: ${writeBurstCount}\n")
            data := fifo_w.io.deq.bits.data
            dqm := ~fifo_w.io.deq.bits.strb
            when( writeBurstCount === 0.U ) {
                bvalid := true.B
                bsignal.resp := AXI4Resp.OKAY
                state := State.sIdle
            } .otherwise {
                writeBurstCount := writeBurstCount - 1.U
            }
        }
    }

    io.sdrc.rd_n := rd_n
    io.sdrc.wr_n := wr_n
    io.sdrc.addr := address
    io.sdrc.dataLen := dataLen
    io.sdrc.dataWrite := data
    io.sdrc.dqm := dqm
    io.sdrc.selfRefresh := false.B
    io.sdrc.powerDown := false.B

    fifo_ar_deq.io.out.ready := arready
    fifo_aw_deq.io.out.ready := awready
    fifo_w.io.deq.ready := wready
    fifo_r.io.enq.valid := rvalid
    fifo_r.io.enq.bits := rsignal
    fifo_b.io.enq.valid := bvalid
    fifo_b.io.enq.bits := bsignal
}
