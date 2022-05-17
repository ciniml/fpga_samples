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
import chisel3.experimental.ChiselEnum

class LineWriterTestSystem() extends Module {
  val videoParams = new VideoParams(24, 2, 20, 4, 3, 24, 5, 2, 1)
  val memoryAddressBits = log2Ceil(videoParams.frameBytes * 2)
  val maxBurstWords = 4
  val axiParams = new AXI4Params(memoryAddressBits, 32, AXI4WriteOnly, Some(maxBurstWords))
  val dut = Module(
    new LineWriter(
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
  
  dut.io.axi.aw.get <> memory.io.axi4.aw.get
  dut.io.axi.w.get <> memory.io.axi4.w.get
  dut.io.axi.b.get <> memory.io.axi4.b.get
  
  val ramAddress = RegInit(0.U(axiParams.addressBits.W))
  ram.io.reader.address := ramAddress
  ram.io.reader.request := true.B
  val ramData = ram.io.reader.data
  ram.io.writer <> memory.io.writer.get

  val commandType = LineWriterCommand(videoParams, axiParams)
  val commandSequence = VecInit(Seq(
    // Fill Tests
    commandType.Lit(_.startAddress -> 0x00.U, _.count -> 1.U, _.doFill -> true.B, _.color -> "x452301".U),
    commandType.Lit(_.startAddress -> 0x03.U, _.count -> 1.U, _.doFill -> true.B, _.color -> "xab8967".U),
    commandType.Lit(_.startAddress -> 0x0c.U, _.count -> 2.U, _.doFill -> true.B, _.color -> "xdeadbe".U),
    commandType.Lit(_.startAddress -> 0x12.U, _.count -> 5.U, _.doFill -> true.B, _.color -> "xcafeef".U),  // 2 bursts transfer
    commandType.Lit(_.startAddress -> 0x23.U, _.count -> 8.U, _.doFill -> true.B, _.color -> "xa5b6c7".U),  // 3 bursts transfer
    // Stream Tests
    commandType.Lit(_.startAddress -> 0x3b.U, _.count -> 3.U, _.doFill -> false.B, _.color -> "xa5a5a5".U), // 3 pixels from data stream
  ))
  val dataType = new VideoSignal(videoParams.pixelBits)
  val dataSequence = VecInit(Seq(
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x121314".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x151617".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x18191a".U),
    dataType.Lit(_.startOfFrame -> false.B, _.endOfLine -> false.B, _.pixelData -> "x000000".U),  // Sentinel
  ))
  val memResult = VecInit(Seq(
    "x67452301".U,  // 00
    "x0000AB89".U,  // 04
    "x00000000".U,  // 08
    "xbedeadbe".U,  // 0c
    "xfeefdead".U,  // 10
    "xcafeefca".U,  // 14
    "xefcafeef".U,  // 18
    "xfeefcafe".U,  // 1c
    "xc70000ca".U,  // 20
    "xb6c7a5b6".U,  // 24
    "xa5b6c7a5".U,  // 28
    "xc7a5b6c7".U,  // 2c
    "xb6c7a5b6".U,  // 30
    "xa5b6c7a5".U,  // 34
    "x14a5b6c7".U,  // 38
    "x16171213".U,  // 3c
    "x18191a15".U,  // 40
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
    printf(p"DATA index: ${dataIndex} value: ${Hexadecimal(dataSequence(dataIndex).pixelData)}")
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
      printf(p"CHECK index:${resultIndex} expected:${Hexadecimal(memResult(resultIndex))} actual ${Hexadecimal(ramData)}")
      when( ramData =/= memResult(resultIndex) ) {
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

class LineWriterTest
    extends FlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "LineWriter"
  behavior of dutName

  it should "simple" in {
    test(new LineWriterTestSystem) { c =>
      val width = c.videoParams.pixelsH
      val height = c.videoParams.pixelsV
      c.clock.setTimeout(width * height * 3 )
      
      while( !c.io.finished.peek().litToBoolean ) {
        c.io.fail.expect(false.B, "Result check failed")
        c.clock.step()
      }
    }
  }
}
