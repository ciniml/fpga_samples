// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._

import uart._
import _root_.circt.stage.ChiselStage


class UartSystem() extends RawModule {
  val clock = IO(Input(Clock()))
  val resetn = IO(Input(Bool()))
  val tx = IO(Output(Bool()))
  val rx = IO(Input(Bool()))
  
  withClockAndReset(clock, !resetn) {
    val clockFreq = 24000000  // 24MHz
    val baudRate = 115200
    val uartRx = Module(new UartRx(8, clockFreq / baudRate, 3))
    val uartTx = Module(new UartTx(8, clockFreq / baudRate))

    uartRx.io.out <> uartTx.io.in

    tx <> uartTx.io.tx
    rx <> uartRx.io.rx
  }
}


object Elaborate extends App {
  ChiselStage.emitSystemVerilogFile(new UartSystem, Array(
    "-o", "uart_system.v",
    "--target-dir", "rtl/chisel/uart",
  ))
}
