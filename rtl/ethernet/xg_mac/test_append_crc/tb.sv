`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    axis_if #(.DATA_WIDTH(8)) tb_maxis_if(.clock(clock), .aresetn(aresetn));
    axis_if #(.DATA_WIDTH(8)) tb_saxis_if(.clock(clock), .aresetn(aresetn));

    localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

    logic [63:0] crc_appended_tdata ;
    logic        crc_appended_tvalid;
    logic        crc_appended_tready;
    logic [7:0]  crc_appended_tkeep ;
    logic        crc_appended_tuser ;
    logic        crc_appended_tlast ;
    logic [31:0] crc;

    append_crc dut_append(
        .saxis_tdata (tb_maxis_if.tdata ),
        .saxis_tvalid(tb_maxis_if.tvalid),
        .saxis_tready(tb_maxis_if.tready),
        .saxis_tkeep (tb_maxis_if.tkeep ),
        .saxis_tuser (tb_maxis_if.tuser ),
        .saxis_tlast (tb_maxis_if.tlast ),
        .maxis_tdata (crc_appended_tdata ),
        .maxis_tvalid(crc_appended_tvalid),
        .maxis_tready(crc_appended_tready),
        .maxis_tkeep (crc_appended_tkeep ),
        .maxis_tuser (crc_appended_tuser ),
        .maxis_tlast (crc_appended_tlast ),
        .*
    );

    remove_crc dut_remove(
        .saxis_tdata (crc_appended_tdata ),
        .saxis_tvalid(crc_appended_tvalid),
        .saxis_tready(crc_appended_tready),
        .saxis_tkeep (crc_appended_tkeep ),
        .saxis_tuser (crc_appended_tuser ),
        .saxis_tlast (crc_appended_tlast ),
        .maxis_tdata (tb_saxis_if.tdata ),
        .maxis_tvalid(tb_saxis_if.tvalid),
        .maxis_tready(tb_saxis_if.tready),
        .maxis_tkeep (tb_saxis_if.tkeep ),
        .maxis_tuser (tb_saxis_if.tuser ),
        .maxis_tlast (tb_saxis_if.tlast ),
        .crc(crc),
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
        bit [63:0] tdata;
        bit [7:0]  tkeep;
        bit        tlast;
        bit        tuser;
        int        count;
    } tv_axis;

    localparam int MIN_BYTES = 1;
    localparam int MAX_BYTES = 24;

    function automatic bit [31:0] crc32(bit [31:0] data, int count, bit [31:0] remainder);
        bit [31:0] new_remainder;
        new_remainder = remainder ^ data;
        for(int byte_index = 0; byte_index < 4 && byte_index < count; byte_index++ ) begin
            for(int i = byte_index*8; i < byte_index*8+8; i++ ) begin
                new_remainder = {1'b0, new_remainder[31:1]} ^ (new_remainder[0] ? POLYNOMIAL : 0);
            end
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
            bit     tusers[];
            
            // Generate test inputs
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
                    axis_in_queue.push_back(row);
                    length -= row.count;

                    $info("input #%04d: count=%d, tdata=%016x, tkeep=%08b, tlast=%d", i, row.count, row.tdata, row.tkeep, row.tlast);
                end
            end
            axis_in = new[axis_in_queue.size()];
            for(int i = 0; i < axis_in.size(); i++ ) begin
                axis_in[i] = axis_in_queue.pop_front();
            end
            tusers = new[axis_in.size()];
            begin
                int tusers_index;
                tusers_index = 0;
                for(int i = 0; i < axis_in.size(); i++) begin
                    if( axis_in[i].tlast ) begin
                        tusers[tusers_index] = axis_in[i].tuser;
                        tusers_index++;
                    end 
                end
            end
            // Reset 
            aresetn <= 0;
            tb_maxis.master_init;
            tb_saxis.slave_init;
            repeat(4) @(posedge clock);
            aresetn <= 1;
            @(posedge clock);
            
            fork
                fork
                    begin
                        int row_index;
                        row_index = 0;
                        while(row_index < axis_in.size()) begin
                            while(1) begin
                                tv_axis row;
                                
                                row = axis_in[row_index];
                                tb_maxis.master_send(row.tdata, row.tkeep, row.tlast, row.tuser);
                                row_index++;
                                if( row.tlast ) break;
                            end
                            repeat($urandom_range(0, 2)) @(posedge clock);
                        end
                    end
                    begin
                        int tusers_index;
                        bit [31:0] remainder;

                        tusers_index = 0;
                        for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                            remainder = '1;
                            while(1) begin
                                bit [63: 0] tdata_mask;
                                bit [63: 0] tdata;
                                bit [ 7: 0] tkeep;
                                bit         tuser;
                                bit         tlast;
                                int count;

                                tb_saxis.slave_receive(tdata, tkeep, tlast, tuser, 32'h7fffffff);
                                tdata_mask = {{8 {tkeep[7]}}, {8 {tkeep[6]}}, {8 {tkeep[5]}}, {8 {tkeep[4]}}, {8 {tkeep[3]}}, {8 {tkeep[2]}}, {8 {tkeep[1]}}, {8 {tkeep[0]}}};
                                tdata = tdata & tdata_mask; 
                                count = tkeep[7] ? 8 :  tkeep[6] ? 7 :  tkeep[5] ? 6 :  tkeep[4] ? 5 :  tkeep[3] ? 4 :  tkeep[2] ? 3 :  tkeep[1] ? 2 :  tkeep[0] ? 1 : 0;

                                //$info("tdata = %016x, remainder = %08x", tdata, remainder);
                                remainder = crc32(tdata[31:0], count - 0, remainder);
                                remainder = crc32(tdata[63:32], count - 4, remainder);
                                //$info("remainder = %08x", remainder);
                                

                                if( tlast ) begin
                                    if( ~remainder != crc ) begin
                                        $error("#%02d CRC error, actual: %08x, expected: %08x", i, crc, ~remainder);
                                    end else begin
                                        $info("#%02d CRC matched.", i);
                                    end
                                    if( tusers[tusers_index] != tuser ) $error("#%02d TUSER mismatch, expected: %d, actual: %d", i, tusers[tusers_index], tuser);
                                    remainder = '1;
                                    tusers_index++;
                                    break;
                                end
                            end
                        end
                    end
                join
                begin
                    repeat(NUMBER_OF_INPUTS*20) @(posedge clock);
                    $error("timed out");
                end
            join_any
            disable fork;
            $finish;
        end
    endmodule

    stimuli stimuli_inst (
        .tb_maxis(tb_maxis_if),
        .tb_saxis(tb_saxis_if),
        .*
    );
endmodule
