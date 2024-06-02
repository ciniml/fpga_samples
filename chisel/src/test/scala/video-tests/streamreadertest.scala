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
import video._
import java.io.FileInputStream
import scala.collection.mutable
import _root_.util.AsyncFIFO
import axi._
import chisel3.experimental.BundleLiterals._


class StreamReaderTestSystem() extends Module {
  val videoParams = new VideoParams(24, 2, 8, 4, 3, 24, 8, 2, 1)
  val memoryAddressBits = log2Ceil(videoParams.frameBytes * 2)
  val maxBurstWords = 4
  val axiParams = new AXI4Params(memoryAddressBits, 32, AXI4ReadOnly, Some(maxBurstWords))
  val dut = Module(
    new StreamReader(
      videoParams,
      axiParams,
      maxBurstWords,
    )
  )
  val io = IO(new Bundle {
    val finished = Output(Bool())
    val fail = Output(Bool())
  })

   val memInput = Seq(
    "xef123456".U,  // 000 : line0
    "x0000abcd".U,  // 004
    "x00000000".U,  // 008
    "x00000000".U,  // 00c
    "x00000000".U,  // 010
    "x00000000".U,  // 014

    "xba654321".U,  // 018 : line1
    "x1112fedc".U,  // 01c
    "x13141510".U,  // 020
    "x00161718".U,  // 024
    "x00000000".U,  // 028
    "x00000000".U,  // 02c

    "x00000000".U,  // 030 : line2
    "x21220000".U,  // 034
    "x23242520".U,  // 038
    "x14262728".U,  // 03c
    "x16171213".U,  // 040
    "x00000015".U,  // 044

    "x00000000".U,  // 048 : line3
    "x00000000".U,  // 04c
    "x00000000".U,  // 050
    "x1a000000".U,  // 054
    "x1c1d1819".U,  // 058
    "x0000001b".U,  // 05c
  )

  val memory = Module(new AXI4Memory(memoryAddressBits, axiParams.dataBits, AXI4ReadOnly, axiParams.maxBurstLength.get))
  val rom = Module(new RomReader(memoryAddressBits, axiParams.dataBits, memInput, 0))
  
  dut.io.axi.ar.get <> memory.io.axi4.ar.get
  dut.io.axi.r.get <> memory.io.axi4.r.get
  rom.io.reader <> memory.io.reader.get

  val commandType = StreamReaderCommand(videoParams, axiParams)
  val commandSequence = VecInit(Seq(
    // Fill Tests
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 0.U, _.endXInclusive -> 0.U, _.startY -> 0.U, _.endYInclusive -> 0.U), // 1 pixel, aligned
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 1.U, _.endXInclusive -> 1.U, _.startY -> 0.U, _.endYInclusive -> 0.U), // 1 pixel, unaligned(1)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 0.U, _.endXInclusive -> 0.U, _.startY -> 1.U, _.endYInclusive -> 1.U), // 1 pixel, aligned
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 1.U, _.endXInclusive -> 1.U, _.startY -> 1.U, _.endYInclusive -> 1.U), // 1 pixel, unaligned(1)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 2.U, _.endXInclusive -> 4.U, _.startY -> 1.U, _.endYInclusive -> 2.U), // 3x2 pixel, unaligned(2)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 5.U, _.endXInclusive -> 6.U, _.startY -> 2.U, _.endYInclusive -> 3.U), // 2x2 pixel, unaligned(2)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 0.U, _.endXInclusive -> 5.U, _.startY -> 2.U, _.endYInclusive -> 2.U), // 6x1 pixel, aligned
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 1.U, _.endXInclusive -> 6.U, _.startY -> 2.U, _.endYInclusive -> 2.U), // 6x1 pixel, unaligned(1)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 2.U, _.endXInclusive -> 7.U, _.startY -> 2.U, _.endYInclusive -> 2.U), // 6x1 pixel, unaligned(2)
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 3.U, _.endXInclusive -> 7.U, _.startY -> 2.U, _.endYInclusive -> 2.U), // 5x1 pixel, unaligned(3)
    // Reverse direction
    commandType.Lit(_.addressOffset -> 0x0000.U, _.startX -> 2.U, _.endXInclusive -> 4.U, _.startY -> 2.U, _.endYInclusive -> 1.U), // 3x2 pixel, unaligned(2), reverse
  ))
  val resultSequence = VecInit(Seq(
    "x123456".U,  // cmd 0
    "xabcdef".U,  // cmd 1
    "x654321".U,  // cmd 2
    "xfedcba".U,  // cmd 3
    "x101112".U,  // cmd 4 (3x2)
    "x131415".U,
    "x161718".U,
    "x202122".U,
    "x232425".U,
    "x262728".U,  // /
    "x121314".U,  // cmd 5 (2x2)
    "x151617".U,
    "x18191a".U,
    "x1b1c1d".U,  // /
    "x000000".U,  // cmd 6 (6x1)
    "x000000".U,
    "x202122".U,
    "x232425".U,
    "x262728".U,
    "x121314".U,  // /
    "x000000".U,  // cmd 7 (6x1)
    "x202122".U,
    "x232425".U,
    "x262728".U,
    "x121314".U,
    "x151617".U,  // /
    "x202122".U,  // cmd 8 (6x1)
    "x232425".U,
    "x262728".U,
    "x121314".U,
    "x151617".U,
    "x000000".U,  // /
    "x232425".U,  // cmd 9 (5x1)
    "x262728".U,
    "x121314".U,
    "x151617".U,
    "x000000".U,  // /
    "x202122".U,  // cmd 10 (3x2) reversed cmd 4
    "x232425".U,
    "x262728".U,
    "x101112".U,
    "x131415".U,
    "x161718".U,  // /
  ))
 
  val commandIndex = RegInit(0.U(log2Ceil(commandSequence.length+1).W))
  val resultIndex = RegInit(0.U(log2Ceil(resultSequence.length + 1).W))

  object State extends ChiselEnum {
      val sCheck, sFail, sFinish = Value
  }
  val state = RegInit(State.sCheck)
  val command = Reg(commandType)
  val commandValid = RegInit(false.B)
  val commandReady = dut.io.command.ready
  dut.io.command.valid := commandValid
  dut.io.command.bits := command

  when(commandValid && commandReady) {
    commandValid := false.B
  }

  when( !commandValid || commandReady ) {
    when(commandIndex < commandSequence.length.U ) {
      command := commandSequence(commandIndex)
      printf(p"ISSUE COMMAND index:${commandIndex}\n")

      commandValid := true.B
      commandIndex := commandIndex + 1.U
    }
  }

  val dataValid = WireDefault(dut.io.data.valid)
  val dataReady = RegInit(false.B)
  val dataBits = WireDefault(dut.io.data.bits.pixelData)
  dut.io.data.ready := dataReady
  dataReady := random.LFSR(16).xorR

  io.finished := state === State.sFinish
  io.fail := state === State.sFail
  switch(state) {
    is(State.sCheck) {
      when( dataValid && dataReady ) {
        val result = resultSequence(resultIndex)
        printf(p"CHECK index:${resultIndex} expected:${Hexadecimal(result)} actual ${Hexadecimal(dataBits)} ... MATCHED: ${dataBits === result}\n")
        when( dataBits =/= result ) {
          state := State.sFail
        }
        resultIndex := resultIndex + 1.U
        when(resultIndex === (resultSequence.length - 1).U) {
          state := State.sFinish
        }
      }
    }
  }
}

class StreamReaderTest
    extends FlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "StreamReader"
  behavior of dutName

  it should "simple" in {
    test(new StreamReaderTestSystem) { c =>
      val width = c.videoParams.pixelsH
      val height = c.videoParams.pixelsV
      c.clock.setTimeout(width * height * 3 * 12)
      
      while( !c.io.finished.peek().litToBoolean ) {
        c.io.fail.expect(false.B, "Result check failed")
        c.clock.step()
      }
    }
  }
}
