`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    logic [3:0] mii_d;
    logic       mii_en;
    logic       mii_er;

    logic  [7:0] saxis_tdata;
    logic        saxis_tvalid;
    logic        saxis_tready;
    logic        saxis_tlast;

    axis_to_mii dut(
        .*
    );
    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        logic [7:0]  saxis_tdata;
        logic        saxis_tlast;
    } tv_axis_in;

    typedef struct {
        logic [7:0] mii_d;
        logic       mii_en;
    } tv_mii_out;
    
    tv_axis_in tv_in_rows[];
    tv_mii_out tv_out_rows[];
    

    initial begin
        tv_out_rows = '{
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'hd, mii_en: 1 },
            '{mii_d: 4'hb, mii_en: 1 },
            '{mii_d: 4'ha, mii_en: 1 },
            '{mii_d: 4'hd, mii_en: 1 },
            '{mii_d: 4'hc, mii_en: 1 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'h5, mii_en: 1 },
            '{mii_d: 4'hd, mii_en: 1 },
            '{mii_d: 4'hb, mii_en: 1 },
            '{mii_d: 4'ha, mii_en: 1 },
            '{mii_d: 4'hd, mii_en: 1 },
            '{mii_d: 4'hc, mii_en: 1 },
            '{mii_d: 4'hf, mii_en: 1 },
            '{mii_d: 4'he, mii_en: 1 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 },
            '{mii_d: 4'h0, mii_en: 0 }
        };

        tv_in_rows = '{
            '{saxis_tdata: 8'h55, saxis_tlast: 0},
            '{saxis_tdata: 8'h55, saxis_tlast: 0},
            '{saxis_tdata: 8'hd5, saxis_tlast: 0},
            '{saxis_tdata: 8'hab, saxis_tlast: 0},
            '{saxis_tdata: 8'hcd, saxis_tlast: 1},
            
            '{saxis_tdata: 8'h55, saxis_tlast: 0},
            '{saxis_tdata: 8'h55, saxis_tlast: 0},
            '{saxis_tdata: 8'hd5, saxis_tlast: 0},
            '{saxis_tdata: 8'hab, saxis_tlast: 0},
            '{saxis_tdata: 8'hcd, saxis_tlast: 0},
            '{saxis_tdata: 8'hef, saxis_tlast: 1}
        };

        aresetn <= 0;
        saxis_tdata <= 0;
        saxis_tvalid <= 0;
        saxis_tlast <= 0;
        repeat(2) @(posedge clock);

        aresetn <= 1;
        repeat(2) @(posedge clock);
        #1;
        
        fork
            begin
                for(int i = 0; i < tv_in_rows.size(); i++ ) begin
                    tv_axis_in row;
                    row = tv_in_rows[i];

                    saxis_tvalid <= 1;
                    saxis_tdata  <= row.saxis_tdata;
                    saxis_tlast <= row.saxis_tlast;

                    do @(posedge clock); while(saxis_tready == 0);
                end
                saxis_tvalid <= 0;
            end
            begin
                for(int i = 0; i < tv_out_rows.size(); i++) begin
                    tv_mii_out row;
                    row = tv_out_rows[i];
                    
                    if( row.mii_d  != mii_d   ) $error("#%02d mii_d mismatch, expected: %016x, actual: %016x", i, row.mii_d, mii_d);
                    if( row.mii_en != mii_en   ) $error("#%02d mii_en mismatch, expected: %08b, actual: %08b",  i, row.mii_en, mii_en);
                    @(posedge clock);
                    #1;
                end
            end
        join
        
        repeat(10) @(posedge clock);
        $finish;
    end

endmodule
