// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.util.Cat

class Bin2Gray(val width: Int) extends Module {
    val io = IO(new Bundle {
        val in = Input(UInt(width.W))
        val out = Output(UInt(width.W))
    })

    io.out := io.in ^ (io.in >> 1)
}
class Gray2Bin(val width: Int) extends Module {
    val io = IO(new Bundle {
        val in = Input(UInt(width.W))
        val out = Output(UInt(width.W))
    })

    val out = Wire(Vec(width, Bool()))
    out(width - 1) := io.in(width - 1)

    (width - 2 to 0 by -1).foreach(i => {
        out(i) := out(i+1) ^ io.in(i)
    })
    io.out := out.asUInt
}
class GrayCodeCounter(val width: Int) extends Module {
    val io = IO(new Bundle{
        val counter = Output(UInt(width.W))
    })

    val bin2gray = Module(new Bin2Gray(width))
    val counter = RegInit(0.U(width.W))

    counter := counter + 1.U
    bin2gray.io.in := counter
    io.counter := bin2gray.io.out
}
