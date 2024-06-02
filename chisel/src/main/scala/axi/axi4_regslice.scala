// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._

import _root_.util.IrrevocableRegSlice

class AXI4RegSlice(axi4Params: AXI4Params) extends Module {
    val io = IO(new Bundle {
        val in = Flipped(AXI4IO(axi4Params))
        val out = AXI4IO(axi4Params)
    })

    axi4Params.mode match {
        case AXI4WriteOnly => {}
        case _ => {
            val sliceAr = Module(new IrrevocableRegSlice(new AXI4A(axi4Params)))
            val sliceR = Module(new IrrevocableRegSlice(new AXI4R(axi4Params)))

            io.in.ar.get <> sliceAr.io.in
            io.out.ar.get <> sliceAr.io.out
            io.in.r.get <> sliceR.io.out
            io.out.r.get <> sliceR.io.in
        }
    }

    axi4Params.mode match {
        case AXI4ReadOnly => {}
        case _ => {
            val sliceAw = Module(new IrrevocableRegSlice(new AXI4A(axi4Params)))
            val sliceW = Module(new IrrevocableRegSlice(new AXI4W(axi4Params)))
            val sliceB = Module(new IrrevocableRegSlice(new AXI4B(axi4Params)))

            io.in.aw.get <> sliceAw.io.in
            io.out.aw.get <> sliceAw.io.out
            io.in.w.get <> sliceW.io.in
            io.out.w.get <> sliceW.io.out
            io.in.b.get <> sliceB.io.out
            io.out.b.get <> sliceB.io.in
        }
    }
}

object WithAXI4RegSlice {
    def apply(in: AXI4IO): AXI4IO = {
        val regSlice = Module(new AXI4RegSlice(in.params))
        regSlice.io.in <> in
        regSlice.io.out
    }
}
