// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import chisel3.experimental.ChiselEnum
import chisel3.stage.ChiselStage
import firrtl.annotations.MemoryLoadFileType
import common.Consts._
import fpga._
import display._

class Config(clockHz: Int) extends Module {
  val io = IO(new Bundle {
    val mem = new DmemPortIo
  })

  io.mem.rdata := MuxLookup(io.mem.raddr(2, 2), "xDEADBEEF".U, Seq(
    0.U -> "x01234567".U,
    1.U -> clockHz.U,
  ))
  io.mem.rvalid := true.B
  io.mem.wready := true.B
}

class MatrixLedPeripheral(clockHz: Int) extends Module {
    val io = IO(new Bundle{
        val mem = new DmemPortIo
        val row = Output(UInt(8.W))
        val column = Output(UInt(8.W))
    })
    val config = new MatrixLedConfig(8, 8, clockHz, clockHz/1000, clockHz/10000)
    val matrixLed = Module(new MatrixLed(config))
    val matrix = RegInit(VecInit((0 to config.rows-1).map(_ => 0.U(config.columns.W))))
    io.row := matrixLed.io.row
    io.column := matrixLed.io.column
    matrixLed.io.matrix := matrix

    io.mem.rdata := MuxLookup(io.mem.raddr(2, 2), "xDEADBEEF".U, Seq(
        0.U -> Cat((0 to 3).map(i => matrix(i)).reverse),
        1.U -> Cat((4 to 7).map(i => matrix(i)).reverse),
    ))
    io.mem.rvalid := true.B
    io.mem.wready := true.B
    when(io.mem.wen) {
        switch(io.mem.waddr(2,2)) {
            is(0.U) {
                (0 to 3).foreach(i => { when( io.mem.wstrb(i) ) { matrix(i) := io.mem.wdata((i+1)*8-1, i*8) } })
            }
            is(1.U) {
                (4 to 7).foreach(i => { when( io.mem.wstrb(i-4) ) { matrix(i) := io.mem.wdata((i-4+1)*8-1, (i-4)*8) } })
            }
        }
    }
}

class RiscVDebugSignals extends Bundle {
  val core = new CoreDebugSignals()

  val raddr  = Output(UInt(WORD_LEN.W))
  val rdata = Output(UInt(WORD_LEN.W))
  val ren   = Output(Bool())
  val rvalid = Output(Bool())

  val waddr  = Output(UInt(WORD_LEN.W))
  val wen   = Output(Bool())
  val wready = Output(Bool())
  val wstrb = Output(UInt(4.W))
  val wdata = Output(UInt(WORD_LEN.W))
}

class RiscV(clockHz: Int) extends Module {
  val imemSizeInBytes = 2048
  val dmemSizeInBytes = 512
  val startAddress = 0x08000000L

  val io = IO(new Bundle {
    val gpio = Output(UInt(8.W))
    val uart_tx = Output(Bool())
    val row = Output(UInt(8.W))
    val column = Output(UInt(8.W))
    val exit = Output(Bool())
    val imem = new MemoryReadPort(imemSizeInBytes/4, UInt(32.W))
    val imemRead = new MemoryReadPort(imemSizeInBytes/4, UInt(32.W))
    val imemWrite = new MemoryWritePort(imemSizeInBytes/4, UInt(32.W))
    val debugSignals = new RiscVDebugSignals()
  })
  val core = Module(new Core(startAddress))
  
  val memory = Module(new Memory(null, imemSizeInBytes, dmemSizeInBytes, false))
  val imem_dbus = Module(new SingleCycleMem(imemSizeInBytes))
  val gpio = Module(new Gpio)
  val uart = Module(new Uart(clockHz))
  val matrix = Module(new MatrixLedPeripheral(clockHz))
  val config = Module(new Config(clockHz))

  val decoder = Module(new DMemDecoder(Seq(
    (BigInt(startAddress), BigInt(imemSizeInBytes)),
    (BigInt(0x20000000L), BigInt(dmemSizeInBytes)),
    (BigInt(0x30000000L), BigInt(64)),  // GPIO
    (BigInt(0x30001000L), BigInt(64)),  // UART
    (BigInt(0x40000000L), BigInt(64)),  // CONFIG
    (BigInt(0x50000000L), BigInt(64)),  // MATRIX
  )))
  decoder.io.targets(0) <> imem_dbus.io.mem
  decoder.io.targets(1) <> memory.io.dmem
  decoder.io.targets(2) <> gpio.io.mem
  decoder.io.targets(3) <> uart.io.mem
  decoder.io.targets(4) <> config.io.mem
  decoder.io.targets(5) <> matrix.io.mem

  core.io.imem <> memory.io.imem
  memory.io.imemReadPort <> io.imem
  // core.io.dmem <> memory.io.dmem
  core.io.dmem <> decoder.io.initiator
  imem_dbus.io.read <> io.imemRead
  imem_dbus.io.write <> io.imemWrite

  // Debug signals
  io.debugSignals.core <> core.io.debug_signal
  io.debugSignals.raddr  := core.io.dmem.raddr  
  io.debugSignals.rdata  := decoder.io.initiator.rdata  
  io.debugSignals.ren    := core.io.dmem.ren    
  io.debugSignals.rvalid := decoder.io.initiator.rvalid 
  io.debugSignals.waddr  := core.io.dmem.waddr  
  io.debugSignals.wdata  := core.io.dmem.wdata
  io.debugSignals.wen    := core.io.dmem.wen    
  io.debugSignals.wready := decoder.io.initiator.wready 
  io.debugSignals.wstrb  := core.io.dmem.wstrb

  io.exit := core.io.exit
  io.gpio <> gpio.io.gpio
  io.uart_tx <> uart.io.tx
  io.row <> matrix.io.row
  io.column <> matrix.io.column
}

// object ElaborateArtyA7 extends App {
//   (new ChiselStage).emitVerilog(new RiscV(80000000), Array(
//     "-o", "riscv.v",
//     "--target-dir", "rtl/riscv_arty_a7",
//   ))
// }

// object ElaborateRunber extends App {
//   (new ChiselStage).emitVerilog(new RiscV(12000000), Array(
//     "-o", "riscv.v",
//     "--target-dir", "rtl/riscv_runber",
//   ))
// }

object ElaborateCpuRiscvChiselBookMatrix_TangNano9K extends App {
  (new ChiselStage).emitVerilog(new RiscV(27000000), Array(
    "-o", "riscv.v",
    "--target-dir", "rtl/cpu_riscv_chisel_book_matrix/tangnano9k",
  ))
}

