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
    
    val rxQueue = Module(new Queue(Flushable(UInt(8.W)), 2048))
    rxQueue.io.deq.valid <> service.io.in.valid
    rxQueue.io.deq.ready <> service.io.in.ready
    rxQueue.io.deq.bits.body <> service.io.in.bits.data
    rxQueue.io.deq.bits.last <> service.io.in.bits.last
    service.io.in.bits.keep := 1.U

    val txPacketQueue = Module(new PacketQueue(Flushable(UInt(8.W)), 2048))
    txPacketQueue.io.write.valid <> service.io.out.valid
    txPacketQueue.io.write.ready <> service.io.out.ready
    txPacketQueue.io.write.bits.body <> service.io.out.bits.data
    txPacketQueue.io.write.bits.last <> service.io.out.bits.last

    rxQueue.io.enq.valid <> in_tvalid
    rxQueue.io.enq.ready <> in_tready
    rxQueue.io.enq.bits.body <> in_tdata
    rxQueue.io.enq.bits.last <> in_tlast

    txPacketQueue.io.read.valid <> out_tvalid
    txPacketQueue.io.read.ready <> out_tready
    txPacketQueue.io.read.bits.body <> out_tdata
    txPacketQueue.io.read.bits.last <> out_tlast
  }
}

object ElaborateEthernetSystem extends App {
  (new ChiselStage).emitVerilog(new EthernetSystem, Array(
    "-o", "ethernet_system.v",
    "--target-dir", "rtl/chisel/ethernet_system",
  ))
}
