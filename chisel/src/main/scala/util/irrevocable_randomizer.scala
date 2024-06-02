// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._

class IrrevocableRandomizer[T <: Data](gen: T) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
    })

    val block = random.LFSR(16).xorR
    io.out.valid := io.in.valid && !block
    io.in.ready := io.out.ready && !block
    io.out.bits := io.in.bits
}

object IrrevocableRandomizer {
    def apply[T <: Data](in: IrrevocableIO[T]): IrrevocableIO[T] = {
        val checker = Module(new IrrevocableRandomizer(chiselTypeOf(in.bits)))
        checker.io.in <> in
        checker.io.out
    }
}
