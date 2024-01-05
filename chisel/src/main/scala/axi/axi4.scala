// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._
import chisel3.experimental.ChiselEnum

sealed trait AXI4Mode
case object AXI4ReadWrite extends AXI4Mode
case object AXI4ReadOnly  extends AXI4Mode
case object AXI4WriteOnly extends AXI4Mode

object AXI4Resp extends ChiselEnum {
    val OKAY, EXOKAY, SLVERR, DECERR = Value
}

case class AXI4Params
(
    addressBits: Int,
    dataBits: Int,
    mode: AXI4Mode,
    maxBurstLength: Option[Int] = None,
) {
    val strbBits = dataBits / 8
    val allowBurst = maxBurstLength.isDefined

    def asAXIMode(mode: AXI4Mode): AXI4Params = {
        AXI4Params(addressBits, dataBits, mode, maxBurstLength)
    }
}

class AXI4A(val params: AXI4Params) extends Bundle {
    val addr = UInt(params.addressBits.W)
    val len = if (params.allowBurst) Some(UInt(8.W)) else None
}
class AXI4R(val params: AXI4Params) extends Bundle {
    val data  = UInt(params.dataBits.W)
    val resp  = AXI4Resp()
    val last = if(params.allowBurst) Some(Bool()) else None
}
class AXI4W(val params: AXI4Params) extends Bundle {
    val data  = UInt(params.dataBits.W)
    val strb = UInt(params.strbBits.W)
    val last = if(params.allowBurst) Some(Bool()) else None
}
class AXI4B(val params: AXI4Params) extends Bundle {
    val resp  = AXI4Resp()
}

class AXI4IO(val params: AXI4Params) extends Bundle {
    val ar = params.mode match {
        case AXI4WriteOnly => None
        case _ => Some(Irrevocable(new AXI4A(params)))
    }
    val r = params.mode match {
        case AXI4WriteOnly => None
        case _ => Some(Flipped(Irrevocable(new AXI4R(params))))
    }
    val aw = params.mode match {
        case AXI4ReadOnly => None
        case _ => Some(Irrevocable(new AXI4A(params)))
    }
    val w = params.mode match {
        case AXI4ReadOnly => None
        case _ => Some(Irrevocable(new AXI4W(params)))
    }
    val b = params.mode match {
        case AXI4ReadOnly => None
        case _ => Some(Flipped(Irrevocable(new AXI4B(params))))
    }
}
object AXI4IO {
    def apply(params : AXI4Params) : AXI4IO = {
        new AXI4IO(params)
    }
}

class MemoryReaderIO(addressBits: Int, dataBits: Int) extends Bundle {
    val address = Output(UInt(addressBits.W))
    val data = Input(UInt(dataBits.W))
    val request = Output(Bool())
    val response = Input(Bool())
}


class MemoryWriterIO(addressBits: Int, dataBits: Int) extends Bundle {
    val strbBits = dataBits/8
    val address = Output(UInt(addressBits.W))
    val data = Output(UInt(dataBits.W))
    val strobe = Output(UInt(strbBits.W))
    val request = Output(Bool())
    val ready = Input(Bool())
}

class RomReader(addressBits: Int, dataBits: Int, values: Seq[UInt], addressOffset: BigInt) extends Module {
    val io = IO(new Bundle{
        val reader = Flipped(new MemoryReaderIO(addressBits, dataBits))
    })

    val rom = VecInit(values)
    val maskedAddressBits = log2Ceil(dataBits/8)
    
    
    val response = RegInit(false.B)
    io.reader.response := response
    val data = RegInit(0.U(dataBits.W))
    io.reader.data := data

    val index = WireInit((io.reader.address - addressOffset.U)(addressBits-1, maskedAddressBits))
    val validIndex = WireInit(addressOffset.U <= io.reader.address && io.reader.address < (addressOffset + rom.length*(dataBits/8)).U)

    response := false.B
    when(io.reader.request) {
        when( validIndex ) {
            data := rom(index)
            response := true.B
        }
    }
}

class RamReaderWriter(addressBits: Int, dataBits: Int, addressOffset: BigInt, size: Int) extends Module {
    val io = IO(new Bundle {
        val reader = Flipped(new MemoryReaderIO(addressBits, dataBits))
        val writer = Flipped(new MemoryWriterIO(addressBits, dataBits))
    })
    val dataBytes = dataBits / 8
    val maskedAddressBits = log2Ceil(dataBytes)
    val numberOfElements = size >> maskedAddressBits
    val mem = Mem(numberOfElements, Vec(dataBytes, UInt(8.W)))

    def checkRange(address: UInt): Bool = {
        addressOffset.U <= address && address < (addressOffset + size).U
    }

    val readIndex = WireDefault(io.reader.address(addressBits - 1, maskedAddressBits))
    val isReadIndexValid = WireDefault(checkRange(io.reader.address))

    val writeIndex = WireDefault(io.writer.address(addressBits - 1, maskedAddressBits))
    val isWriteIndexValid = WireDefault(checkRange(io.writer.address))

    val writeData = WireDefault(VecInit((0 until dataBytes by 1).map(i => io.writer.data((i+1)*8-1, i*8))))
    val writeStrobes = io.writer.strobe.asBools()
    io.writer.ready := !reset.asBool()
    when(io.writer.request && isWriteIndexValid) {
        mem.write(writeIndex, writeData, writeStrobes)
    }

    val readData = RegInit(0.U(dataBits.W))
    val readResponse = RegInit(false.B)
    io.reader.data := readData
    io.reader.response := readResponse
    
    readResponse := false.B
    when(io.reader.request && isReadIndexValid) {
        readData := Cat(mem.read(readIndex).reverse)
        readResponse := true.B
    }
}

class AXI4LiteMemoryReader(addressBits: Int, dataBits: Int) extends Module {
    val axi4liteParams = AXI4Params(addressBits, dataBits, AXI4ReadOnly)
    val io = IO(new Bundle {
        val axi4lite = new AXI4IO(axi4liteParams)
        val reader = Flipped(new MemoryReaderIO(addressBits, dataBits))
    })
    val dataBytes = dataBits / 8
    val maskedAddressBits = log2Ceil(dataBytes)

    val sIdle :: sAddress :: sData :: Nil = Enum(3)
    val state = RegInit(sIdle)

    val address = RegInit(0.U(addressBits.W))
    val data = RegInit(0.U(dataBits.W))
    val response = RegInit(false.B)
    val byteSelector = WireInit(address(maskedAddressBits-1, 0))

    io.axi4lite.ar.get.valid := state === sAddress
    io.axi4lite.ar.get.bits.addr := address(addressBits-1, maskedAddressBits) ## 0.U(maskedAddressBits.W)
    io.axi4lite.r.get.ready := state === sData
    io.reader.response := response
    io.reader.data := data

    response := false.B
    switch(state) {
        is(sIdle) {
            when(io.reader.request) {
                address := io.reader.address
                state := sAddress
            }
        }
        is(sAddress) {
            when(io.axi4lite.ar.get.ready) {
                state := sData
            }
        }
        is(sData) {
            when(io.axi4lite.r.get.valid) {
                for(byteIndex <- 0 until dataBytes) {
                    when(byteSelector === byteIndex.U) {
                        data := io.axi4lite.r.get.bits.data(dataBytes*8-1, byteIndex*8)
                    }
                }
                response := true.B

                when(io.reader.request) {
                    address := io.reader.address
                    state := sAddress
                } otherwise {
                    state := sIdle
                }
            }
        }
    }
}

class AXI4Memory(addressBits: Int, dataBits: Int, mode: AXI4Mode, maxBurstLength: Int) extends Module {
    val axi4Params = AXI4Params(addressBits, dataBits, mode, Some(maxBurstLength))
    val io = IO(new Bundle {
        val axi4 = Flipped(new AXI4IO(axi4Params))
        val reader = mode match {
            case AXI4WriteOnly => None
            case _ => Some(new MemoryReaderIO(addressBits, dataBits))
        }
        val writer = mode match {
            case AXI4ReadOnly => None
            case _ => Some(new MemoryWriterIO(addressBits, dataBits))
        }
    })
    val dataBytes = dataBits / 8
    val maskedAddressBits = log2Ceil(dataBytes)
    val burstLengthBits = log2Ceil(maxBurstLength)

    mode match {
        case AXI4WriteOnly => {}
        case _ => {
            val sIdle :: sData :: Nil = Enum(2)
            val state = RegInit(sIdle)

            val address = RegInit(0.U(addressBits.W))
            val burstLength = RegInit(0.U(burstLengthBits.W))
            val data = RegInit(0.U(dataBits.W))
            val response = RegInit(false.B)
            val dataValid = RegInit(false.B)

            val io_reader = io.reader.get
            
            io.axi4.ar.get.ready := state === sIdle && !dataValid
            io.axi4.r.get.valid := dataValid
            io.axi4.r.get.bits.data := io_reader.data
            io.axi4.r.get.bits.last.get := burstLength === 0.U
            io.axi4.r.get.bits.resp := AXI4Resp.OKAY

            io_reader.address := address
            val readerRequest = WireDefault(false.B)
            io_reader.request := readerRequest
            
            when( dataValid && io.axi4.r.get.ready ) {
                dataValid := false.B
            }
            switch(state) {
                is(sIdle) {
                    when( !dataValid && io.axi4.ar.get.valid ) {
                        address := io.axi4.ar.get.bits.addr
                        burstLength := io.axi4.ar.get.bits.len.get
                        dataValid := false.B
                        state := sData
                    }
                }
                is(sData) {
                    when( !dataValid || io.axi4.r.get.ready ) {
                        dataValid := true.B
                        readerRequest := true.B
                        address := address + dataBytes.U
                        when( burstLength === 0.U ) {
                            state := sIdle
                        } .otherwise {
                            burstLength := burstLength - 1.U
                        }
                    }
                }
            }
        }
    }


    mode match {
        case AXI4ReadOnly => {}
        case _ => {
            val sIdle :: sData :: sResp :: Nil = Enum(3)
            val state = RegInit(sIdle)

            val address = RegInit(0.U(addressBits.W))
            val burstLength = RegInit(0.U(burstLengthBits.W))
            val data = RegInit(0.U(dataBits.W))
            val response = RegInit(false.B)
            
            val io_writer = io.writer.get

            io.axi4.aw.get.ready := state === sIdle && io.axi4.aw.get.valid
            io.axi4.w.get.ready := state === sData && (!io_writer.request || io_writer.ready)
            io_writer.data := io.axi4.w.get.bits.data
            io_writer.strobe := io.axi4.w.get.bits.strb

            io.axi4.b.get.valid := state === sResp
            io.axi4.b.get.bits.resp := AXI4Resp.OKAY

            io_writer.address := address
            io_writer.request := state === sData && io.axi4.w.get.valid

            switch(state) {
                is(sIdle) {
                    when( io.axi4.aw.get.valid && io.axi4.aw.get.valid ) {
                        address := io.axi4.aw.get.bits.addr
                        burstLength := io.axi4.aw.get.bits.len.get
                        state := sData
                    }
                }
                is(sData) {
                    when( io.axi4.w.get.valid && io_writer.ready ) {
                        address := address + dataBytes.U
                        when( burstLength === 0.U ) {
                            state := sResp
                        } .otherwise {
                            burstLength := burstLength - 1.U
                        }
                    }
                }
                is(sResp) {
                    when( io.axi4.b.get.ready ) {
                        state := sIdle
                    }
                }
            }
        }
    }
}


class AXI4MemoryWriter(addressBits: Int, dataBits: Int) extends Module {
    val strobeBits = dataBits/8
    val axi4liteParams = AXI4Params(addressBits, dataBits, AXI4WriteOnly)
    val io = IO(new Bundle {
        val axi4lite = new AXI4IO(axi4liteParams)
        val writer = Flipped(new MemoryWriterIO(addressBits, dataBits))
    })

    val sIdle :: sAddress :: sData :: sResp :: Nil = Enum(4)
    val state = RegInit(sIdle)

    val address = RegInit(0.U(addressBits.W))
    val data = RegInit(0.U(dataBits.W))
    val ready = RegInit(false.B)
    val strobe = RegInit(0.U(strobeBits.W))

    io.axi4lite.aw.get.valid := state === sAddress
    io.axi4lite.aw.get.bits.addr := address
    io.axi4lite.w.get.valid := state === sData
    io.axi4lite.w.get.bits.data := data
    io.axi4lite.w.get.bits.strb := strobe
    io.axi4lite.b.get.ready := state === sResp
    io.writer.ready := state === sIdle && ready
    
    ready := true.B
    switch(state) {
        is(sIdle) {
            when(io.writer.request && ready) {
                address := io.writer.address
                data := io.writer.data
                strobe := io.writer.strobe
                state := sAddress
            }
        }
        is(sAddress) {
            when(io.axi4lite.aw.get.ready) {
                state := sData
            }
        }
        is(sData) {
            when(io.axi4lite.w.get.ready) {
                state := sResp
            }
        }
        is(sResp) {
            when(io.axi4lite.b.get.valid) {
                state := sIdle
            }
        }
    }
}
