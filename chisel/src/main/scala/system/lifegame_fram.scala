// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._


import spi._
import firrtl.annotations.MemoryLoadFileType
import _root_.circt.stage.ChiselStage

case class LifeGameFramConfig(val rows: Int = 8, val columns: Int = 8, val clockFreq: Int, val refreshInterval: Int, refreshGuardInterval: Int, updateInterval: Int )


class LifeGameFram(val config: LifeGameFramConfig) extends RawModule {
  val columns = config.columns
  val rows = config.rows
  
  val clock = IO(Input(Clock()))
  val reset = IO(Input(Bool()))
  val data = IO(Output(UInt(columns.W)))
  val initialize = IO(Input(Bool()))
  val row = IO(Output(UInt(rows.W)))
  val spi_sck = IO(Output(Bool()))
  val spi_si = IO(Output(Bool()))
  val spi_so = IO(Input(Bool()))
  val spi_cs_n = IO(Output(Bool()))
  val spi_wp_n = IO(Output(Bool()))
  val spi_hold_n = IO(Output(Bool()))


  withClockAndReset(clock, reset) {
    val clockFreq = config.clockFreq
    val refreshInterval = config.refreshInterval
    val refreshGuardInterval = config.refreshGuardInterval
    val updateInterval = config.updateInterval

    val matrix = Reg(Vec(rows, UInt(columns.W)))
    val board = Reg(Vec(rows, UInt(columns.W)))
    val boardNext = Reg(Vec(rows, UInt(columns.W)))
    val readChecksum = RegInit(0.U(8.W))
    val writeChecksum = RegInit(0.U(8.W))
    val spiBufferLength = 5
    val spiTxBuffer = Reg(Vec(spiBufferLength, UInt(8.W)))
    val spiRxBuffer = Reg(Vec(spiBufferLength, UInt(8.W)))
    val spiTxCounter = RegInit(0.U(log2Ceil(scala.math.max(spiBufferLength, rows + 2) + 1).W))
    val spiRxCounter = RegInit(0.U(log2Ceil(scala.math.max(spiBufferLength, rows + 2) + 1).W))
    val boardAddress = RegInit(0.U(log2Ceil(rows + 1).W))
    val updateRow = RegInit(0.U(log2Ceil(rows).W))
    val updateColumn = RegInit(0.U(log2Ceil(columns).W))
    val updateCounter = RegInit(0.U(log2Ceil(updateInterval).W))
    
    val spim = Module(new SPIMaster(1, 8, true))
    spi_sck := spim.io.spi.sck
    spi_si := spim.io.spi.mosi
    spi_cs_n := spim.io.spi.cs
    spim.io.spi.miso := spi_so
    spi_wp_n := true.B
    spi_hold_n := true.B
    val cs_n = RegInit(true.B)
    spim.io.cs.get := cs_n
    

    val WREN  = "b00000110".U
    val WRDI  = "b00000100".U
    val RDSR  = "b00000101".U
    val WRSR  = "b00000001".U
    val READ  = "b00000011".U
    val WRITE = "b00000010".U
    val FSTRD = "b00001011".U
    val RDID  = "b10011111".U
    val SLEEP = "b10111001".U

    object State extends ChiselEnum {
        val Reset, ReadId, Error, Idle, IssueRead, ReadBoard, InitializeBoard, UpdateBoard, CheckStall, WriteEnable, IssueWrite, WriteBoard = Value
    }
    val state = RegInit(State.Reset)

    // SPI transmit sequence
    spim.io.tx.bits := MuxCase(spiTxBuffer(spiBufferLength-1), Seq(
      ((state === State.ReadBoard) -> 0.U), 
      (state === State.WriteBoard && boardAddress < rows.U) -> boardNext(boardAddress),
      (state === State.WriteBoard && boardAddress === rows.U) -> ~writeChecksum,
    ))
    spim.io.tx.valid := spiTxCounter > 0.U
    when( spiTxCounter > 0.U && spim.io.tx.ready ) {
      spiTxCounter := spiTxCounter - 1.U
      when( state === State.IssueWrite ) {
        writeChecksum := 0.U
      } .elsewhen( state === State.WriteBoard ) {
        when(boardAddress < rows.U) {
          writeChecksum := writeChecksum ^ boardNext(boardAddress)
        }
      }
      when( state === State.WriteBoard ) {
        printf(p"[LIFEGAME] WriteBoard ${Hexadecimal(boardAddress)}, ${Hexadecimal(boardNext(boardAddress))}, spiTxCounterNext=${spiTxCounter - 1.U}\n")
        boardAddress := boardAddress + 1.U
      } .otherwise {
        val spiTxBufferNext = Wire(Vec(spiBufferLength, UInt(8.W)))

        spiTxBufferNext(0) := 0.U
        for(i: Int <- 0 to spiBufferLength - 2) {
          spiTxBufferNext(i + 1) := spiTxBuffer(i)
        }
        spiTxBuffer := spiTxBufferNext
        printf(p"[LIFEGAME] Write Sent=${Hexadecimal(spiTxBuffer(spiBufferLength-1))} BufferNext=${Hexadecimal(spiTxBufferNext.asUInt)}, spiTxCounterNext=${spiTxCounter - 1.U}\n")
      }
    }
    spim.io.rx.ready := spiRxCounter > 0.U
    when( spiRxCounter > 0.U && spim.io.rx.valid ) {
      val rxData = spim.io.rx.bits
      spiRxCounter := spiRxCounter - 1.U
      when( state === State.IssueRead ) {
        readChecksum := 0.U
      } .elsewhen( state === State.ReadBoard ) {
        readChecksum := readChecksum ^ rxData
      }
      when( state === State.ReadBoard ) {
        printf(p"[LIFEGAME] ReadBoard ${Hexadecimal(boardAddress)}, ${Hexadecimal(rxData)}, spiRxCounterNext=${spiRxCounter - 1.U}\n")
        boardAddress := boardAddress + 1.U
        when( boardAddress < rows.U ) {
          board(boardAddress) := rxData
        }
      } .otherwise {
        val spiRxBufferNext = Wire(Vec(spiBufferLength, UInt(8.W)))

        spiRxBufferNext(0) := rxData
        for(i: Int <- 0 to spiBufferLength - 2) {
          spiRxBufferNext(i + 1) := spiRxBuffer(i)
        }
        spiRxBuffer := spiRxBufferNext
        printf(p"[LIFEGAME] Read ${Hexadecimal(spiRxBufferNext.asUInt)}, spiRxCounterNext=${spiRxCounter - 1.U}\n")
      }
    }
    
    //printf(p"[LIFEGAME] state=${state.asUInt}, spiTxCounter=${spiTxCounter}, spiRxCounter=${spiRxCounter}\n")
    switch(state) {
      is(State.Reset) {
        printf(p"[LIFEGAME] Reset\n")
        cs_n := false.B
        spiTxCounter := 5.U
        spiRxCounter := 5.U
        spiTxBuffer(spiBufferLength - 1) := RDID
        spiTxBuffer(spiBufferLength - 2) := 0.U
        spiTxBuffer(spiBufferLength - 3) := 0.U
        spiTxBuffer(spiBufferLength - 4) := 0.U
        spiTxBuffer(spiBufferLength - 5) := 0.U
        state := State.ReadId
      }
      is(State.ReadId) {
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          cs_n := true.B
          val deviceId = Cat((0 to 3).map(i => spiRxBuffer(i)).reverse)
          printf(p"[LIFEGAME] ReadId DeviceID=${Hexadecimal(deviceId)}\n")
          when(deviceId === "x047f4803".U) {
            state := State.Idle
          } .otherwise {
            state := State.Error
          }
        }
      }
      is(State.Error) {
        matrix(0) := "b10000001".U
        matrix(1) := "b01000010".U
        matrix(2) := "b00100100".U
        matrix(3) := "b00011000".U
        matrix(4) := "b00011000".U
        matrix(5) := "b00100100".U
        matrix(6) := "b01000010".U
        matrix(7) := "b10000001".U
        state := State.Error
      }
      is(State.Idle) {
        when( updateCounter > 0.U ) {
          updateCounter := updateCounter - 1.U
        } .otherwise {
          printf(p"[LIFEGAME] Idle->IssueRead\n")
          updateCounter := (updateInterval - 1).U
          // Start Read sequence
          cs_n := false.B
          spiTxCounter := 4.U
          spiRxCounter := 4.U
          spiTxBuffer(spiBufferLength - 1) := READ
          spiTxBuffer(spiBufferLength - 2) := 0.U
          spiTxBuffer(spiBufferLength - 3) := 0.U
          spiTxBuffer(spiBufferLength - 4) := 0.U
          // Initialize update counters
          updateRow := 0.U
          updateColumn := 0.U

          state := State.IssueRead
        }
      }
      is(State.IssueRead) {
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          spiTxCounter := (rows + 1).U
          spiRxCounter := (rows + 1).U
          boardAddress := 0.U
          state := State.ReadBoard
        }
      }
      is(State.ReadBoard) {
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          cs_n := true.B
          printf(p"[LIFEGAME] Checksum=${Hexadecimal(readChecksum)} ")
          when( readChecksum === 0xff.U ) {  // Checksum OK.
            printf("Valid\n")
            updateColumn := 0.U
            updateRow := 0.U
            when( board.reduce((l, r) => l | r) === 0.U ) {
              // No cells exist.
              state := State.InitializeBoard
            } .otherwise {
              // Update cells
              state := State.UpdateBoard
            }
          } .otherwise {  // Checksum Error.
            printf("Invalid\n")
            state := State.InitializeBoard
          }
        }
      }
      is(State.InitializeBoard) {
        boardNext(0) := "b00001001".U
        boardNext(1) := "b00010000".U
        boardNext(2) := "b00010001".U
        boardNext(3) := "b00011110".U
        boardNext(4) := "b00000000".U
        boardNext(5) := "b01000000".U
        boardNext(6) := "b01000000".U
        boardNext(7) := "b01000000".U

        // Start Write sequence
        cs_n := false.B
        spiTxCounter := 1.U
        spiRxCounter := 1.U
        spiTxBuffer(spiBufferLength - 1) := WREN
        state := State.WriteEnable
      }
      is(State.UpdateBoard) {
        // Update cells
        val upperRow = Mux(updateRow > 0.U, board(updateRow - 1.U), 0.U(columns.W))
        val centerRow = board(updateRow)
        val bottomRow = Mux(updateRow < (rows - 1).U, board(updateRow + 1.U), 0.U(columns.W))
        val ul = Mux(updateColumn > 0.U, upperRow(updateColumn - 1.U), false.B)
        val cl = Mux(updateColumn > 0.U, centerRow(updateColumn - 1.U), false.B)
        val bl = Mux(updateColumn > 0.U, bottomRow(updateColumn - 1.U), false.B)
        val uc = upperRow(updateColumn)
        val cc = centerRow(updateColumn)
        val bc = bottomRow(updateColumn)
        val ur = Mux(updateColumn < (columns - 1).U, upperRow(updateColumn + 1.U), false.B)
        val cr = Mux(updateColumn < (columns - 1).U, centerRow(updateColumn + 1.U), false.B)
        val br = Mux(updateColumn < (columns - 1).U, bottomRow(updateColumn + 1.U), false.B)
        val count = Seq(ul, cl, bl, uc, bc, ur, cr, br).map(b => b + 0.U(3.W)).reduce((l, r) => l + r)
        val cell = WireDefault(board(updateRow)(updateColumn))

        when(!cc && count === 3.U) { // Birth
          cell := true.B
        } .elsewhen(cc && (count <= 1.U || 4.U <= count) ) {
          cell := false.B
        }
        boardNext(updateRow) := VecInit((0 to columns - 1).map(i => Mux(updateColumn === i.U, cell, boardNext(updateRow)(i)))).asUInt
        
        when(updateColumn === (columns - 1).U) {
          updateRow := updateRow + 1.U
          updateColumn := 0.U
          when(updateRow === (rows - 1).U) {
            state := State.CheckStall
          }
        } .otherwise {
          updateColumn := updateColumn + 1.U
        }
      }
      is(State.CheckStall) {
        val stall = board.zip(boardNext).map(p => p._1 ^ p._2).reduce((l, r) => l | r) === 0.U
        printf(p"[LIFEGAME] CheckStall ${stall}\n")
        when( stall || initialize ) {
          // Updated board state is the same as the previous state. Re-initialize the board.
          state := State.InitializeBoard
        } .otherwise {
          cs_n := false.B
          spiTxCounter := 1.U
          spiTxBuffer(spiBufferLength - 1) := WREN
          spiRxCounter := 1.U
          state := State.WriteEnable
        }
      }
      is(State.WriteEnable) {
        matrix := boardNext
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          cs_n := true.B
          spiTxCounter := 4.U
          spiTxBuffer(spiBufferLength - 1) := WRITE
          spiTxBuffer(spiBufferLength - 2) := 0.U
          spiTxBuffer(spiBufferLength - 3) := 0.U
          spiTxBuffer(spiBufferLength - 4) := 0.U
          spiRxCounter := 4.U
          state := State.IssueWrite
        }
      }
      is(State.IssueWrite) {
        cs_n := false.B
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          spiTxCounter := (rows + 1).U
          spiRxCounter := (rows + 1).U
          boardAddress := 0.U
          state := State.WriteBoard
        }
      }
      is(State.WriteBoard) {
        when(spiTxCounter === 0.U && spiRxCounter === 0.U) {
          cs_n := true.B
          state := State.Idle
        }
      }
    }

    val refreshCounter = RegInit(0.U(log2Ceil(refreshInterval).W))
    val rowReg = RegInit(1.U(rows.W))
    val rowEnable = WireDefault(true.B)
    row := Mux(rowEnable, rowReg, 0.U(columns.W))

    data := MuxCase(0.U, (0 to columns - 1).map(i => ((rowReg === (1.U << i), matrix(i)))))

    refreshCounter := refreshCounter + 1.U
    when( refreshCounter < (refreshInterval - refreshGuardInterval*2 - 1).U ) {
    } .elsewhen( refreshCounter === (refreshInterval - refreshGuardInterval - 1).U ) {
      rowEnable := false.B
      rowReg := (rowReg << 1) | rowReg(rows - 1)
    } .elsewhen( refreshCounter < (refreshInterval - 1).U ) {
      rowEnable := false.B
    } .elsewhen( refreshCounter === (refreshInterval - 1).U ) {
      refreshCounter := 0.U
    }
  }
}

object ElaborateLifeGameSram extends App {
  ChiselStage.emitSystemVerilogFile(new LifeGameFram(new LifeGameFramConfig(8, 8, 27000000, 27000000/1000, 27000000/100000, 27000000)), Array(
    "-o", "lifegame_fram.v",
    "--target-dir", "rtl/chisel/lifegame_fram",
  ))
}
