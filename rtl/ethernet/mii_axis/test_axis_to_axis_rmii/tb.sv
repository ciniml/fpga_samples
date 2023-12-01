`timescale 1ns/1ps

module tb;
    logic clock;
    logic aresetn;

    logic [1:0] axis_to_rmii_rmii_d;
    logic       axis_to_rmii_rmii_en;
    logic [1:0] rmii_to_axis_rmii_d;
    logic       rmii_to_axis_rmii_dv;
    
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
    axis_to_rmii dut_axis_to_rmii(
        .rmii_d (axis_to_rmii_rmii_d),
        .rmii_en(axis_to_rmii_rmii_en),
        .saxis_tvalid(preamble_axis_tvalid),
        .saxis_tready(preamble_axis_tready),
        .saxis_tdata (preamble_axis_tdata ),
        .saxis_tlast (preamble_axis_tlast ),
        .*
    );

    rmii_to_axis dut_rmii_to_axis(
        .rmii_d (rmii_to_axis_rmii_d),
        .rmii_dv(rmii_to_axis_rmii_dv),
        .*
    );

    // Inject toggling CRS_DV at the last 6 cycles of a frame.
    logic [9:0] rmii_d_buf  = 0;
    logic [5:0] rmii_dv_buf = 0;
    logic       rmii_dv     = 0;
    always_ff @(posedge clock) begin
        rmii_dv <= axis_to_rmii_rmii_en;
        if( rmii_dv && !axis_to_rmii_rmii_en ) begin
            rmii_dv_buf <= { axis_to_rmii_rmii_en, rmii_dv_buf[5:1] } & 6'b010101;
        end
        else begin
            rmii_dv_buf <= { axis_to_rmii_rmii_en, rmii_dv_buf[5:1] };
        end
        rmii_d_buf  <= { axis_to_rmii_rmii_d, rmii_d_buf[9:2] };
    end

    assign rmii_to_axis_rmii_d  = rmii_d_buf[1:0];
    assign rmii_to_axis_rmii_dv = rmii_dv_buf[0] & !(rmii_dv && !axis_to_rmii_rmii_en);

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
    localparam int MIN_BYTES = 2;
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
