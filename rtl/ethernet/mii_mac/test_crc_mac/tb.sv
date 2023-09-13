`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    axis_if #(.DATA_WIDTH(1)) tb_maxis_if(.clock(clock), .aresetn(aresetn));
    axis_if #(.DATA_WIDTH(1)) tb_saxis_if(.clock(clock), .aresetn(aresetn));

    logic  [31:0] crc_out;
    
    localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

    crc_mac dut(
        .saxis_tdata(tb_maxis_if.tdata),
        .saxis_tvalid(tb_maxis_if.tvalid),
        .saxis_tready(tb_maxis_if.tready),
        .saxis_tlast(tb_maxis_if.tlast),
        .saxis_tuser(tb_maxis_if.tuser),
        .maxis_tdata(tb_saxis_if.tdata),
        .maxis_tvalid(tb_saxis_if.tvalid),
        .maxis_tready(tb_saxis_if.tready),
        .maxis_tlast(tb_saxis_if.tlast),
        .maxis_tuser(tb_saxis_if.tuser),
        .*
    );
    
    initial begin
        clock = 0;
    end 
    always #(5) begin
        clock = ~clock;
    end
    
    typedef struct {
        bit [7:0] tdata;
        bit       tlast;
        bit       tuser;
    } tv_axis;

    localparam int NUMBER_OF_INPUTS = 100;
    localparam int MIN_BYTES = 1;
    localparam int MAX_BYTES = 24;

    function automatic bit [31:0] crc32(bit [7:0] data, bit [31:0] remainder);
        bit [31:0] new_remainder;
        new_remainder = remainder ^ data;
        for(int i = 0; i < 8; i++ ) begin
            new_remainder = {1'b0, new_remainder[31:1]} ^ (new_remainder[0] ? POLYNOMIAL : 0);
        end
        return new_remainder;
    endfunction
    
    module stimuli (
        input logic clock,
        output logic aresetn,
        axis_if.master tb_maxis,
        axis_if.slave tb_saxis
    );
        initial begin
            tv_axis axis_in_queue[$];
            tv_axis axis_in[];

            aresetn <= 0;
            tb_maxis.master_init;
            tb_saxis.slave_init;
            repeat(4) @(posedge clock);

            aresetn <= 1;
            @(posedge clock);
            #1;
            
            for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                int length;
                
                length = $urandom_range(MIN_BYTES, MAX_BYTES);

                for(; length > 0; length-- ) begin
                    tv_axis row;

                    row.tdata = $urandom();
                    row.tlast = length == 1;
                    row.tuser = row.tlast ? $urandom_range(0, 1) : 0;
                    axis_in_queue.push_back(row);

                    $info("input #%04d: tdata=%016x, tlast=%d", i, row.tdata, row.tlast);
                end
            end
            axis_in = new[axis_in_queue.size()];
            for(int i = 0; i < axis_in.size(); i++ ) begin
                axis_in[i] = axis_in_queue.pop_front();
            end

            fork
                begin
                    int row_index;
                    row_index = 0;
                    while(row_index < axis_in.size()) begin
                        while(1) begin
                            tv_axis row;
                            
                            row = axis_in[row_index];
                            tb_maxis.master_send(row.tdata, 1'b1, row.tlast, row.tuser);
                            row_index++;
                            if( row.tlast ) break;
                        end
                        repeat($urandom_range(0, 2)) @(posedge clock);
                    end
                end
                begin
                    int row_index;
                    bit [31:0] remainder;

                    row_index = 0;
                    for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                        remainder = '1;
                        while(1) begin
                            tv_axis row;
                            bit [7:0] tdata;
                            bit       tkeep;
                            bit       tuser;
                            bit       tlast;

                            row = axis_in[row_index++];
                            tdata = row.tdata;
                            //$info("tdata = %016x, remainder = %08x", tdata, remainder);
                            remainder = crc32(tdata, remainder);
                            //$info("remainder = %08x", remainder);
                            tb_saxis.slave_receive(tdata, tkeep, tlast, tuser, 32'h7fffffff);
                            if( row.tdata != tdata ) $error("#%02d tdata mismatch, expected=%016h, actual=%016h", i, row.tdata, tdata);
                            if( row.tlast != tlast ) $error("#%02d tlast mismatch, expected=%d, actual=%d"      , i, row.tlast, tlast);
                            //if( row.tuser != tuser ) $error("#%02d tuser mismatch, expected=%d, actual=%d"      , i, row.tuser, tuser);
                            if( row.tlast ) begin
                                if( ~remainder != crc_out ) $error("#%02d crc_out mismatch, expected: %08x, actual: %08x", i, ~remainder, crc_out);
                                if( ~remainder == crc_out ) $info("#%02d crc matched. expected: %08x", i, ~remainder);
                                remainder = '1;
                                break;
                            end
                        end
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
