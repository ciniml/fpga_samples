// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package segled

import org.scalatest._
import chiseltest._
import chisel3._
import chisel3.util._
import scala.util.control.Breaks
import chisel3.experimental.BundleLiterals._


class ShiftRegister595 extends Module {
  val io = IO(new Bundle {
    val shift = Flipped(ShiftRegisterPort())
    val output = Output(UInt(8.W))
  })

  val shiftClock = io.shift.shiftClock.asClock
  val shiftRegSignal = Wire(UInt(8.W))

  withClock(shiftClock) {
    val shiftReg = RegInit(0.U(8.W))
    shiftRegSignal := shiftReg
    shiftReg := Cat(shiftReg(6, 0), io.shift.data)
  }

  withClock(io.shift.latch.asClock) {
    val outputReg = RegInit(0.U(8.W))
    outputReg := shiftRegSignal
    // Emulate output enable as a output mask. no tristate.
    io.output := Mux(io.shift.outputEnable, 0.U, outputReg)
  }
}

class SegmentLedWithShiftRegsTestSystem extends Module {
  val dut = Module(
    new SegmentLedWithShiftRegs(8, 6, 2, 3, true, true)
  )

  val io = IO(new Bundle {
    val segmentOut = ShiftRegisterPort()
    val digitSelector = ShiftRegisterPort()
    val segmentOutBits = Output(UInt(8.W))
    val digitSelectorBits = Output(UInt(8.W))
  })

  val shiftRegSegment = Module(new ShiftRegister595())
  val shiftRegDigit = Module(new ShiftRegister595())

  shiftRegSegment.io.shift <> dut.io.segmentOut
  shiftRegDigit.io.shift <> dut.io.digitSelector

  io.segmentOutBits := shiftRegSegment.io.output
  io.digitSelectorBits := shiftRegDigit.io.output

  io.segmentOut := dut.io.segmentOut
  io.digitSelector := dut.io.digitSelector
  dut.io.digits := VecInit(Seq(0x01.U, 0x02.U, 0x04.U, 0x48.U, 0x10.U, 0xa0.U))
  //dut.io.digits := VecInit(Seq(0x0f.U, 0x00.U, 0x00.U, 0x00.U, 0x00.U, 0x00.U))
}

class SegmentLedWithShiftRegsTester
    extends FlatSpec
    with ChiselScalatestTester
    with Matchers {
  val dutName = "SegmentLedWithShiftRegs"
  behavior of dutName

  it should "simple" in {
    test(new SegmentLedWithShiftRegsTestSystem()) { c =>
      c.clock.setTimeout(2000)
      c.clock.step(1000)
    }
  }
}
