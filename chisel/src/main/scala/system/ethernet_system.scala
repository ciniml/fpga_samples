// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._
import chisel3.experimental.chiselName
import chisel3.stage.ChiselStage
import ethernet._
import _root_.util._

@chiselName
class EthernetSystem() extends RawModule {
  val clock = IO(Input(Clock()))
  val aresetn = IO(Input(Bool()))
  
  val in_tdata = IO(Input(UInt(8.W)))
  val in_tvalid = IO(Input(Bool()))
  val in_tready = IO(Output(Bool()))
  val in_tlast = IO(Input(Bool()))

  val out_tdata = IO(Output(UInt(8.W)))
  val out_tvalid = IO(Output(Bool()))
  val out_tready = IO(Input(Bool()))
  val out_tlast = IO(Output(Bool()))

  withClockAndReset(clock, !aresetn) {
    val service = Module(new EthernetService)
    val packetQueue = Module(new PacketQueue(Flushable(UInt(8.W)), 2048))
    packetQueue.io.write.valid <> service.io.out.valid
    packetQueue.io.write.ready <> service.io.out.ready
    packetQueue.io.write.bits.body <> service.io.out.bits.data
    packetQueue.io.write.bits.last <> service.io.out.bits.last

    service.io.in.valid <> in_tvalid
    service.io.in.ready <> in_tready
    service.io.in.bits.data <> in_tdata
    service.io.in.bits.last <> in_tlast
    service.io.in.bits.keep := 1.U

    packetQueue.io.read.valid <> out_tvalid
    packetQueue.io.read.ready <> out_tready
    packetQueue.io.read.bits.body <> out_tdata
    packetQueue.io.read.bits.last <> out_tlast
  }
}

object ElaborateEthernetSystem extends App {
  (new ChiselStage).emitVerilog(new EthernetSystem, Array(
    "-o", "ethernet_system.v",
    "--target-dir", "rtl/chisel/ethernet_system",
  ))
}
