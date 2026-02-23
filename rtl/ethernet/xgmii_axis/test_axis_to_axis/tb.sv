`timescale 1ns/1ps

module tb #(
    parameter bit SHIFT4 = 0
);
    logic clock;
    logic aresetn;

    logic [63:0] axis_to_xgmii_xgmii_d;
    logic [ 7:0] axis_to_xgmii_xgmii_c;
    logic [63:0] xgmii_to_axis_xgmii_d;
    logic [ 7:0] xgmii_to_axis_xgmii_c;
    
    logic  [63:0] saxis_tdata;
    logic         saxis_tvalid;
    logic         saxis_tready;
    logic  [7:0]  saxis_tkeep;
    logic         saxis_tuser;
    logic         saxis_tlast;

    logic  [63:0] maxis_tdata;
    logic         maxis_tvalid;
    logic  [7:0]  maxis_tkeep;
    logic         maxis_tuser;
    logic         maxis_tlast;

    axis_to_xgmii dut_axis_to_xgmii(
        .xgmii_d(axis_to_xgmii_xgmii_d),
        .xgmii_c(axis_to_xgmii_xgmii_c),
        .*
    );
    xgmii_to_axis dut_xgmii_to_axis(
        .xgmii_d(xgmii_to_axis_xgmii_d),
        .xgmii_c(xgmii_to_axis_xgmii_c),
        .*
    );

generate
    if( SHIFT4 ) begin: xgmii_shift4
        logic [31:0] xgmii_d_half = 32'h07070707;
        logic [3:0]  xgmii_c_half = '1;
        
        always_ff @(posedge clock) begin
            if( !aresetn ) begin
                xgmii_d_half <= {4 {8'h07}};
                xgmii_c_half <= '1;
                xgmii_to_axis_xgmii_d <= {8 {8'h07}};
                xgmii_to_axis_xgmii_c <= '1;
            end
            else begin
                xgmii_d_half <= axis_to_xgmii_xgmii_d[63:32];
                xgmii_c_half <= axis_to_xgmii_xgmii_c[7:4];
                xgmii_to_axis_xgmii_d <= {axis_to_xgmii_xgmii_d[31:0], xgmii_d_half};
                xgmii_to_axis_xgmii_c <= {axis_to_xgmii_xgmii_c[3:0], xgmii_c_half};
            end
        end
    end
    else begin: xgmii_shift0
        assign xgmii_to_axis_xgmii_d = axis_to_xgmii_xgmii_d;
        assign xgmii_to_axis_xgmii_c = axis_to_xgmii_xgmii_c;
    end
endgenerate

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        logic [63:0] tdata;
        logic [7:0]  tkeep;
        logic        tuser;
        logic        tlast;
        int          count;
    } tv_axis;

    localparam int NUMBER_OF_INPUTS = 100;
    localparam int MIN_BYTES = 1;
    localparam int MAX_BYTES = 24;

    property maxis_tkeep_never_null;
        @(posedge clock) disable iff (!maxis_tvalid) maxis_tkeep != 0;
    endproperty
    assert property(maxis_tkeep_never_null);

    initial begin
        tv_axis axis_in[$];

        aresetn <= 0;
        saxis_tdata <= 0;
        saxis_tvalid <= 0;
        saxis_tkeep <= 0;
        saxis_tlast <= 0;
        saxis_tuser <= 0;
        repeat(2) @(posedge clock);

        aresetn <= 1;
        repeat(2) @(posedge clock);
        #1;
        
        fork
            begin
                for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                    int length;
                    length = $urandom_range(MIN_BYTES, MAX_BYTES);

                    while(length > 0) begin
                        tv_axis row;
                        bit [8:0] tkeep;
                        tkeep = (9'b1 << length) - 1;

                        row.tdata = { $urandom(), $urandom() };
                        row.tkeep = tkeep[7:0];
                        row.tlast = length <= 8;
                        row.tuser = row.tlast ? $urandom_range(0, 1) : 0;
                        row.count = length > 8 ? 8 : length;
                        axis_in.push_back(row);
                        length -= row.count;

                        $info("input #%04d: count=%d, tdata=%016x, tkeep=%08b, tlast=%d, tuser=%d", i, row.count, row.tdata, row.tkeep, row.tlast, row.tuser);

                        saxis_tvalid <= 1;
                        saxis_tdata  <= row.tdata;
                        saxis_tkeep  <= row.tkeep;
                        saxis_tlast  <= row.tlast;
                        saxis_tuser  <= row.tuser;

                        do @(posedge clock); while(!saxis_tready);
                    end
                    saxis_tvalid <= 0;
                    repeat($urandom_range(0, 2)) @(posedge clock);
                end
            end
            begin
                for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                    while(1) begin
                        tv_axis row;
                        logic [63:0] tdata;
                        bit [65:0] tdata_mask;

                        row = axis_in.pop_front();
                        tdata_mask = (65'b1 << (row.count*8)) - 65'b1;
                        tdata = row.tdata & tdata_mask[63:0];

                        while(!maxis_tvalid) @(posedge clock);

                        if(     tdata != (maxis_tdata & tdata_mask[63:0])) $error("#%02d tdata mismatch, expected: %016x, actual: %016x", i,     tdata, maxis_tdata & tdata_mask[63:0]);
                        if( row.tkeep != maxis_tkeep                     ) $error("#%02d tkeep mismatch, expected: %08b , actual: %08b" , i, row.tkeep, maxis_tkeep);
                        if( row.tlast != maxis_tlast                     ) $error("#%02d tlast mismatch, expected: %d   , actual: %d"   , i, row.tlast, maxis_tlast);
                        if( row.tlast && row.tuser != maxis_tuser        ) $error("#%02d tuser mismatch, expected: %d   , actual: %d"   , i, row.tuser, maxis_tuser);

                        @(posedge clock);
                        if( row.tlast ) break;
                    end
                end
            end
        join
        
        $finish;
    end

endmodule

module test_shift0;
    tb #(.SHIFT4(0)) tb_inst();
endmodule

module test_shift4;
    tb #(.SHIFT4(1)) tb_inst();
endmodule