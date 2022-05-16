// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2022.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

// See README.md for license details.

package spi

import chisel3._
import chisel3.util._
import _root_.util._

class SPIIO extends Bundle {
    val miso = Input(Bool())
    val mosi = Output(Bool())
    val cs = Output(Bool())
    val sck = Output(Bool())
}
object SPIIO {
    def apply() : SPIIO  = {
        new SPIIO()
    }
}