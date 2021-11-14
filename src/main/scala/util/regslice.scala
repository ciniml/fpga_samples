// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util


import chisel3._
import chisel3.util._

class IrrevocableRegSlice[T <: Data](gen: T) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
    })

    val read = RegInit(0.U(2.W))
    val write = RegInit(0.U(2.W))
    val data = Reg(Vec(2, gen))

    val empty = Wire(Bool())
    val full = Wire(Bool())

    empty := read === write
    full := read(1) =/= write(1) && read(0) === write(0)

    when(io.in.valid && io.in.ready) {
        data(write(0)) := io.in.bits
        write := write + 1.U
    }
    when(io.out.valid && io.out.ready) {
        read := read + 1.U
    }

    io.in.ready := !full
    io.out.valid := !empty
    io.out.bits := data(read(0))
}

object UnsafeIrrevocable {
    def apply[T <: Data](in: DecoupledIO[T]): IrrevocableIO[T] = {
        val irrevocable = Wire(new IrrevocableIO(chiselTypeOf(in.bits)))
        irrevocable.valid := in.valid
        irrevocable.bits := in.bits
        in.ready := irrevocable.ready
        irrevocable
    }
}

object WithIrrevocableRegSlice {
    def apply[T <: Data](in: IrrevocableIO[T]): IrrevocableIO[T] = {
        val regSlice = Module(new IrrevocableRegSlice(chiselTypeOf(in.bits)))
        regSlice.io.in <> in
        regSlice.io.out
    }
}
