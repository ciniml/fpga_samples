`timescale 1ns/1ps

module tb();
    reg clock;
    reg aresetn;

    reg [63:0] xgmii_d;
    reg [7:0] xgmii_c;

    reg  [63:0] maxis_tdata;
    reg         maxis_tvalid;
    reg  [7:0]  maxis_tkeep;
    reg         maxis_tuser;
    reg         maxis_tlast;

    xgmii_to_axis dut(
        .*
    );
    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end

    typedef struct {
        logic [63:0] xgmii_d;
        logic [7:0]  xgmii_c;
        logic [63:0] maxis_tdata;
        logic        maxis_tvalid;
        logic [7:0]  maxis_tkeep;
        logic        maxis_tuser;
        logic        maxis_tlast;

    } tv_row;
    tv_row tv_rows[];
    

    initial begin
        tv_rows = '{
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0e0d_0c0b_0a09_0807, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_fd0f, xgmii_c: 8'b1111_1110, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0f0e_0d0c_0b0a_0908, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'hfd0d_0c0b_0a09_0807, xgmii_c: 8'b1000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h07fd_0d0c_0b0a_0908, maxis_tkeep: 8'b0011_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0707_0707_0707_07fd, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'hfd06_0504_0302_0100, maxis_tkeep: 8'b0111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0707_0707_07fd_0807, xgmii_c: 8'b1111_1100, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110, maxis_tdata: 64'hfb07_0707_0707_fd08, maxis_tkeep: 8'b0000_0001, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_07fe, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'hfe06_0504_0302_0100, maxis_tkeep: 8'b0111_1111, maxis_tvalid: 1, maxis_tuser: 1, maxis_tlast: 1},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0e0d_0c0b_0a09_0807, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_fe0f, xgmii_c: 8'b1111_1110, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0f0e_0d0c_0b0a_0908, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 1, maxis_tlast: 1},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0201_00fb_0707_0707, xgmii_c: 8'b0001_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_fd07_0605_0403, xgmii_c: 8'b1110_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0201_00fb_0707_0707, xgmii_c: 8'b0001_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0a09_0807_0605_0403, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_07fd_0c0b, xgmii_c: 8'b1111_1100, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_000c_0b0a_0908, maxis_tkeep: 8'b0001_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0201_00fb_0707_0707, xgmii_c: 8'b0001_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0a09_0807_0605_0403, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h07fd_100f_0e0d_0c0b, xgmii_c: 8'b1100_0000, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0f0e_0d0c_0b0a_0908, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_0000_0010, maxis_tkeep: 8'b0000_0001, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},

            '{xgmii_d: 64'h0201_00fb_0707_0707, xgmii_c: 8'b0001_1111, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0a09_0807_0605_0403, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h1211_100f_0e0d_0c0b, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h1a19_1817_1615_1413, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0f0e_0d0c_0b0a_0908, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_07fd, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h1716_1514_1312_1110, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0201_00fb_0707_0707, xgmii_c: 8'b0001_1111, maxis_tdata: 64'h0000_0000_001a_1918, maxis_tkeep: 8'b0000_0111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0a09_0807_0605_0403, xgmii_c: 8'b0000_0000, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_07fd, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0000_0000_000a_0908, maxis_tkeep: 8'b0000_0111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},

            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110, maxis_tdata: 64'h0000_0000_0000_0000, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111, maxis_tdata: 64'h0706_0504_0302_0100, maxis_tkeep: 8'b1111_1111, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1}
        };

        aresetn <= 0;
        xgmii_d <= { 8 {8'h07} };
        xgmii_c <= 8'hff;
        repeat(2) @(posedge clock);
        if( maxis_tvalid != 0 ) $error("maxis_tvalid must be deasserted while resetting.");

        aresetn <= 1;
        repeat(2) @(posedge clock);
        //#1;
        if( maxis_tvalid != 0 ) $error("maxis_tvalid must be deasserted while idle.");
        
        for(int i = 0; i < tv_rows.size(); i++) begin
            tv_row row;
            bit [63: 0] tdata_mask;
            bit [63: 0] tdata;
            bit [ 7: 0] tkeep;

            row = tv_rows[i];
            
            tkeep = row.maxis_tkeep;
            tdata_mask = {{8 {tkeep[7]}}, {8 {tkeep[6]}}, {8 {tkeep[5]}}, {8 {tkeep[4]}}, {8 {tkeep[3]}}, {8 {tkeep[2]}}, {8 {tkeep[1]}}, {8 {tkeep[0]}}};
            tdata      = maxis_tdata & tdata_mask;
            row.maxis_tdata &= tdata_mask;

            if( row.maxis_tvalid != maxis_tvalid  ) $error("#%02d TVALID mismatch, expected: %d, actual: %d", i, row.maxis_tvalid, maxis_tvalid);
            if( row.maxis_tvalid ) begin
                if( row.maxis_tdata !=       tdata ) $error("#%02d TDATA mismatch, expected: %016x, actual: %016x", i, row.maxis_tdata, tdata);
                if( row.maxis_tkeep != maxis_tkeep ) $error("#%02d TKEEP mismatch, expected: %08b, actual: %08b", i, row.maxis_tkeep, maxis_tkeep);
                if( row.maxis_tlast != maxis_tlast ) $error("#%02d TLAST mismatch, expected: %d, actual: %d", i, row.maxis_tlast, maxis_tlast);
                if( row.maxis_tlast && row.maxis_tuser != maxis_tuser ) $error("#%02d TUSER mismatch, expected: %d, actual: %d", i, row.maxis_tuser, maxis_tuser);
            end

            #1;
            
            xgmii_d <= row.xgmii_d;
            xgmii_c <= row.xgmii_c;

            @(posedge clock);
        end

        $finish;
    end

endmodule
