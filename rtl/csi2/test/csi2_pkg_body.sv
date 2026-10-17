// csi2_pkg: header ECC and payload CRC against the CSI-2 spec examples.
`timescale 1ns/1ps
module csi2_pkg_body #(parameter bit RUN = 0) ();
    initial if (RUN) begin
        logic [7:0] v1 [24] = '{8'hFF,8'h00,8'h00,8'h02,8'hB9,8'hDC,8'hF3,8'h72,8'hBB,8'hD4,8'hB8,8'h5A,
                                8'hC8,8'h75,8'hC2,8'h7C,8'h81,8'hF8,8'h05,8'hDF,8'hFF,8'h00,8'h00,8'h01};
        logic [7:0] v2 [24] = '{8'hFF,8'h00,8'h00,8'h00,8'h1E,8'hF0,8'h1E,8'hC7,8'h4F,8'h82,8'h78,8'hC5,
                                8'h82,8'hE0,8'h8C,8'h70,8'hD2,8'h3C,8'h78,8'hE9,8'hFF,8'h00,8'h00,8'h01};
        logic [15:0] c1 = 16'hFFFF, c2 = 16'hFFFF;
        logic [23:0] d;
        logic [5:0] e, syn;
        for (int i = 0; i < 24; i++) begin c1 = csi2_pkg::crc16_byte(c1, v1[i]); c2 = csi2_pkg::crc16_byte(c2, v2[i]); end
        if (c1 !== 16'h00F0 || c2 !== 16'hE569) $fatal(1, "crc %04h %04h", c1, c2);
        if (csi2_pkg::ecc6(24'h01F037) !== 6'h3F) $fatal(1, "ecc %02h", csi2_pkg::ecc6(24'h01F037));
        // every single-bit data error is located, every single ECC-bit error recognised
        d = 24'h5A1C2B; e = csi2_pkg::ecc6(d);
        for (int k = 0; k < 24; k++) begin
            syn = csi2_pkg::ecc6(d ^ (24'h1 << k)) ^ e;
            if (csi2_pkg::ecc_fix(syn) !== (24'h1 << k)) $fatal(1, "fix bit %0d", k);
        end
        for (int k = 0; k < 6; k++)
            if (!csi2_pkg::ecc_bit_err(6'h1 << k) || csi2_pkg::ecc_fix(6'h1 << k) !== 0) $fatal(1, "ecc bit %0d", k);
        $display("csi2_pkg: PASS");
        $finish;
    end
endmodule
