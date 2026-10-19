// Bring-up logic for the transformerless 100BASE-TX PHY (pclk 125 MHz domain).
//
//  - TX: a 60-byte broadcast test frame (+ FCS) once per second (or on 'p'):
//        dst ff:ff:ff:ff:ff:ff, src 02:00:00:00:01:00 (locally administered),
//        EtherType 0x88B5 (IEEE local experimental), payload "eth100 #" + 32-bit
//        sequence number. On a PC: tcpdump -e -i <if> ether proto 0x88b5
//  - RX: MII nibbles -> bytes after the SFD -> CRC-32 check; counts good /
//        bad (FCS or rx_er) frames and keeps the first 14 bytes (MAC header)
//        and the length of the last good frame
//  - UART 115200: one status line every 0.5 s, single-letter commands
//
// Status line (all hex):
//   L<link> F<fd> P<pd> A<an_state> C<cdr_lock> S<scr_lock> lp<LP page> f<FLP pulses> s<slips/0.5s>
//   r<good> b<bad> t<sent> ta<th_a> tb<th_b> m<mode> h<dst> <src> <type> n<len>
//   mode bit0 = forced 100BASE-TX, bit1 = periodic send, bit2 = CDR frozen
// Commands: + / -  both thresholds up / down by 8   a / A, b / B  one threshold -/+ 4
//           f force 100BASE-TX (toggle)   r restart auto-negotiation   p send one frame
//           s periodic send (toggle)      z clear counters             x freeze CDR (toggle)
`default_nettype none
module eth100_test #(
    parameter int CLK_HZ = 125_000_000,
    parameter int BAUD   = 115200
) (
    input  wire        clk,
    input  wire        rst,

    // MII side of Eth100Phy
    input  wire        tx_req,
    output logic       tx_en,
    output logic [3:0] tx_data,
    input  wire        rx_valid,
    input  wire  [3:0] rx_data,
    input  wire        rx_er,
    input  wire        rx_sof,
    input  wire        rx_eof,

    // PHY status / control
    input  wire        link,
    input  wire        full_duplex,
    input  wire        parallel,
    input  wire  [2:0] an_state,
    input  wire [15:0] lp_page,
    input  wire        cdr_lock,
    input  wire        scr_lock,
    input  wire        flp_pulse,
    input  wire        cdr_slip,
    output logic [9:0] th_a,
    output logic [9:0] th_b,
    output logic       force_100,
    output logic       an_restart,
    output logic       cdr_freeze,

    output logic       led_rx,       // toggles on every good frame
    output wire        uart_txd,
    input  wire        uart_rxd
);
    localparam logic [9:0] TH_INIT = 10'd900;   // ~ +0.39 V with the README §3.2 network

    function automatic logic [31:0] crc_byte(input logic [31:0] c, input logic [7:0] d);
        logic [31:0] r;
        r = c;
        for (int i = 0; i < 8; i++) r = (r[0] ^ d[i]) ? ((r >> 1) ^ 32'hEDB88320) : (r >> 1);
        return r;
    endfunction

    // ------------------------------------------------------------------
    // timers
    // ------------------------------------------------------------------
    logic [27:0] tick_cnt;
    logic        tick_half;              // 0.5 s
    logic        tick_sec;
    logic        half_phase;
    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt <= '0; tick_half <= 1'b0; tick_sec <= 1'b0; half_phase <= 1'b0;
        end else begin
            tick_half <= 1'b0; tick_sec <= 1'b0;
            if (tick_cnt == 28'(CLK_HZ / 2 - 1)) begin
                tick_cnt   <= '0;
                tick_half  <= 1'b1;
                half_phase <= ~half_phase;
                tick_sec   <= half_phase;
            end else tick_cnt <= tick_cnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // UART RX commands
    // ------------------------------------------------------------------
    logic       c_valid;
    logic [7:0] c_data;
    uart_rx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(CLK_HZ / BAUD)) u_uart_rx(
        .clock(clk), .reset(rst), .data_valid(c_valid), .data_ready(1'b1), .data_bits(c_data),
        .rx(uart_rxd), .overrun());

    logic send_periodic, send_one, clear;
    always_ff @(posedge clk) begin
        if (rst) begin
            th_a <= TH_INIT; th_b <= TH_INIT; force_100 <= 1'b0; an_restart <= 1'b0;
            cdr_freeze <= 1'b0; send_periodic <= 1'b1; send_one <= 1'b0; clear <= 1'b0;
        end else begin
            an_restart <= 1'b0; send_one <= 1'b0; clear <= 1'b0;
            if (c_valid) begin
                case (c_data)
                    "+": begin th_a <= th_a + 10'd8; th_b <= th_b + 10'd8; end
                    "-": begin th_a <= th_a - 10'd8; th_b <= th_b - 10'd8; end
                    "a": th_a <= th_a - 10'd4;
                    "A": th_a <= th_a + 10'd4;
                    "b": th_b <= th_b - 10'd4;
                    "B": th_b <= th_b + 10'd4;
                    "f": force_100 <= ~force_100;
                    "r": an_restart <= 1'b1;
                    "p": send_one <= 1'b1;
                    "s": send_periodic <= ~send_periodic;
                    "z": clear <= 1'b1;
                    "x": cdr_freeze <= ~cdr_freeze;
                    default: ;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // TX frame generator: bytes 0..7 preamble + SFD, 8..67 frame, 68..71 FCS
    // ------------------------------------------------------------------
    logic        tx_go;          // a frame is waiting
    logic        tx_active;
    logic [6:0]  tx_b;           // current byte index
    logic        tx_h;           // current nibble (0 = low)
    logic [31:0] tx_crc;
    logic [31:0] tx_seq;
    logic [15:0] tx_count;

    function automatic logic [7:0] frame_byte(input logic [6:0] b, input logic [31:0] seq, input logic [31:0] fcs);
        logic [7:0] v;
        v = 8'h00;
        if (b < 7)        v = 8'h55;
        else if (b == 7)  v = 8'hd5;
        else if (b < 14)  v = 8'hff;                           // dst
        else if (b == 14) v = 8'h02;                           // src 02:00:00:00:01:00
        else if (b == 18) v = 8'h01;
        else if (b == 20) v = 8'h88;                           // EtherType 0x88B5
        else if (b == 21) v = 8'hb5;
        else if (b >= 22 && b < 30) begin                      // "eth100 #"
            case (b - 7'd22)
                7'd0: v = "e"; 7'd1: v = "t"; 7'd2: v = "h"; 7'd3: v = "1";
                7'd4: v = "0"; 7'd5: v = "0"; 7'd6: v = " "; default: v = "#";
            endcase
        end
        else if (b >= 30 && b < 34) v = seq[8 * (33 - b) +: 8];  // sequence, big endian
        else if (b >= 68)           v = fcs[8 * (b - 68) +: 8];  // FCS, LSB first
        return v;
    endfunction

    logic [31:0] tx_crc_n;
    logic [6:0]  nb_b;
    logic        nb_h;
    logic [7:0]  nb_byte;
    always_comb begin
        // CRC after the byte being finished (only bytes 8..67 are covered)
        tx_crc_n = tx_crc;
        if (tx_h && tx_b >= 8 && tx_b < 68) tx_crc_n = crc_byte(tx_crc, frame_byte(tx_b, tx_seq, ~tx_crc));
        nb_b    = tx_h ? tx_b + 7'd1 : tx_b;
        nb_h    = ~tx_h;
        nb_byte = frame_byte(nb_b, tx_seq, ~tx_crc_n);
    end

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            tx_count <= '0;
        end
        if (rst) begin
            tx_go <= 1'b0; tx_active <= 1'b0; tx_en <= 1'b0; tx_data <= 4'h0;
            tx_b <= '0; tx_h <= 1'b0; tx_crc <= '1; tx_seq <= '0;
        end else begin
            if ((tick_sec && send_periodic) || send_one) tx_go <= 1'b1;
            if (tx_req) begin
                // the nibble on tx_en/tx_data was taken on this clock: set up the next one
                if (tx_active) begin
                    if (tx_h && tx_b == 7'd71) begin
                        tx_active <= 1'b0;
                        tx_en     <= 1'b0;
                        tx_count  <= tx_count + 1'b1;
                        tx_seq    <= tx_seq + 1'b1;
                    end else begin
                        tx_b    <= nb_b;
                        tx_h    <= nb_h;
                        tx_crc  <= tx_crc_n;
                        tx_data <= nb_h ? nb_byte[7:4] : nb_byte[3:0];
                    end
                end else if (tx_go && link) begin
                    tx_go     <= 1'b0;
                    tx_active <= 1'b1;
                    tx_en     <= 1'b1;
                    tx_b      <= '0;
                    tx_h      <= 1'b0;
                    tx_crc    <= '1;
                    tx_data   <= 4'h5;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // RX: nibbles -> bytes -> FCS check
    // ------------------------------------------------------------------
    logic        rx_in;          // inside a frame (after sof)
    logic        rx_data_ph;     // after the SFD
    logic        rx_hi;          // next nibble is the high one
    logic [3:0]  rx_lo;
    logic [31:0] rx_crc;
    logic        rx_bad_f;
    logic [10:0] rx_len;
    // (packed vectors: Gowin otherwise maps byte arrays to "RAMREG" and the paths get long)
    logic [111:0] rx_hdr;        // byte i at [8*i +: 8]
    logic [111:0] last_hdr;
    logic        rx_crc_ok;      // registered (eof comes >= 3 clocks after the last nibble)
    logic [10:0] last_len;
    logic [15:0] rx_good, rx_bad;
    always_ff @(posedge clk) rx_crc_ok <= rx_crc == 32'hDEBB20E3;
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            rx_good <= '0; rx_bad <= '0; last_len <= '0; last_hdr <= '0;
        end
        if (rst) begin
            rx_in <= 1'b0; rx_data_ph <= 1'b0; rx_hi <= 1'b0; rx_lo <= '0; rx_crc <= '1;
            rx_bad_f <= 1'b0; rx_len <= '0; led_rx <= 1'b0;
        end else begin
            if (rx_valid) begin
                if (rx_sof) begin
                    rx_in <= 1'b1; rx_data_ph <= 1'b0; rx_hi <= 1'b1; rx_lo <= rx_data;
                    rx_bad_f <= rx_er; rx_len <= '0; rx_crc <= '1;
                end else if (rx_in) begin
                    if (rx_er) rx_bad_f <= 1'b1;
                    if (!rx_hi) begin
                        rx_lo <= rx_data; rx_hi <= 1'b1;
                    end else begin
                        rx_hi <= 1'b0;
                        if (!rx_data_ph) begin
                            if ({rx_data, rx_lo} == 8'hd5) rx_data_ph <= 1'b1;
                            else if ({rx_data, rx_lo} != 8'h55) rx_bad_f <= 1'b1;
                        end else begin
                            rx_crc <= crc_byte(rx_crc, {rx_data, rx_lo});
                            if (rx_len < 14) rx_hdr[8 * rx_len[3:0] +: 8] <= {rx_data, rx_lo};
                            if (rx_len != 11'h7ff) rx_len <= rx_len + 1'b1;
                        end
                    end
                end
            end
            if (rx_eof && rx_in) begin
                rx_in <= 1'b0;
                if (!rx_bad_f && !rx_er && rx_data_ph && !rx_hi && rx_crc_ok && rx_len >= 18) begin
                    if (!clear) rx_good <= rx_good + 1'b1;
                    led_rx   <= ~led_rx;
                    last_len <= rx_len;
                    last_hdr <= rx_hdr;
                end else if (!clear) rx_bad <= rx_bad + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // counters for the report
    // ------------------------------------------------------------------
    logic [15:0] flp_cnt;
    logic [15:0] slip_cnt, slip_rate;
    always_ff @(posedge clk) begin
        if (rst || clear) flp_cnt <= '0;
        else if (flp_pulse) flp_cnt <= flp_cnt + 1'b1;
        if (rst) begin
            slip_cnt <= '0; slip_rate <= '0;
        end else if (tick_half) begin
            slip_rate <= slip_cnt;
            slip_cnt  <= {15'd0, cdr_slip};
        end else if (cdr_slip) slip_cnt <= slip_cnt + 1'b1;
    end

    // ------------------------------------------------------------------
    // UART status line
    // ------------------------------------------------------------------
    function automatic logic [7:0] hx(input logic [3:0] n);
        return (n < 10) ? 8'h30 + n : 8'h57 + n;
    endfunction
    function automatic logic [31:0] hx16(input logic [15:0] v);
        return {hx(v[15:12]), hx(v[11:8]), hx(v[7:4]), hx(v[3:0])};
    endfunction
    function automatic logic [15:0] hx8(input logic [7:0] v);
        return {hx(v[7:4]), hx(v[3:0])};
    endfunction

    // snapshot registers (taken when a line starts)
    logic [15:0] s_lp, s_flp, s_slip, s_good, s_bad, s_tx;
    logic [9:0]  s_tha, s_thb;
    logic [7:0]  s_misc;                  // {link, fd, pd, cdr, scr, an_state}
    logic [2:0]  s_mode;
    logic [111:0] s_hdr;
    logic [10:0] s_len;

    localparam int NCH = 120;
    logic [NCH*8-1:0] line;
    always_comb begin
        line = {
            "L", hx({3'b0, s_misc[7]}), " F", hx({3'b0, s_misc[6]}), " P", hx({3'b0, s_misc[5]}),
            " A", hx({1'b0, s_misc[2:0]}), " C", hx({3'b0, s_misc[4]}), " S", hx({3'b0, s_misc[3]}),
            " lp", hx16(s_lp), " f", hx16(s_flp), " s", hx16(s_slip),
            " r", hx16(s_good), " b", hx16(s_bad), " t", hx16(s_tx),
            " ta", hx16({6'd0, s_tha}), " tb", hx16({6'd0, s_thb}), " m", hx({1'b0, s_mode}),
            " h", hx8(s_hdr[0 +: 8]), hx8(s_hdr[8 +: 8]), hx8(s_hdr[16 +: 8]), hx8(s_hdr[24 +: 8]), hx8(s_hdr[32 +: 8]), hx8(s_hdr[40 +: 8]),
            " ", hx8(s_hdr[48 +: 8]), hx8(s_hdr[56 +: 8]), hx8(s_hdr[64 +: 8]), hx8(s_hdr[72 +: 8]), hx8(s_hdr[80 +: 8]), hx8(s_hdr[88 +: 8]),
            " ", hx8(s_hdr[96 +: 8]), hx8(s_hdr[104 +: 8]), " n", hx16({5'd0, s_len}), "\r\n"};
    end

    logic       u_valid, u_ready;
    logic [7:0] u_data;          // registered character of u_idx (the 120:1 mux gets a clock of its own)
    logic       u_ok;            // u_data belongs to the current u_idx
    logic [7:0] u_idx;
    logic       u_busy;
    uart_tx #(.NUMBER_OF_BITS(8), .BAUD_DIVIDER(CLK_HZ / BAUD)) u_uart_tx(
        .clock(clk), .reset(rst), .data_valid(u_valid), .data_ready(u_ready), .data_bits(u_data), .tx(uart_txd));
    // the line is right-aligned in `line`: the leading zero bytes are skipped
    assign u_valid = u_ok && u_data != 8'h00;
    wire   u_adv   = u_ok && (u_ready || u_data == 8'h00);

    always_ff @(posedge clk) begin
        u_data <= line[(NCH - 1 - u_idx) * 8 +: 8];
        if (rst) begin
            u_busy <= 1'b0; u_idx <= '0; u_ok <= 1'b0;
        end else if (!u_busy) begin
            u_ok <= 1'b0;
            if (tick_half) begin
                u_busy <= 1'b1;
                u_idx  <= '0;
                s_lp   <= lp_page; s_flp <= flp_cnt; s_slip <= slip_rate; s_good <= rx_good;
                s_bad  <= rx_bad; s_tx <= tx_count; s_tha <= th_a; s_thb <= th_b;
                s_misc <= {link, full_duplex, parallel, cdr_lock, scr_lock, an_state};
                s_mode <= {cdr_freeze, send_periodic, force_100};
                s_len  <= last_len;
                s_hdr  <= last_hdr;
            end
        end else if (u_adv) begin
            u_ok <= 1'b0;
            if (u_idx == 8'(NCH - 1)) u_busy <= 1'b0;
            u_idx <= u_idx + 1'b1;
        end else begin
            u_ok <= 1'b1;
        end
    end
endmodule
`default_nettype wire
