// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package video

import org.scalatest._
import chiseltest._
import chisel3._
import chisel3.util._
import scala.util.control.Breaks
import java.io.FileInputStream
import scala.collection.mutable
import _root_.util.AsyncFIFO
import axi._
import chisel3.experimental.BundleLiterals._


class StreamWriterTestSystem() extends Module {
  val videoParams = new VideoParams(24, 2, 8, 4, 3, 24, 8, 2, 1)
  val memoryAddressBits = log2Ceil(videoParams.frameBytes * 2)
  val maxBurstWords = 4
  val axiParams = new AXI4Params(memoryAddressBits, 32, AXI4WriteOnly, Some(maxBurstWords))
  val dut = Module(
    new StreamWriter(
      videoParams,
      axiParams,
      maxBurstWords,
    )
  )
  val io = IO(new Bundle {
    val finished = Output(Bool())
    val fail = Output(Bool())
  })

  val memory = Module(new AXI4Memory(memoryAddressBits, axiParams.dataBits, AXI4WriteOnly, axiParams.maxBurstLength.get))
  val ram = Module(new RamReaderWriter(memoryAddressBits, axiParams.dataBits, 0, videoParams.frameBytes))
  
  val protocolError = WireDefault(false.B)
  memory.io.axi4 <> AXIRandomizer(AXIProtocolChecker(dut.io.axi, Some(protocolError)))
  
  val ramAddress = RegInit(0.U(axiParams.addressBits.W))
  ram.io.reader.address := ramAddress
  ram.io.reader.request := true.B
  val ramData = ram.io.reader.data
  ram.io.writer <> memory.io.writer.get

  val commandType = StreamWriterCommand(videoParams, axiParams)
  val commandSequence = VecInit(Seq(
    // Fill Tests
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 0.U, _.endXInclusive -> 0.U, _.startY -> 0.U, _.endYInclusive -> 0.U, _.doFill -> true.B, _.color -> "x123456".U), // 1 pixel, aligned
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 1.U, _.endXInclusive -> 1.U, _.startY -> 0.U, _.endYInclusive -> 0.U, _.doFill -> true.B, _.color -> "xabcdef".U), // 1 pixel, unaligned(1)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 0.U, _.endXInclusive -> 0.U, _.startY -> 1.U, _.endYInclusive -> 1.U, _.doFill -> true.B, _.color -> "x654321".U), // 1 pixel, aligned
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 1.U, _.endXInclusive -> 1.U, _.startY -> 1.U, _.endYInclusive -> 1.U, _.doFill -> true.B, _.color -> "xfedcba".U), // 1 pixel, unaligned(1)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 2.U, _.endXInclusive -> 4.U, _.startY -> 1.U, _.endYInclusive -> 2.U, _.doFill -> true.B, _.color -> "x101112".U), // 3x2 pixel, unaligned(2)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 2.U, _.endXInclusive -> 3.U, _.startY -> 2.U, _.endYInclusive -> 1.U, _.doFill -> true.B, _.color -> "x202122".U), // 2x2 pixel, unaligned(2), reverse
    // Stream Tests
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 5.U, _.endXInclusive -> 6.U, _.startY -> 2.U, _.endYInclusive -> 3.U, _.doFill -> false.B, _.color -> "xdeadbe".U), // 2x2 pixel, unaligned(2)
  ))
  val dataType = new VideoSignal(videoParams.pixelBits)
  val dataSequence = VecInit(Seq(
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x121314".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x151617".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x18191a".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x1b1c1d".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x000000".U),  // Sentinel
  ))
  val memResult = VecInit(Seq(
    "xef123456".U,  // 000 : line0
    "x0000abcd".U,  // 004
    "x00000000".U,  // 008
    "x00000000".U,  // 00c
    "x00000000".U,  // 010
    "x00000000".U,  // 014

    "xba654321".U,  // 018 : line1
    "x2122fedc".U,  // 01c
    "x20212220".U,  // 020
    "x00101112".U,  // 024
    "x00000000".U,  // 028
    "x00000000".U,  // 02c

    "x00000000".U,  // 030 : line2
    "x21220000".U,  // 034
    "x20212220".U,  // 038
    "x14101112".U,  // 03c
    "x16171213".U,  // 040
    "x00000015".U,  // 044

    "x00000000".U,  // 048 : line3
    "x00000000".U,  // 04c
    "x00000000".U,  // 050
    "x1a000000".U,  // 054
    "x1c1d1819".U,  // 058
    "x0000001b".U,  // 04c
  ))

  val commandIndex = RegInit(0.U(log2Ceil(commandSequence.length+1).W))
  val resultIndex = RegInit(0.U(log2Ceil(memResult.length + 1).W))

  object State extends ChiselEnum {
      val sIdle, sWait, sCheck, sFail, sFinish = Value
  }
  val state = RegInit(State.sIdle)
  val command = Reg(commandType)
  val commandValid = RegInit(false.B)
  val commandReady = dut.io.command.ready
  dut.io.command.valid := commandValid
  dut.io.command.bits := command

  val dataIndex = RegInit(0.U(log2Ceil(dataSequence.length+1).W))
  val dataWait = RegInit(false.B)
  dut.io.data.valid := dataIndex < (dataSequence.length - 1).U && !dataWait
  dut.io.data.bits := dataSequence(dataIndex)
  dataWait := false.B
  when(dut.io.data.valid && dut.io.data.ready) {
    printf(p"DATA index: ${dataIndex} value: ${Hexadecimal(dataSequence(dataIndex).pixelData)}\n")
    dataIndex := dataIndex + 1.U
    dataWait := true.B
  }

  when(commandValid && commandReady) {
    commandValid := false.B
  }

  io.finished := state === State.sFinish
  io.fail := state === State.sFail
  switch(state) {
    is(State.sIdle) {
      when( commandValid ) {
        when(commandReady) {
          state := State.sWait
        }
      } .otherwise {
        when(commandIndex < commandSequence.length.U ) {
          command := commandSequence(commandIndex)
          commandValid := true.B
          commandIndex := commandIndex + 1.U
        } .otherwise {
          ramAddress := 4.U
          state := State.sCheck
        }
      }
    }
    is(State.sWait) {
      when(!dut.io.isBusy) {
        state := State.sIdle
      }
    }
    is(State.sCheck) {
      printf(p"CHECK index:${resultIndex} expected:${Hexadecimal(memResult(resultIndex))} actual ${Hexadecimal(ramData)}\n")
      when( ramData =/= memResult(resultIndex) || protocolError ) {
        state := State.sFail
      }
      ramAddress := ramAddress + 4.U
      resultIndex := resultIndex + 1.U
      when(resultIndex === (memResult.length - 1).U) {
        state := State.sFinish
      } 
    }
  }
}

class StreamWriterTest
    extends FlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "StreamWriter"
  behavior of dutName

  it should "simple" in {
    test(new StreamWriterTestSystem) { c =>
      val width = c.videoParams.pixelsH
      val height = c.videoParams.pixelsV
      c.clock.setTimeout(width * height * 3 * 12 )
      
      while( !c.io.finished.peek().litToBoolean ) {
        c.io.fail.expect(false.B, "Result check failed")
        c.clock.step()
      }
    }
  }
}
