`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    axis_if #(.DATA_WIDTH(4)) tb_maxis_if(.clock(clock), .aresetn(aresetn));
    axis_if #(.DATA_WIDTH(4)) tb_saxis_if(.clock(clock), .aresetn(aresetn));


    
    simple_fifo #(
        .DATA_BITS(32),
        .DEPTH_BITS(4)
    ) dut(
        .saxis_tdata (tb_maxis_if.tdata ),
        .saxis_tvalid(tb_maxis_if.tvalid),
        .saxis_tready(tb_maxis_if.tready),
        .maxis_tdata (tb_saxis_if.tdata ),
        .maxis_tvalid(tb_saxis_if.tvalid),
        .maxis_tready(tb_saxis_if.tready),
        .*
    );
    
    localparam NUMBER_OF_INPUTS = 1000;

    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        logic [31:0] tdata;
    } tv_axis;

    module stimuli (
        input logic clock,
        output logic aresetn,
        axis_if.master tb_maxis,
        axis_if.slave tb_saxis
    );
        initial begin
            tv_axis axis_in[NUMBER_OF_INPUTS];

            for(int i = 0; i < NUMBER_OF_INPUTS; i++) begin
                axis_in[i].tdata = $urandom();
                //$info("data #%02d: %08x", i, axis_in[i].tdata);
            end

            aresetn <= 0;
            tb_maxis.master_init;
            tb_saxis.slave_init;
            repeat(4) @(posedge clock);
            aresetn <= 1;
            @(posedge clock);
            
            fork
                begin
                    for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                        tb_maxis.master_send_data(axis_in[i].tdata);
                        repeat($urandom_range(0, 2)) @(posedge clock);
                    end
                end
                begin
                    for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                        tv_axis row;
                        bit [63:0] tdata;
                        
                        row = axis_in[i];
                        tb_saxis.slave_receive_data(tdata, 32'h7fffffff);
                        if( row.tdata != tdata ) $error("#%02d tdata mismatch, expected: %08x, actual: %08x", i, row.tdata, tdata);
                    end
                end
            join
            
            $finish;
        end
    endmodule

    stimuli stimuli_inst (
        .tb_maxis(tb_maxis_if),
        .tb_saxis(tb_saxis_if),
        .*
    );
endmodule
