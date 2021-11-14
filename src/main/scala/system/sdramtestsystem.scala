// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package system

import chisel3._
import chisel3.util._
import sdram._
import axi._
import java.io.FileInputStream
import scala.collection.mutable

class SDRAMTestSystem() extends Module {
  val params = SDRAMBridgeParams(20, 4, 8)
  val axi4Params = AXI4Params(params.addressBits, params.dataBits, AXI4ReadWrite, Some(params.maxBurstLength))
  val io = IO(new Bundle {
      val axi = Flipped(new AXI4IO(axi4Params))
  })
  
  val dut = Module(new SDRCBridge(params))
  val mem = Module(new SimSDRC(params, 1024*1024))
  
  dut.io.sdrc <> mem.io.sdrc
  io.axi <> dut.io.axi
}
