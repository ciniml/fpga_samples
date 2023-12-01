`timescale 1ns/1ps

module tb();
    logic clock;
    logic aresetn;

    axis_if #(.DATA_WIDTH(1)) tb_maxis_if(.clock(clock), .aresetn(aresetn));
    axis_if #(.DATA_WIDTH(1)) tb_saxis_if(.clock(clock), .aresetn(aresetn));

    localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

    logic [7:0] mii_d;
    logic       mii_en;
    logic       mii_er;

    mii_mac_tx dut_tx(
        .saxis_tdata (tb_maxis_if.tdata ),
        .saxis_tvalid(tb_maxis_if.tvalid),
        .saxis_tready(tb_maxis_if.tready),
        .saxis_tuser (tb_maxis_if.tuser ),
        .saxis_tlast (tb_maxis_if.tlast ),
        .*
    );

    mii_mac_rx dut_rx(
        .maxis_tdata (tb_saxis_if.tdata ),
        .maxis_tvalid(tb_saxis_if.tvalid),
        .maxis_tuser (tb_saxis_if.tuser ),
        .maxis_tlast (tb_saxis_if.tlast ),
        .mii_dv(mii_en),
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
        bit [7:0] tdata;
        bit       tlast;
        bit       tuser;
    } tv_axis;

    localparam int MIN_BYTES = 60;
    localparam int MAX_BYTES = 1500;

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
            int data_counter;
            
            data_counter = 0;
            // Generate test inputs
            for(int i = 0; i < NUMBER_OF_INPUTS; i++ ) begin
                int length;
                bit [7:0] data [MAX_BYTES+8-1:0];

                length = $urandom_range(MIN_BYTES, MAX_BYTES);
                for(int data_index = 0; data_index < length; data_index ++) begin
                    int value;
                    value = $urandom();
                    data[data_index] = data_counter; //value[8*0 +: 8];
                    data_counter += 1;
                end

                // input and output must be identical.
                for(int data_index = 0; data_index < length; data_index++ ) begin
                    tv_axis row;
                    int remaining;
                    remaining = length - data_index;
                    row.tdata= data[data_index];
                    row.tlast = remaining == 1;
                    row.tuser = !row.tlast;
                    axis_in.push_back(row);
                    axis_out.push_back(row);
                    //$display("input #%04d: tdata=%02x, tlast=%d", i, row.tdata, row.tlast);
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
                                tb_maxis.master_send(row.tdata, 1'b1, row.tlast, row.tuser);
                                if( row.tlast ) break;
                            end
                            repeat($urandom_range(0, 2)) @(posedge clock);
                        end
                    end
                    begin
                        for(int i = 0; axis_out.size() > 0; i++ ) begin
                            while(axis_out.size() > 0) begin
                                tv_axis row;
                                bit [7: 0] tdata;
                                bit        tkeep;
                                bit        tuser;
                                bit        tlast;

                                row = axis_out.pop_front();

                                tb_saxis.slave_receive(tdata, tkeep, tlast, tuser, 0);

                                if( row.tdata != tdata )              $error("#%02d tdata mismatch, expected=%02h, actual=%02h", i, row.tdata, tdata);
                                if( row.tlast != tlast )              $error("#%02d tlast mismatch, expected=%d, actual=%d"    , i, row.tlast, tlast);
                                if( row.tlast && row.tuser != tuser ) $error("#%02d tuser mismatch, expected=%d, actual=%d"    , i, row.tuser, tuser);
                                if( row.tlast ) begin
                                    break;
                                end
                            end
                        end
                    end
                join
                begin
                    repeat(NUMBER_OF_INPUTS*MAX_BYTES*20) @(posedge clock);
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
