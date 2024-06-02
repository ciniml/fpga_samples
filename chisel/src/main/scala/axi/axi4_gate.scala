// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)


package axi

import chisel3._
import chisel3.util._

import _root_.util.WithIrrevocableGate

class AXI4Gate(axi4Params: AXI4Params) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(AXI4IO(axi4Params))
        val out = AXI4IO(axi4Params)
        val enable = Input(Bool())
    })

    axi4Params.mode match {
        case AXI4WriteOnly => {}
        case _ => {
            io.out.ar.get <> WithIrrevocableGate(io.in.ar.get, io.enable)
            io.out.r.get <> io.in.r.get
        }
    }

    axi4Params.mode match {
        case AXI4ReadOnly => {}
        case _ => {
            io.out.aw.get <> WithIrrevocableGate(io.in.aw.get, io.enable)
            io.out.w.get <> io.in.w.get
            io.out.b.get <> io.in.b.get
        }
    }
}

object WithAXI4Gate {
    def apply(in: AXI4IO, enable: Bool): AXI4IO = {
        val gate = Module(new AXI4Gate(in.params))
        gate.io.in <> in
        gate.io.enable := enable
        gate.io.out
    }
}
