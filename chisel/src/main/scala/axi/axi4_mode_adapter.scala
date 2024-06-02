// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package axi

import chisel3._
import chisel3.util._

import _root_.util.IrrevocableRegSlice

class AXI4ModeAdapter(inParams: AXI4Params, outMode: AXI4Mode) extends Module {
    val outParams = AXI4Params(inParams.addressBits, inParams.dataBits, outMode, inParams.maxBurstLength)
    val io = IO(new Bundle {
        val in = Flipped(AXI4IO(inParams))
        val out = AXI4IO(outParams)
    })

    inParams.mode match {
        case AXI4WriteOnly => {
            outMode match {
                case AXI4WriteOnly => {}
                case _ => {
                    // Output IF has READ channel, but the input IF has no READ channel.
                    io.out.ar.get.valid := false.B
                    io.out.ar.get.bits := DontCare
                    io.out.r.get.ready := false.B
                }
            }
        }
        case _ => { // Input IF has READ channel
            outMode match {
                case AXI4WriteOnly => {
                    // Output IF has no READ channel. terminate the input READ channel.
                    io.in.ar.get.ready := false.B
                    io.in.r.get.valid := false.B
                    io.in.r.get.bits := DontCare
                }
                case _ => {
                    // Both input and output have READ channel.
                    io.in.ar.get <> io.out.ar.get
                    io.in.r.get <> io.out.r.get
                }
            }
        }
    }

    inParams.mode match {
        case AXI4ReadOnly => {
            outMode match {
                case AXI4ReadOnly => {}
                case _ => {
                    // Output IF has WRITE channel, but the input IF has no WRITE channel.
                    io.out.aw.get.valid := false.B
                    io.out.aw.get.bits := DontCare
                    io.out.w.get.valid := false.B
                    io.out.w.get.bits := DontCare
                    io.out.b.get.ready := false.B
                }
            }
        }
        case _ => { // Input IF has WRITE channel
            outMode match {
                case AXI4ReadOnly => {
                    // Output IF has no WRITE channel. terminate the input WRITE channel.
                    io.in.aw.get.ready := false.B
                    io.in.w.get.ready := false.B
                    io.in.b.get.valid := false.B
                    io.in.b.get.bits := DontCare
                }
                case _ => {
                    // Both input and output have WRITE channel.
                    io.in.aw.get <> io.out.aw.get
                    io.in.w.get <> io.out.w.get
                    io.in.b.get <> io.out.b.get
                }
            }
        }
    }
}

object ToAXIMode {
    def apply(io: AXI4IO, mode: AXI4Mode): AXI4IO = {
        val adapter = Module(new AXI4ModeAdapter(io.params, mode))
        adapter.io.in <> io
        adapter.io.out
    }
}
