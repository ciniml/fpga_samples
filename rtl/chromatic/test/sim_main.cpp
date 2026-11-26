// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// cart_sim_top as a process: stdin bytes -> EP1 OUT stream, EP1 IN stream -> stdout.
// util/chromatic_cart_dump --sim <this executable> talks to it like to the USB device.
// The cartridge is inserted at start (CART_DET = 1) and the power switch is ON.
// Exit status: 0, or 3 when the cartridge model saw a rule violation.
#include "Vcart_sim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <cstdint>
#include <deque>
#include <vector>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char **argv) {
    // CART_SIM_ROMOUT=<file>: the cartridge model writes its ROM image there (+romout)
    std::vector<const char *> args(argv, argv + argc);
    std::string romout, ramout;
    if (const char *e = getenv("CART_SIM_ROMOUT")) { romout = std::string("+romout=") + e; args.push_back(romout.c_str()); }
    if (const char *e = getenv("CART_SIM_RAMOUT")) { ramout = std::string("+ramout=") + e; args.push_back(ramout.c_str()); }
    std::string flashout;
    if (const char *e = getenv("CART_SIM_FLASHOUT")) { flashout = std::string("+flashout=") + e; args.push_back(flashout.c_str()); }
    Verilated::commandArgs((int)args.size(), args.data());
    // the byte stream keeps the original stdout; $display output goes to stderr
    int data_fd = dup(1);
    dup2(2, 1);
    auto *m = new Vcart_sim_top;
    fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
    std::deque<uint8_t> in;
    std::vector<uint8_t> out;
    bool eof = false;
    uint64_t cyc = 0, idle = 0;
    m->rst = 1; m->cart_det = 1; m->switch_on = 1; m->host_ok = 1; m->rx_valid = 0; m->tx_ready = 1;
    auto tick = [&]() { m->clk = 0; m->eval(); m->clk = 1; m->eval(); cyc++; };
    for (int i = 0; i < 16; i++) tick();
    m->rst = 0;
    for (int i = 0; i < 4000; i++) tick();   // CART_DET debounce
    for (;;) {
        // host side: read what is available (block briefly only when the design is idle)
        if (!eof && (in.empty() || (cyc & 1023) == 0)) {
            struct pollfd p{0, POLLIN, 0};
            int to = (in.empty() && idle > 200000) ? 5 : 0;
            if (poll(&p, 1, to) > 0) {
                uint8_t b[4096];
                ssize_t n = read(0, b, sizeof b);
                if (n > 0) in.insert(in.end(), b, b + n);
                else if (n == 0) eof = true;
            }
        }
        m->rx_valid = !in.empty();
        m->rx_data = in.empty() ? 0 : in.front();
        // sample the handshakes before the edge
        m->clk = 0; m->eval();
        bool took = m->rx_valid && m->rx_ready;
        bool sent = m->tx_valid && m->tx_ready;
        uint8_t tx = m->tx_data;
        m->clk = 1; m->eval(); cyc++;
        if (took) in.pop_front();
        if (sent) out.push_back(tx);
        idle = (took || sent) ? 0 : idle + 1;
        if (!out.empty() && (out.size() >= 4096 || idle > 50)) {
            size_t off = 0;
            while (off < out.size()) {
                ssize_t n = write(data_fd, out.data() + off, out.size() - off);
                if (n <= 0) return 1;
                off += n;
            }
            out.clear();
        }
        if (m->n_violations) { fprintf(stderr, "cart_sim: rule violation, stopping\n"); return 3; }
        if (eof && in.empty() && idle > 100000) break;
    }
    fprintf(stderr, "cart_sim: %llu cycles, %d bus writes, %d RAM reads, %d violations%s\n",
            (unsigned long long)cyc, m->n_writes, m->n_ram_reads, m->n_violations,
            m->ram_enabled ? ", cartridge RAM left ENABLED" : "");
    int viol = m->n_violations + (m->ram_enabled ? 1 : 0);
    m->final();
    delete m;
    return viol ? 3 : 0;
}
