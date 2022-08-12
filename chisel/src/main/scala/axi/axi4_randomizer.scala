// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._
import _root_.util._

class AXIRandomizer(axiParams: AXI4Params) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(AXI4IO(axiParams))
        val out = AXI4IO(axiParams)
    })

    axiParams.mode match {
        case AXI4ReadOnly =>  {}
        case _ => {
            io.out.aw.get <> IrrevocableRandomizer(io.in.aw.get)
            io.out.w.get <> IrrevocableRandomizer(io.in.w.get)
            io.in.b.get <> IrrevocableRandomizer(io.out.b.get)
        }
    }
    val readChannelError = WireDefault(false.B)
    axiParams.mode match {
        case AXI4WriteOnly =>  {}
        case _ => {
            io.out.ar.get <> IrrevocableRandomizer(io.in.ar.get)
            io.in.r.get <> IrrevocableRandomizer(io.out.r.get)
        }
    }
}
object AXIRandomizer {
    def apply(in: AXI4IO): AXI4IO = {
        val randomizer = Module(new AXIProtocolChecker(in.params))
        randomizer.io.in <> in
        randomizer.io.out
    }
}
