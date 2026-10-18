// Two Eth100Phy instances cross-connected through eth100_chan line models,
// each on its own 125 MHz clock (+-ppm). After the link comes up (forced
// 100BASE-TX or auto-negotiation), both sides send NFRAMES random frames
// (preamble + SFD + payload as MII nibbles) and the receiver's nibble
// stream must equal the transmitted one exactly, with no rx_er.
`timescale 1ns/1ps
module eth100_link_body #(
    parameter bit  FORCE   = 1,      // 1: i_force_100 (no FLP), 0: auto-negotiation
    parameter bit  ONE_AN  = 0,      // with FORCE=0: only B negotiates, A is forced (parallel detection at B)
    parameter real PPM_A   = 0.0,
    parameter real PPM_B   = 0.0,
    parameter real TAU     = 1.6,
    parameter real ATT     = 1.0,
    parameter real NOISE   = 0.0,
    parameter real OFFSET  = 0.0,
    parameter real TH      = 0.5,
    parameter int  NFRAMES = 20,
    parameter int  TDIV    = 16,     // FLP timing divider
    parameter int  AN_DIV  = 1000,   // auto-negotiation timer divider
    parameter int  HOLD    = 131072,
    parameter bit  RUN     = 0
) ();
    logic clk_a = 0, clk_b = 0, rst = 1;
    always #(4.0 * (1.0 + PPM_A / 1e6)) clk_a = ~clk_a;
    always #(4.0 * (1.0 + PPM_B / 1e6)) clk_b = ~clk_b;

    // ---- line ----
    logic       a_tx_p, a_tx_n, b_tx_p, b_tx_n;
    logic [3:0] a_sa, a_sb, b_sa, b_sb;
    eth100_chan #(.TAU(TAU), .ATT(ATT), .NOISE(NOISE), .OFFSET(OFFSET), .TH_A(TH), .TH_B(TH))
        ch_ab (.tx_p(a_tx_p), .tx_n(a_tx_n), .rx_clk(clk_b), .a(b_sa), .b(b_sb));
    eth100_chan #(.TAU(TAU), .ATT(ATT), .NOISE(NOISE), .OFFSET(-OFFSET), .TH_A(TH), .TH_B(TH))
        ch_ba (.tx_p(b_tx_p), .tx_n(b_tx_n), .rx_clk(clk_a), .a(a_sa), .b(a_sb));

    // ---- PHYs + MII traffic ----
    logic a_link, b_link;
    int   a_rx_frames, b_rx_frames, a_rx_bad, b_rx_bad;
    logic a_send = 0, b_send = 0;
    int   a_sent, b_sent;
    side #(.TDIV(TDIV), .AN_DIV(AN_DIV), .HOLD(HOLD), .SEED(1))
        sa (.clk(clk_a), .rst(rst), .force_100(FORCE || ONE_AN), .samp_a(a_sa), .samp_b(a_sb),
            .tx_p(a_tx_p), .tx_n(a_tx_n), .link(a_link), .send(a_send), .sent(a_sent),
            .rx_frames(a_rx_frames), .rx_bad(a_rx_bad));
    side #(.TDIV(TDIV), .AN_DIV(AN_DIV), .HOLD(HOLD), .SEED(2))
        sb (.clk(clk_b), .rst(rst), .force_100(FORCE), .samp_a(b_sa), .samp_b(b_sb),
            .tx_p(b_tx_p), .tx_n(b_tx_n), .link(b_link), .send(b_send), .sent(b_sent),
            .rx_frames(b_rx_frames), .rx_bad(b_rx_bad));

    int errors = 0;
    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end else $display("ok: %s", what);
    endtask

    initial if (RUN) begin
        realtime t_link;
        repeat (4) @(posedge clk_a);
        rst = 0;
        // link up on both sides (timeout: 60 ms simulated)
        fork
            begin wait (a_link && b_link); end
            begin #60ms; end
        join_any
        disable fork;
        t_link = $realtime;
        $display("[%0t] link a=%0d b=%0d  an_state a=%0d b=%0d  fd a=%0d b=%0d  pd a=%0d b=%0d  lp a=%04h b=%04h",
                 $time, a_link, b_link, sa.an_state, sb.an_state, sa.full_duplex, sb.full_duplex,
                 sa.parallel, sb.parallel, sa.lp_page, sb.lp_page);
        check("link A", a_link);
        check("link B", b_link);
        if (!FORCE && !ONE_AN) begin
            check("A full duplex by negotiation", sa.full_duplex && !sa.parallel);
            check("B full duplex by negotiation", sb.full_duplex && !sb.parallel);
            check("A saw B's page 0x4181 (Ack)", sa.lp_page == 16'h0181 || sa.lp_page == 16'h4181);
        end
        if (ONE_AN) check("B parallel detection, half duplex", sb.parallel && !sb.full_duplex);
        if (a_link && b_link) begin
            repeat (2000) @(posedge clk_a);
            // traffic both ways
            sa.queue_frames(NFRAMES);
            sb.queue_frames(NFRAMES);
            a_send = 1; b_send = 1;
            fork
                begin wait (a_rx_frames + a_rx_bad >= NFRAMES && b_rx_frames + b_rx_bad >= NFRAMES); end
                begin #(NFRAMES * 40us); end
            join_any
            disable fork;
            repeat (100) @(posedge clk_a);
            $display("A->B: sent %0d, B good %0d bad %0d | B->A: sent %0d, A good %0d bad %0d | cdr slips a=%0d b=%0d",
                     a_sent, b_rx_frames, b_rx_bad, b_sent, a_rx_frames, a_rx_bad, sa.slips, sb.slips);
            check("A->B all frames intact", b_rx_frames == NFRAMES && b_rx_bad == 0);
            check("B->A all frames intact", a_rx_frames == NFRAMES && a_rx_bad == 0);
            check("links stayed up", a_link && b_link && sa.drops == 0 && sb.drops == 0);
        end
        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end
endmodule

// One PHY with an MII frame generator and a receive checker. The checker
// compares against the *peer's* transmit list (bound hierarchically through
// peer below), so each side holds the frames it sent until the peer has
// checked them.
module side #(
    parameter int TDIV   = 16,
    parameter int AN_DIV = 1000,
    parameter int HOLD   = 131072,
    parameter int SEED   = 1
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       force_100,
    input  logic [3:0] samp_a,
    input  logic [3:0] samp_b,
    output logic       tx_p,
    output logic       tx_n,
    output logic       link,
    input  logic       send,
    output int         sent,
    output int         rx_frames,
    output int         rx_bad
);
    logic        tx_req, tx_en = 0, rx_valid, rx_er, rx_sof, rx_eof, rx_dv;
    logic [3:0]  tx_data = 0, rx_data;
    logic        full_duplex, parallel, cdr_lock, scr_lock, flp_pulse;
    logic [2:0]  an_state;
    logic [15:0] lp_page;

    Eth100Phy #(.TDIV(TDIV), .AN_DIV(AN_DIV), .HOLD(HOLD)) phy (
        .i_clk(clk), .i_rst(rst),
        .i_samp_a(samp_a), .i_samp_b(samp_b), .o_tx_p(tx_p), .o_tx_n(tx_n), .o_pwm_a(), .o_pwm_b(),
        .i_th_a(10'd512), .i_th_b(10'd512), .i_force_100(force_100), .i_an_restart(1'b0), .i_cdr_freeze(1'b0),
        .o_tx_req(tx_req), .i_tx_en(tx_en), .i_tx_er(1'b0), .i_tx_data(tx_data),
        .o_rx_valid(rx_valid), .o_rx_data(rx_data), .o_rx_er(rx_er), .o_rx_sof(rx_sof), .o_rx_eof(rx_eof), .o_rx_dv(rx_dv),
        .o_link(link), .o_full_duplex(full_duplex), .o_parallel(parallel), .o_an_state(an_state), .o_lp_page(lp_page),
        .o_cdr_lock(cdr_lock), .o_scr_lock(scr_lock), .o_flp_pulse(flp_pulse));

    // ---- transmit: frames as nibble lists ----
    typedef logic [3:0] nib_q_t[$];
    nib_q_t txq_frames[$];   // frames still to be sent / checked by the peer
    int     txq_next = 0;    // index of the frame being / to be sent
    int     rng = SEED;
    function automatic int rnd(input int n);
        rng = rng * 1103515245 + 12345;
        return ((rng >>> 8) & 32'h7fffff) % n;
    endfunction
    task automatic queue_frames(input int n);
        for (int f = 0; f < n; f++) begin
            nib_q_t q;
            int len;
            q.delete();
            len = 46 + rnd(200);
            for (int i = 0; i < 15; i++) q.push_back(4'h5);
            q.push_back(4'hd);
            for (int i = 0; i < len; i++) begin
                logic [7:0] by = rnd(256);
                q.push_back(by[3:0]);
                q.push_back(by[7:4]);
            end
            txq_frames.push_back(q);
        end
    endtask

    int pos = 0, gap = 0;
    initial sent = 0;
    always @(posedge clk) if (tx_req) begin
        // the nibble on the inputs was taken this clock; set up the next one
        if (tx_en) begin
            if (pos < txq_frames[txq_next].size()) begin
                tx_data <= txq_frames[txq_next][pos];
                pos <= pos + 1;
            end else begin
                tx_en <= 0;
                txq_next <= txq_next + 1;
                sent <= sent + 1;
                gap <= 0;
            end
        end else begin
            gap <= gap + 1;
            if (send && gap >= 24 && txq_next < txq_frames.size()) begin
                tx_en   <= 1;
                tx_data <= txq_frames[txq_next][0];
                pos     <= 1;
            end
        end
    end

    // ---- receive checker (expected = peer's transmit list, in order) ----
    nib_q_t cur;
    bit     in_f = 0, had_er = 0;
    int     chk_idx = 0;
    initial begin rx_frames = 0; rx_bad = 0; end
    // the peer is resolved by the parent through bind-free hierarchical paths
    function automatic bit match(input nib_q_t got, input int idx);
        nib_q_t exp;
        if (SEED == 1) begin
            if (idx >= eth100_link_body.sb.txq_frames.size()) return 0;
            exp = eth100_link_body.sb.txq_frames[idx];
        end else begin
            if (idx >= eth100_link_body.sa.txq_frames.size()) return 0;
            exp = eth100_link_body.sa.txq_frames[idx];
        end
        if (got.size() != exp.size()) begin
            $display("  [%m] frame %0d: length %0d, expected %0d", idx, got.size(), exp.size());
            return 0;
        end
        foreach (got[i]) if (got[i] !== exp[i]) begin
            $display("  [%m] frame %0d: nibble %0d = %h, expected %h", idx, i, got[i], exp[i]);
            return 0;
        end
        return 1;
    endfunction
    always @(posedge clk) begin
        if (rx_valid) begin
            if (rx_sof) begin cur.delete(); in_f = 1; had_er = 0; end
            if (in_f) cur.push_back(rx_data);
            if (rx_er) had_er = 1;
        end
        if (rx_eof && in_f) begin
            in_f = 0;
            if (rx_er) had_er = 1;
            if (!had_er && match(cur, chk_idx)) rx_frames++;
            else begin
                rx_bad++;
                $display("  [%m] bad frame %0d (er=%0d, %0d nibbles)", chk_idx, had_er, cur.size());
            end
            chk_idx++;
        end
    end

    // ---- statistics ----
    int  slips = 0, drops = 0;
    logic link_q = 0;
    always @(posedge clk) begin
        if (phy.u_rx.o_cdr_slip) slips++;
        if (link_q && !link) drops++;
        link_q <= link;
    end
endmodule
