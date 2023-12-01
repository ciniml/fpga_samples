`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    logic [3:0] rmii_d;
    logic       rmii_en;
    logic       rmii_er;

    logic  [7:0] saxis_tdata;
    logic        saxis_tvalid;
    logic        saxis_tready;
    logic        saxis_tlast;

    axis_to_rmii dut(
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
        logic [7:0] rmii_d;
        logic       rmii_en;
    } tv_rmii_out;
    
    tv_axis_in tv_in_rows[];
    tv_rmii_out tv_out_rows[];
    

    initial begin
        tv_out_rows = '{
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'hd, rmii_en: 1 },
            '{rmii_d: 4'hb, rmii_en: 1 },
            '{rmii_d: 4'ha, rmii_en: 1 },
            '{rmii_d: 4'hd, rmii_en: 1 },
            '{rmii_d: 4'hc, rmii_en: 1 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'h5, rmii_en: 1 },
            '{rmii_d: 4'hd, rmii_en: 1 },
            '{rmii_d: 4'hb, rmii_en: 1 },
            '{rmii_d: 4'ha, rmii_en: 1 },
            '{rmii_d: 4'hd, rmii_en: 1 },
            '{rmii_d: 4'hc, rmii_en: 1 },
            '{rmii_d: 4'hf, rmii_en: 1 },
            '{rmii_d: 4'he, rmii_en: 1 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 },
            '{rmii_d: 4'h0, rmii_en: 0 }
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
                    tv_rmii_out row;
                    row = tv_out_rows[i];
                    for(int bit_index = 0; bit_index < 2; bit_index++) begin
                        bit [1:0] expected_d;
                        expected_d = row.rmii_d >> (2*bit_index);
                        if( expected_d  != rmii_d   )  $error("#%02d.%01d rmii_d mismatch, expected: %02b, actual: %02b", i, bit_index, expected_d, rmii_d);
                        if( row.rmii_en != rmii_en   ) $error("#%02d.%01d rmii_en mismatch, expected: %08b, actual: %08b",  i, bit_index, row.rmii_en, rmii_en);
                        @(posedge clock);
                        #1;
                    end
                end
            end
        join
        
        repeat(10) @(posedge clock);
        $finish;
    end

endmodule
