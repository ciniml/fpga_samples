`timescale 1ns/1ps

module tb();
    reg clock;
    reg aresetn;

    reg [3:0] mii_d;
    reg       mii_dv;
    reg       mii_er;

    reg  [7:0] maxis_tdata;
    reg        maxis_tvalid;
    reg        maxis_tuser;
    reg        maxis_tlast;

    mii_to_axis dut(
        .*
    );
    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end

    typedef struct {
        logic [3:0] mii_d;
        logic       mii_dv;
        logic [7:0] maxis_tdata;
        logic       maxis_tvalid;
        logic       maxis_tuser;
        logic       maxis_tlast;

    } tv_row;
    tv_row tv_rows[];
    

    initial begin
        tv_rows = '{
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hd, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'ha, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hb, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hc, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hd, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hba, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hba, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            // Odd nibble preambles.
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h5, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hd, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'ha, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hb, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hc, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'hd, mii_dv: 1, maxis_tdata: 8'h00, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hba, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hba, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 1, maxis_tuser: 0, maxis_tlast: 1},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0},
            '{mii_d: 4'h0, mii_dv: 0, maxis_tdata: 8'hdc, maxis_tvalid: 0, maxis_tuser: 0, maxis_tlast: 0}
        };

        aresetn <= 0;
        mii_d <= 0;
        mii_dv <= 0;
        mii_er <= 0;
        repeat(2) @(posedge clock);
        if( maxis_tvalid != 0 ) $error("maxis_tvalid must be deasserted while resetting.");

        aresetn <= 1;
        repeat(2) @(posedge clock);
        //#1;
        if( maxis_tvalid != 0 ) $error("maxis_tvalid must be deasserted while idle.");
        
        for(int i = 0; i < tv_rows.size(); i++) begin
            tv_row row;
            bit [7:0] tdata;

            row = tv_rows[i];

            if( row.maxis_tvalid != maxis_tvalid  ) $error("#%02d TVALID mismatch, expected: %d, actual: %d", i, row.maxis_tvalid, maxis_tvalid);
            if( row.maxis_tvalid ) begin
                if( row.maxis_tdata != maxis_tdata ) $error("#%02d TDATA mismatch, expected: %016x, actual: %016x", i, row.maxis_tdata, maxis_tdata);
                if( row.maxis_tlast != maxis_tlast ) $error("#%02d TLAST mismatch, expected: %d, actual: %d", i, row.maxis_tlast, maxis_tlast);
                //if( row.maxis_tlast && row.maxis_tuser != maxis_tuser ) $error("#%02d TUSER mismatch, expected: %d, actual: %d", i, row.maxis_tuser, maxis_tuser);
            end

            #1;
            
            mii_d <= row.mii_d;
            mii_dv <= row.mii_dv;

            @(posedge clock);
        end

        $finish;
    end

endmodule
