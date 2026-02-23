`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    logic [63:0] xgmii_d;
    logic [7:0] xgmii_c;

    logic  [63:0] saxis_tdata;
    logic         saxis_tvalid;
    logic         saxis_tready;
    logic  [7:0]  saxis_tkeep;
    logic         saxis_tuser;
    logic         saxis_tlast;

    axis_to_xgmii dut(
        .*
    );
    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        logic [63:0] saxis_tdata;
        logic [7:0]  saxis_tkeep;
        logic        saxis_tuser;
        logic        saxis_tlast;
    } tv_axis_in;

    typedef struct {
        logic [63:0] xgmii_d;
        logic [7:0]  xgmii_c;
    } tv_xgmii_out;
    
    tv_axis_in   tv_in_rows[];
    tv_xgmii_out tv_out_rows[];
    

    initial begin
        tv_out_rows = '{
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111 },
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111 },

            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0e0d_0c0b_0a09_0807, xgmii_c: 8'b0000_0000 },
            '{xgmii_d: 64'h0707_0707_0707_fd0f, xgmii_c: 8'b1111_1110 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'hfd0d_0c0b_0a09_0807, xgmii_c: 8'b1000_0000 },
            
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0707_0707_0707_07fd, xgmii_c: 8'b1111_1111 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0707_0707_07fd_0807, xgmii_c: 8'b1111_1100 },
            
            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0707_0707_0707_fd07, xgmii_c: 8'b1111_1110 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0707_0707_0707_07fe, xgmii_c: 8'b1111_1111 },
            
            '{xgmii_d: 64'h0605_0403_0201_00fb, xgmii_c: 8'b0000_0001 },
            '{xgmii_d: 64'h0e0d_0c0b_0a09_0807, xgmii_c: 8'b0000_0000 },
            '{xgmii_d: 64'h0707_0707_0707_fe0f, xgmii_c: 8'b1111_1110 },

            '{xgmii_d: 64'h0707_0707_0707_0707, xgmii_c: 8'b1111_1111 }
        };

        tv_in_rows = '{
            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 1},
            
            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 0},
            '{saxis_tdata: 64'h0f0e_0d0c_0b0a_0908, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 1},

            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 0},
            '{saxis_tdata: 64'hbaad_0d0c_0b0a_0908, saxis_tkeep: 8'b0011_1111, saxis_tuser: 0, saxis_tlast: 1},
            
            '{saxis_tdata: 64'hba06_0504_0302_0100, saxis_tkeep: 8'b0111_1111, saxis_tuser: 0, saxis_tlast: 1},
            
            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 0},
            '{saxis_tdata: 64'hbaad_dead_beef_ca08, saxis_tkeep: 8'b0000_0001, saxis_tuser: 0, saxis_tlast: 1},
            
            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 1},
            
            '{saxis_tdata: 64'hba06_0504_0302_0100, saxis_tkeep: 8'b0111_1111, saxis_tuser: 1, saxis_tlast: 1},

            '{saxis_tdata: 64'h0706_0504_0302_0100, saxis_tkeep: 8'b1111_1111, saxis_tuser: 0, saxis_tlast: 0},
            '{saxis_tdata: 64'h0f0e_0d0c_0b0a_0908, saxis_tkeep: 8'b1111_1111, saxis_tuser: 1, saxis_tlast: 1}
        };

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
                for(int i = 0; i < tv_in_rows.size(); i++ ) begin
                    tv_axis_in row;
                    row = tv_in_rows[i];

                    saxis_tvalid <= 1;
                    saxis_tdata  <= row.saxis_tdata;
                    saxis_tkeep <= row.saxis_tkeep;
                    saxis_tlast <= row.saxis_tlast;
                    saxis_tuser <= row.saxis_tuser;

                    do @(posedge clock); while(saxis_tready == 0);
                end
                saxis_tvalid <= 0;
            end
            begin
                for(int i = 0; i < tv_out_rows.size(); i++) begin
                    tv_xgmii_out row;
                    row = tv_out_rows[i];
                    
                    if( row.xgmii_d != xgmii_d  ) $error("#%02d xgmii_d mismatch, expected: %016x, actual: %016x", i, row.xgmii_d, xgmii_d);
                    if( row.xgmii_c != xgmii_c  ) $error("#%02d xgmii_c mismatch, expected: %08b, actual: %08b", i, row.xgmii_c, xgmii_c);
                    @(posedge clock);
                    #1;
                end
            end
        join
        
        repeat(10) @(posedge clock);
        $finish;
    end

endmodule
