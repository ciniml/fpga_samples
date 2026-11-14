// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// bt_sim_top as a process for util/chromatic_bustest --sim:
//   Chromatic USB stream = stdin / stdout, target UART stream = the FIFOs named by
//   BT_SIM_UART_IN (host -> target) and BT_SIM_UART_OUT (target -> host).
// Clocks: 60 MHz and 100 MHz on a 5/3 ns step. $display goes to stderr.
// Exit status 3 when the data bus saw contention.
#include "Vbt_sim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <deque>
#include <vector>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>

struct Stream {
    int in_fd, out_fd;
    std::deque<uint8_t> in;
    std::vector<uint8_t> out;
    bool eof = false;
    void pump(bool block) {
        if (!eof) {
            struct pollfd p{in_fd, POLLIN, 0};
            if (poll(&p, 1, block ? 2 : 0) > 0) {
                uint8_t b[4096];
                ssize_t n = read(in_fd, b, sizeof b);
                if (n > 0) in.insert(in.end(), b, b + n);
                else if (n == 0) eof = true;
            }
        }
    }
    void flush() {
        size_t off = 0;
        while (off < out.size()) {
            ssize_t n = write(out_fd, out.data() + off, out.size() - off);
            if (n <= 0) exit(1);
            off += n;
        }
        out.clear();
    }
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int data_fd = dup(1);
    dup2(2, 1);
    const char *ui = getenv("BT_SIM_UART_IN"), *uo = getenv("BT_SIM_UART_OUT");
    if (!ui || !uo) { fprintf(stderr, "BT_SIM_UART_IN / BT_SIM_UART_OUT not set\n"); return 2; }
    int ufd_out = open(uo, O_WRONLY);      // opened first: the host opens its read end first too
    int ufd_in = open(ui, O_RDONLY | O_NONBLOCK);
    if (ufd_in < 0 || ufd_out < 0) { perror("fifo"); return 2; }
    fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
    Stream cs{0, data_fd}, ts{ufd_in, ufd_out};

    auto *m = new Vbt_sim_top;
    m->rst = 1; m->cart_det = 1; m->switch_on = 1;
    m->c_rx_valid = 0; m->c_tx_ready = 1; m->t_rx_valid = 0; m->t_tx_ready = 1;
    m->clk60 = 0; m->clk100 = 0; m->eval();
    uint64_t step = 0, idle = 0;
    auto do_step = [&]() {
        bool c60 = (step % 5) == 4, c100 = (step % 3) == 2;   // toggle on the next step
        bool r60 = c60 && !m->clk60, r100 = c100 && !m->clk100;
        bool took_c = false, sent_c = false, took_t = false, sent_t = false;
        uint8_t txc = 0, txt = 0;
        if (r60) {
            m->c_rx_valid = !cs.in.empty(); m->c_rx_data = cs.in.empty() ? 0 : cs.in.front(); m->eval();
            took_c = m->c_rx_valid && m->c_rx_ready; sent_c = m->c_tx_valid && m->c_tx_ready; txc = m->c_tx_data;
        }
        if (r100) {
            m->t_rx_valid = !ts.in.empty(); m->t_rx_data = ts.in.empty() ? 0 : ts.in.front(); m->eval();
            took_t = m->t_rx_valid && m->t_rx_ready; sent_t = m->t_tx_valid && m->t_tx_ready; txt = m->t_tx_data;
        }
        if (c60) m->clk60 = !m->clk60;
        if (c100) m->clk100 = !m->clk100;
        if (c60 || c100) m->eval();
        step++;
        if (took_c) cs.in.pop_front();
        if (sent_c) cs.out.push_back(txc);
        if (took_t) ts.in.pop_front();
        if (sent_t) ts.out.push_back(txt);
        if (took_c || sent_c || took_t || sent_t) idle = 0; else idle++;
    };
    for (int i = 0; i < 200; i++) do_step();
    m->rst = 0;
    for (int i = 0; i < 40000; i++) do_step();   // CART_DET debounce
    for (;;) {
        // look at the host side every 4096 steps; wait (2 ms) only when nothing has moved for a
        // long time (a test run sends its reply only at the end: blocking on every step would
        // stall it)
        if ((step & 4095) == 0) {
            bool block = cs.in.empty() && ts.in.empty() && idle > 3000000;
            cs.pump(block); ts.pump(false);
        }
        do_step();
        if (!cs.out.empty() && (cs.out.size() >= 4096 || idle > 100)) cs.flush();
        if (!ts.out.empty() && (ts.out.size() >= 256 || idle > 100)) ts.flush();
        if (cs.eof && cs.in.empty() && idle > 300000) break;
    }
    fprintf(stderr, "bt_sim: %llu steps, %d contention\n", (unsigned long long)step, m->n_contention);
    int c = m->n_contention;
    m->final();
    delete m;
    return c ? 3 : 0;
}
