// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._
import _root_.util._

class AXIProtocolChecker(axiParams: AXI4Params) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(AXI4IO(axiParams))
        val out = AXI4IO(axiParams)
        val error = Output(Bool())
    })

    val writeChannelError = WireDefault(false.B)
    axiParams.mode match {
        case AXI4ReadOnly =>  {}
        case _ => {
            val awError = WireDefault(false.B)
            val wError = WireDefault(false.B)
            val bError = WireDefault(false.B)
            io.out.aw.get <> IrrevocableChecker(io.in.aw.get, Some(awError))
            io.out.w.get <> IrrevocableChecker(io.in.w.get, Some(wError))
            io.in.b.get <> IrrevocableChecker(io.out.b.get, Some(bError))

            writeChannelError := awError | wError | bError
        }
    }
    val readChannelError = WireDefault(false.B)
    axiParams.mode match {
        case AXI4WriteOnly =>  {}
        case _ => {
            val arError = WireDefault(false.B)
            val rError = WireDefault(false.B)
            io.out.ar.get <> IrrevocableChecker(io.in.ar.get, Some(arError))
            io.in.r.get <> IrrevocableChecker(io.out.r.get, Some(rError))

            readChannelError := arError | rError
        }
    }

    io.error := readChannelError | writeChannelError
}
object AXIProtocolChecker {
    def apply(in: AXI4IO, error: Option[Bool] = None): AXI4IO = {
        val checker = Module(new AXIProtocolChecker(in.params))
        checker.io.in <> in
        if( error.isDefined ) {
            error.get := checker.io.error
        }
        checker.io.out
    }
}
