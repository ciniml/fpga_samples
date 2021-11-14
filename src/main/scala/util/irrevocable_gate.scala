// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util


import chisel3._
import chisel3.util._

class IrrevocableGate[T <: Data](gen: T) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
        val enable = Input(Bool())
    })

    val outBits = Reg(gen)
    val outValid = RegInit(false.B)
    val outReady = io.out.ready
    io.out.valid := outValid
    io.out.bits := outBits
    val inBits = io.in.bits
    val inValid = io.in.valid
    val inReady = WireDefault(false.B)
    io.in.ready := inReady

    when(outValid && outReady) {
        outValid := false.B
    }
    when((!outValid || outReady) && io.enable) {
        outValid := inValid
        outBits := inBits
        inReady := true.B
    }
}

object WithIrrevocableGate {
    def apply[T <: Data](in: IrrevocableIO[T], enable: Bool): IrrevocableIO[T] = {
        val gate = Module(new IrrevocableGate(chiselTypeOf(in.bits)))
        gate.io.in <> in
        gate.io.enable := enable
        gate.io.out
    }
}
