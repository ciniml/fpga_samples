// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util._

class IrrevocableChecker[T <: Data](gen: T) extends Module {
    val io = IO(new Bundle{
        val in = Flipped(Irrevocable(gen))
        val out = Irrevocable(gen)
        val error = Output(Bool())
    })

    io.out <> io.in

    val error = RegInit(false.B)
    io.error := error

    val prevValid = RegNext(io.in.valid)
    val prevReady = RegNext(io.in.ready)

    when(prevValid && !prevReady && !io.in.valid ) {
        printf(p"Irrevocable violation detected!
")
        error := true.B
    }
}

object IrrevocableChecker {
    def apply[T <: Data](in: IrrevocableIO[T], error: Option[Bool] = None): IrrevocableIO[T] = {
        val checker = Module(new IrrevocableChecker(chiselTypeOf(in.bits)))
        checker.io.in <> in
        if( error.isDefined ) {
            error.get := checker.io.error
        }
        checker.io.out
    }
}
