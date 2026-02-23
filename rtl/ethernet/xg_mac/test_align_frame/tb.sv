`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    axis_if #(.DATA_WIDTH(8)) tb_maxis_if(.clock(clock), .aresetn(aresetn));
    axis_if #(.DATA_WIDTH(8)) tb_saxis_if(.clock(clock), .aresetn(aresetn));

    localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

    align_frame dut(
        .saxis_tdata (tb_maxis_if.tdata ),
        .saxis_tvalid(tb_maxis_if.tvalid),
        .saxis_tready(tb_maxis_if.tready),
        .saxis_tkeep (tb_maxis_if.tkeep ),
        .saxis_tuser (tb_maxis_if.tuser ),
        .saxis_tlast (tb_maxis_if.tlast ),
        .maxis_tdata (tb_saxis_if.tdata ),
        .maxis_tvalid(tb_saxis_if.tvalid),
        .maxis_tready(tb_saxis_if.tready),
        .maxis_tkeep (tb_saxis_if.tkeep ),
        .maxis_tuser (tb_saxis_if.tuser ),
        .maxis_tlast (tb_saxis_if.tlast ),
        .*
    );
    
    localparam NUMBER_OF_INPUTS = 1000;
    localparam [7:0] SFD      = 8'hab;
    localparam [7:0] PREAMBLE = 8'haa;

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

    module stimuli (
        input logic clock,
        output logic aresetn,
        axis_if.master tb_maxis,
        axis_if.slave tb_saxis
    );
        initial begin
            tv_axis axis_in[$];
            tv_axis axis_out[$];
            bit     tusers[];
            
            // Generate test inputs
            for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                int length;
                int preamble_length;
                bit [7:0] data [MAX_BYTES+8-1:0];

                preamble_length = $urandom_range(1, 8);
                length = $urandom_range(9 - preamble_length, MAX_BYTES);
                for(int preamble_index = 0; preamble_index < preamble_length - 1; preamble_index++ ) begin
                    data[preamble_index] = PREAMBLE;
                end
                data[preamble_length-1] = SFD;

                for(int data_index = preamble_length; data_index < preamble_length+length; data_index += 4) begin
                    int value;
                    value = $urandom();
                    data[data_index + 0] = value[8*0 +: 8];
                    data[data_index + 1] = value[8*1 +: 8];
                    data[data_index + 2] = value[8*2 +: 8];
                    data[data_index + 3] = value[8*3 +: 8];
                end

                // input data 
                for(int data_index = 0; data_index < preamble_length+length; data_index += 8) begin
                    tv_axis row;
                    bit [8:0] tkeep;
                    int remaining;
                    remaining = preamble_length + length - data_index;
                    tkeep = (9'b1 << remaining) - 1;
                    
                    for(int byte_index = 0; byte_index < 8; byte_index++) begin
                        row.tdata[8*byte_index +: 8] = data[data_index+byte_index];
                    end
                    row.tkeep = tkeep[7:0];
                    row.tlast = remaining <= 8;
                    row.tuser = row.tlast;
                    row.count = remaining > 8 ? 8 : remaining;
                    axis_in.push_back(row);

                    $info("input #%04d: count=%d, tdata=%016x, tkeep=%08b, tlast=%d", i, row.count, row.tdata, row.tkeep, row.tlast);
                end
                // expected output
                for(int data_index = preamble_length; data_index < preamble_length+length; data_index += 8) begin
                    tv_axis row;
                    bit [8:0] tkeep;
                    int remaining;
                    remaining = preamble_length + length - data_index;
                    tkeep = (9'b1 << remaining) - 1;
                    
                    for(int byte_index = 0; byte_index < 8; byte_index++) begin
                        row.tdata[8*byte_index +: 8] = data[data_index+byte_index];
                    end
                    row.tkeep = tkeep[7:0];
                    row.tlast = remaining <= 8;
                    row.tuser = row.tlast;
                    row.count = remaining > 8 ? 8 : remaining;
                    axis_out.push_back(row);

                    $info("output #%04d: count=%d, tdata=%016x, tkeep=%08b, tlast=%d", i, row.count, row.tdata, row.tkeep, row.tlast);
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
                        
                        while(axis_in.size() > 0) begin
                            while(axis_in.size() > 0) begin
                                tv_axis row;
                                
                                row = axis_in.pop_front();
                                tb_maxis.master_send(row.tdata, row.tkeep, row.tlast, row.tuser);
                                if( row.tlast ) break;
                            end
                            repeat($urandom_range(0, 2)) @(posedge clock);
                        end
                    end
                    begin
                        for(int i = 0; axis_out.size() > 0; i++ ) begin
                            while(axis_out.size() > 0) begin
                                tv_axis row;
                                bit [63: 0] tdata_mask;
                                bit [63: 0] tdata;
                                bit [ 7: 0] tkeep;
                                bit         tuser;
                                bit         tlast;

                                row = axis_out.pop_front();

                                tb_saxis.slave_receive(tdata, tkeep, tlast, tuser, 32'h7fffffff);
                                tdata_mask = {{8 {tkeep[7]}}, {8 {tkeep[6]}}, {8 {tkeep[5]}}, {8 {tkeep[4]}}, {8 {tkeep[3]}}, {8 {tkeep[2]}}, {8 {tkeep[1]}}, {8 {tkeep[0]}}};
                                tdata     &= tdata_mask;
                                row.tdata &= tdata_mask;

                                if( row.tdata != tdata ) $error("#%02d tdata mismatch, expected=%016h, actual=%016h", i, row.tdata, tdata);
                                if( row.tkeep != tkeep ) $error("#%02d tkeep mismatch, expected=%08b , actual=%08b" , i, row.tkeep, tkeep);
                                if( row.tlast != tlast ) $error("#%02d tlast mismatch, expected=%d, actual=%d"      , i, row.tlast, tlast);
                                if( row.tuser != tuser ) $error("#%02d tuser mismatch, expected=%d, actual=%d"      , i, row.tuser, tuser);
                                if( row.tlast ) begin
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
