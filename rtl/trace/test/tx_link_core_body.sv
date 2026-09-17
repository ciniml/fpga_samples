// easycdr_trace_tx_core test body: symbol stream -> displayport_decoder_8b10b.
//   - every FRAME_LEN-th symbol is a K28.5 comma, o_ready is low only there
//   - offered bytes come out in order (data and K flag) with no code errors
//   - idle slots carry K28.3
`timescale 1ns/1ps
module tx_link_core_body #(
    parameter int FRAME_LEN = 16,
    parameter bit RUN       = 0
) ();
    logic clk = 0, rstn = 0;
    always #5 clk = ~clk;

    logic       i_valid = 0, i_is_k = 0, o_ready;
    logic [7:0] i_data = 0;
    logic [9:0] sym;
    easycdr_trace_tx_core #(.FRAME_LEN(FRAME_LEN)) dut (
        .clk(clk), .rstn(rstn), .i_valid(i_valid), .i_is_k(i_is_k), .i_data(i_data),
        .o_ready(o_ready), .o_symbol(sym));

    logic       d_valid, d_is_k, d_err;
    logic [7:0] d_data;
    displayport_decoder_8b10b dec (
        .i_clk(clk), .i_rstn(rstn), .i_valid(1'b1), .i_symbol(sym),
        .o_valid(d_valid), .o_data(d_data), .o_is_k(d_is_k), .o_code_err(d_err));

    // scoreboard: bytes offered when o_ready (consumed) must come out in order
    logic [8:0] sent[$];
    int commas = 0, idles = 0, words = 0, errors = 0, ready_low = 0, ready_low_ok = 0;
    always @(posedge clk) if (rstn) begin
        if (i_valid && o_ready) sent.push_back({i_is_k, i_data});
        if (!o_ready) ready_low++;
        if (d_valid) begin
            words++;
            // word 0 is the encoder's reset-state symbol; the decoder's disparity
            // tracking settles on it, so a code error is only counted from word 2
            if (d_err) begin if (words >= 2) errors++; $display("code error at word %0d sym %03x (t=%0t)", words, sym, $time); end
            else if (d_is_k && d_data == 8'hbc) commas++;
            else if (d_is_k && d_data == 8'h7c) idles++;
            else begin
                if (sent.size() == 0) begin $display("FAIL: unexpected %0d %02x", d_is_k, d_data); errors++; end
                else if (sent[0] != {d_is_k, d_data}) begin
                    $display("FAIL: order: expected %03x got %03x", sent[0], {d_is_k, d_data}); errors++; sent.pop_front();
                end else sent.pop_front();
            end
        end
    end

    initial if (RUN) begin
        repeat (4) @(posedge clk); rstn = 1;
        repeat (40) @(posedge clk);                    // idle: commas + K28.3 only
        // 100 bytes offered back to back, incl. some K codes
        for (int n = 0; n < 100; n++) begin
            @(negedge clk); i_valid = 1; i_is_k = (n % 10 == 3); i_data = i_is_k ? 8'h3c : n[7:0];
            @(posedge clk); while (!o_ready) @(posedge clk);
        end
        @(negedge clk); i_valid = 0;
        repeat (60) @(posedge clk);
        // 1 word in 3, to check idle interleaving
        for (int n = 0; n < 30; n++) begin
            @(negedge clk); i_valid = 1; i_is_k = 0; i_data = 8'ha0 + n[7:0];
            @(posedge clk); while (!o_ready) @(posedge clk);
            @(negedge clk); i_valid = 0; repeat (2) @(posedge clk);
        end
        repeat (40) @(posedge clk);
        $display("words %0d commas %0d idles %0d errors %0d pending %0d ready_low %0d", words, commas, idles, errors, sent.size(), ready_low);
        if (errors != 0) $fatal(1, "code/order errors");
        if (sent.size() != 0) $fatal(1, "bytes lost");
        if (commas < words / FRAME_LEN - 2 || commas > words / FRAME_LEN + 2) $fatal(1, "comma rate");
        if (ready_low < commas - 2 || ready_low > commas + 2) $fatal(1, "o_ready low != comma slots");
        if (idles == 0) $fatal(1, "no idle filler seen");
        $display("PASS (FRAME_LEN=%0d)", FRAME_LEN);
        $finish;
    end
endmodule
