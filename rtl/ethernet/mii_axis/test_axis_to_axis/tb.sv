`timescale 1ns/1ps

module tb;
    logic clock;
    logic aresetn;

    logic [3:0] axis_to_mii_mii_d;
    logic       axis_to_mii_mii_en;
    logic       axis_to_mii_mii_er;
    logic [3:0] mii_to_axis_mii_d;
    logic       mii_to_axis_mii_dv;
    logic       mii_to_axis_mii_er;
    
    logic  [7:0] saxis_tdata;
    logic        saxis_tvalid;
    logic        saxis_tready;
    logic        saxis_tlast;

    logic  [7:0] preamble_axis_tdata;
    logic        preamble_axis_tvalid;
    logic        preamble_axis_tready;
    logic        preamble_axis_tlast;

    logic  [7:0] maxis_tdata;
    logic        maxis_tvalid;
    logic        maxis_tuser;
    logic        maxis_tlast;

    prepend_preamble dut_prepend_preamble(
        .maxis_tvalid(preamble_axis_tvalid),
        .maxis_tready(preamble_axis_tready),
        .maxis_tdata (preamble_axis_tdata ),
        .maxis_tlast (preamble_axis_tlast ),
        .*
    );
    axis_to_mii dut_axis_to_mii(
        .mii_d (axis_to_mii_mii_d),
        .mii_en(axis_to_mii_mii_en),
        .mii_er(axis_to_mii_mii_er),
        .saxis_tvalid(preamble_axis_tvalid),
        .saxis_tready(preamble_axis_tready),
        .saxis_tdata (preamble_axis_tdata ),
        .saxis_tlast (preamble_axis_tlast ),
        .*
    );

    mii_to_axis dut_mii_to_axis(
        .mii_d (mii_to_axis_mii_d),
        .mii_dv(mii_to_axis_mii_dv),
        .mii_er(mii_to_axis_mii_er),
        .*
    );

    assign mii_to_axis_mii_d  = axis_to_mii_mii_d;
    assign mii_to_axis_mii_dv = axis_to_mii_mii_en;
    assign mii_to_axis_mii_er = axis_to_mii_mii_er;

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        logic [7:0] tdata;
        logic       tuser;
        logic       tlast;
    } tv_axis;

    localparam int NUMBER_OF_INPUTS = 200;
    localparam int MIN_BYTES = 1;
    localparam int MAX_BYTES = 24;

    initial begin
        tv_axis axis_in[$];

        aresetn <= 0;
        saxis_tdata <= 0;
        saxis_tvalid <= 0;
        saxis_tlast <= 0;
        repeat(2) @(posedge clock);

        aresetn <= 1;
        repeat(2) @(posedge clock);
        #1;
        fork
            fork
                begin
                    for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                        int length;
                        int count;
                        length = $urandom_range(MIN_BYTES, MAX_BYTES);

                        for(int count = 0; count < length; count++ ) begin
                            tv_axis row;

                            row.tdata = $urandom();
                            row.tlast = count == length - 1;
                            row.tuser = row.tlast ? $urandom_range(0, 1) : 0;
                            axis_in.push_back(row);
                            $info("input #%04d: tdata=%02x, tlast=%d, tuser=%d", i, row.tdata, row.tlast, row.tuser);

                            saxis_tvalid <= 1;
                            saxis_tdata  <= row.tdata;
                            saxis_tlast  <= row.tlast;
                            //saxis_tuser  <= row.tuser;

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

                            while(1) begin
                                row = axis_in.pop_front();
                                if( row.tdata !== 8'hxx ) break;
                                @(posedge clock);
                            end
                            while(!maxis_tvalid) @(posedge clock);

                            $info("#%04d: tdata=%02x, tlast=%d, tuser=%d", i, row.tdata, row.tlast, row.tuser);

                            if( row.tdata != maxis_tdata                     ) $error("#%02d tdata mismatch, expected: %02x, actual: %02x"  , i, row.tdata, maxis_tdata);
                            if( row.tlast != maxis_tlast                     ) $error("#%02d tlast mismatch, expected: %d   , actual: %d"   , i, row.tlast, maxis_tlast);
                            //if( row.tlast && row.tuser != maxis_tuser        ) $error("#%02d tuser mismatch, expected: %d   , actual: %d"   , i, row.tuser, maxis_tuser);
                            
                            @(posedge clock);
                            if( row.tlast ) break;
                        end
                    end
                end
            join
            begin
                int limit = NUMBER_OF_INPUTS * MAX_BYTES * 10;
                for(int cycles = 0; cycles < limit; cycles++ ) @(posedge clock);
                $error("Error: simulation timed out after %d cycles.", limit);
            end
        join_any
        disable fork;
        $finish;
    end

endmodule
