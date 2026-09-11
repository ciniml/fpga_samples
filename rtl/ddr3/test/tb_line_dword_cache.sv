// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test entry points: the bodies live in test/*.sv (Veryl.toml include_files).

`ifdef __veryl_test_ddr3_test_line_dword_cache__
    `ifdef __veryl_wavedump_ddr3_test_line_dword_cache__
        module __veryl_wavedump;
            initial begin
                $dumpfile("test_line_dword_cache.vcd");
                $dumpvars();
            end
        endmodule
    `endif
`ifndef SYNTHESIS
module test_line_dword_cache;
    line_dword_cache_tb tb ();
endmodule
`endif
`endif
//# sourceMappingURL=tb_line_dword_cache.sv.map
