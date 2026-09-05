// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Socket pump for the Verilated NvmeTcpTarget.
//
// Unlike nvme_tcp_bridge.cpp (which implements the NVMe/TCP target in
// C++), this bridge contains no NVMe logic at all: it only shuttles
// bytes between up to two TCP sockets and the RTL's per-connection
// byte streams, plus the backing RAM model. All PDU parsing, fabrics
// handling, R2T flow and CQE construction happen in the RTL - exactly
// what an FPGA TCP engine would provide on real hardware.
//
// Usage: nvme_tcp_rtl_bridge [port]     (default port 4420)

#include "VNvmeTcpTarget.h"
#include "verilated.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <vector>

#ifndef SIM_LBA_COUNT
#define SIM_LBA_COUNT 2048
#endif

struct Conn {
    int fd = -1;
    std::deque<uint8_t> rx; // socket -> RTL
    std::vector<uint8_t> tx; // RTL -> socket
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    uint16_t port = 4420;
    if (argc > 1) port = (uint16_t)atoi(argv[1]);

    auto dut = std::make_unique<VNvmeTcpTarget>();
    std::vector<uint32_t> bmem((size_t)SIM_LBA_COUNT * 128, 0);

    dut->i_rst = 1;
    dut->i_clk = 0;
    dut->i_conn_active = 0;
    dut->i_rx_valid = 0;
    dut->i_rx_data = 0;
    dut->i_tx_ready = 3;
    dut->i_mem_rdata = 0;

    Conn conns[2];

    auto tick = [&]() {
        dut->i_clk = 0;
        dut->eval();
        // sample pre-edge values
        uint8_t rx_ready = dut->o_rx_ready;
        uint8_t tx_valid = dut->o_tx_valid;
        uint16_t tx_data = dut->o_tx_data;
        bool m_wen = dut->o_mem_wen;
        bool m_ren = dut->o_mem_ren;
        uint32_t m_addr = dut->o_mem_addr;
        uint32_t m_wdata = dut->o_mem_wdata;
        dut->i_clk = 1;
        dut->eval();
        if (m_wen && m_addr < bmem.size()) bmem[m_addr] = m_wdata;
        if (m_ren) dut->i_mem_rdata = (m_addr < bmem.size()) ? bmem[m_addr] : 0;
        // byte handshakes that completed at this edge
        for (int c = 0; c < 2; c++) {
            if ((dut->i_rx_valid >> c) & 1 && (rx_ready >> c) & 1) {
                conns[c].rx.pop_front();
            }
            if ((tx_valid >> c) & 1) { // i_tx_ready is always 1
                conns[c].tx.push_back((uint8_t)(tx_data >> (8 * c)));
            }
        }
        // present the next RX bytes
        uint8_t v = 0;
        uint16_t d = 0;
        for (int c = 0; c < 2; c++) {
            if (!conns[c].rx.empty()) {
                v |= 1 << c;
                d |= (uint16_t)conns[c].rx.front() << (8 * c);
            }
        }
        dut->i_rx_valid = v;
        dut->i_rx_data = d;
        dut->eval();
    };

    for (int i = 0; i < 10; i++) tick();
    dut->i_rst = 0;
    for (int i = 0; i < 10; i++) tick();

    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in sa{};
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons(port);
    if (bind(lfd, (sockaddr*)&sa, sizeof(sa)) < 0) { perror("bind"); return 1; }
    if (listen(lfd, 4) < 0) { perror("listen"); return 1; }
    fcntl(lfd, F_SETFL, O_NONBLOCK);
    printf("[pump] RTL NVMe/TCP target on 127.0.0.1:%u (ns=1, %u blocks x 512B)\n",
           port, (unsigned)SIM_LBA_COUNT);
    fflush(stdout);

    for (;;) {
        // accept into a free slot
        int cfd = accept(lfd, nullptr, nullptr);
        if (cfd >= 0) {
            int slot = -1;
            for (int c = 0; c < 2; c++) if (conns[c].fd < 0) { slot = c; break; }
            if (slot < 0) {
                close(cfd);
            } else {
                fcntl(cfd, F_SETFL, O_NONBLOCK);
                setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
                conns[slot].fd = cfd;
                conns[slot].rx.clear();
                conns[slot].tx.clear();
                dut->i_conn_active |= 1 << slot;
                printf("[pump] connection on slot %d\n", slot);
                fflush(stdout);
            }
        }

        // socket -> RX buffers, TX buffers -> socket
        bool idle = true;
        for (int c = 0; c < 2; c++) {
            Conn& cn = conns[c];
            if (cn.fd < 0) continue;
            uint8_t buf[65536];
            ssize_t n = read(cn.fd, buf, sizeof(buf));
            if (n > 0) {
                cn.rx.insert(cn.rx.end(), buf, buf + n);
                idle = false;
            } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                printf("[pump] slot %d closed\n", c);
                fflush(stdout);
                close(cn.fd);
                cn.fd = -1;
                cn.rx.clear();
                cn.tx.clear();
                dut->i_conn_active &= ~(1 << c);
                dut->eval();
            }
            if (cn.fd >= 0 && !cn.tx.empty()) {
                ssize_t w = write(cn.fd, cn.tx.data(), cn.tx.size());
                if (w > 0) cn.tx.erase(cn.tx.begin(), cn.tx.begin() + w);
                idle = false;
            }
            if (!cn.rx.empty()) idle = false;
        }

        for (int i = 0; i < 4096; i++) tick();
        if (idle) usleep(1000);
    }
}
