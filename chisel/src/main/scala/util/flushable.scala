// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)

package util

import chisel3._
import chisel3.internal.firrtl.Width

class Flushable[T <: Data](gen: T) extends Bundle {
    val body = gen.cloneType.asInstanceOf[T]
    val last = Bool()

    override def cloneType: this.type = new Flushable(gen).asInstanceOf[this.type]
}

object Flushable {
    def apply[T <: Data](gen: T): Flushable[T] = {
        new Flushable(gen)
    }
    def apply(width: Width): Flushable[UInt] = {
        new Flushable(UInt(width))
    }
}
