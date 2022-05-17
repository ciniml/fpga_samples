// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2021.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)


package axi

import chisel3._
import chisel3.util._
import _root_.util._

object AXIChannelCombine {
    def apply(reader: AXI4IO, writer: AXI4IO ): AXI4IO = {
        val combinedParams = AXI4Params(reader.params.addressBits, reader.params.dataBits, AXI4ReadWrite, reader.params.maxBurstLength)
        val combined = Wire(AXI4IO(combinedParams))

        combined.ar.get <> reader.ar.get
        combined.r.get <> reader.r.get
        combined.aw.get <> writer.aw.get
        combined.w.get <> writer.w.get
        combined.b.get <> writer.b.get

        combined
    }
}
