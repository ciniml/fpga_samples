// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// TAP <-> RMII bridge for eth_sim_top (RMII MAC + EthIpStack).
//
// Frames from the kernel's TAP device get preamble/SFD/FCS added and
// are serialized as RMII dibits into the DUT; the DUT's RMII TX is
// deserialized, FCS-checked/stripped and written back to the TAP. So
// `ping 192.168.37.2` exercises the exact RTL (MAC included) that goes
// on the board, against the real kernel network stack.
//
// One-time setup (root):
//   sudo ip tuntap add dev tap-nvme mode tap user $USER
//   sudo ip addr add 192.168.37.1/24 dev tap-nvme
//   sudo ip link set tap-nvme up
//
// Usage: eth_tap_bridge [tap-name]     (default tap-nvme)

#include "Veth_sim_top.h"
#include "verilated.h"

#include <fcntl.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <vector>

static void tcp_log(const char* dir, const uint8_t* f, size_t n) {
    if (n < 54 || f[12] != 0x08 || f[13] != 0x00 || f[23] != 0x06) return;
    uint16_t iplen = (f[16] << 8) | f[17];
    int doff = (f[46] >> 4) * 4;
    int plen = iplen - 20 - doff;
    uint32_t seq = (f[38] << 24) | (f[39] << 16) | (f[40] << 8) | f[41];
    uint32_t ack = (f[42] << 24) | (f[43] << 16) | (f[44] << 8) | f[45];
    printf("[tcp] %s seq=%08x ack=%08x flags=%02x win=%u plen=%d\n",
           dir, seq, ack, f[47], (f[48] << 8) | f[49], plen);
    if (dir[0] == 'O') {
        for (size_t i = 0; i < n && i < 64; i++)
            printf("%02x%s", f[i], (i % 16 == 15) ? "\n" : " ");
        printf("\n");
    }
    fflush(stdout);
}

static uint32_t crc32_step(uint32_t crc, uint8_t b) {
    crc ^= b;
    for (int i = 0; i < 8; i++)
        crc = (crc >> 1) ^ (0xEDB88320u & (-(int32_t)(crc & 1)));
    return crc;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* tap_name = (argc > 1) ? argv[1] : "tap-nvme";

    int tap = open("/dev/net/tun", O_RDWR | O_NONBLOCK);
    if (tap < 0) { perror("open /dev/net/tun"); return 1; }
    struct ifreq ifr {};
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    strncpy(ifr.ifr_name, tap_name, IFNAMSIZ - 1);
    if (ioctl(tap, TUNSETIFF, &ifr) < 0) {
        fprintf(stderr, "TUNSETIFF %s failed: %s\n", tap_name, strerror(errno));
        fprintf(stderr, "one-time setup:\n"
                        "  sudo ip tuntap add dev %s mode tap user $USER\n"
                        "  sudo ip addr add 192.168.37.1/24 dev %s\n"
                        "  sudo ip link set %s up\n",
                tap_name, tap_name, tap_name);
        return 1;
    }
    printf("[eth] bridging %s <-> RMII RTL (RTL is 192.168.37.2)\n", tap_name);
    fflush(stdout);

    auto dut = std::make_unique<Veth_sim_top>();
    dut->rst = 1;
    dut->clk = 0;
    dut->rmii_rxd = 0;
    dut->rmii_crs_dv = 0;

    std::deque<uint8_t> txdibits; // dibits to drive into the DUT
    // RX (DUT -> TAP) deserializer state
    int rx_bits = 0;
    uint32_t rx_sh = 0;
    bool rx_sync = false; // saw SFD
    std::vector<uint8_t> rx_frame;

    auto tick = [&]() {
        dut->clk = 0;
        dut->eval();
        dut->clk = 1;
        dut->eval();
        // drive next RX dibit (into the DUT); 0xFF marks an idle
        // (inter-frame gap) cycle with dv=0
        if (!txdibits.empty()) {
            uint8_t d = txdibits.front();
            txdibits.pop_front();
            dut->rmii_crs_dv = d != 0xFF;
            dut->rmii_rxd = (d != 0xFF) ? d : 0;
        } else {
            dut->rmii_crs_dv = 0;
            dut->rmii_rxd = 0;
        }
        // sample TX (from the DUT)
        if (dut->rmii_tx_en) {
            rx_sh = (rx_sh >> 2) | ((uint32_t)(dut->rmii_txd & 3) << 30);
            rx_bits += 2;
            if (!rx_sync) {
                // look for ...preamble + SFD 0xD5 in the top byte
                if (rx_bits >= 8 && ((rx_sh >> 24) & 0xFF) == 0xD5) {
                    rx_sync = true;
                    rx_bits = 0;
                    rx_frame.clear();
                }
            } else if (rx_bits == 8) {
                rx_frame.push_back((uint8_t)(rx_sh >> 24));
                rx_bits = 0;
            }
        } else if (rx_sync) {
            // end of frame: verify and strip the FCS
            if (rx_frame.size() > 4) {
                uint32_t crc = 0xFFFFFFFFu;
                for (size_t i = 0; i + 4 < rx_frame.size(); i++)
                    crc = crc32_step(crc, rx_frame[i]);
                crc ^= 0xFFFFFFFFu;
                uint32_t fcs = rx_frame[rx_frame.size() - 4] |
                               (rx_frame[rx_frame.size() - 3] << 8) |
                               (rx_frame[rx_frame.size() - 2] << 16) |
                               ((uint32_t)rx_frame[rx_frame.size() - 1] << 24);
                if (crc == fcs) {
                    ssize_t rc = write(tap, rx_frame.data(), rx_frame.size() - 4);
                    (void)rc;
                    tcp_log("OUT", rx_frame.data(), rx_frame.size() - 4);
                } else {
                    fprintf(stderr, "[eth] bad FCS on DUT TX (len %zu, calc %08x got %08x)\n",
                            rx_frame.size(), crc, fcs);
                    for (size_t i = 0; i < rx_frame.size(); i++) {
                        fprintf(stderr, "%02x%s", rx_frame[i], (i % 16 == 15) ? "\n" : " ");
                    }
                    fprintf(stderr, "\n");
                }
            }
            rx_sync = false;
            rx_bits = 0;
            rx_sh = 0;
        }
    };

    for (int i = 0; i < 20; i++) tick();
    dut->rst = 0;

    auto push_frame = [&](const uint8_t* f, size_t n) {
        for (int i = 0; i < 7; i++)
            for (int d = 0; d < 4; d++) txdibits.push_back((0x55 >> (2 * d)) & 3);
        for (int d = 0; d < 4; d++) txdibits.push_back((0xD5 >> (2 * d)) & 3);
        uint32_t crc = 0xFFFFFFFFu;
        size_t len = n < 60 ? 60 : n; // pad to the Ethernet minimum
        for (size_t i = 0; i < len; i++) {
            uint8_t b = (i < n) ? f[i] : 0;
            crc = crc32_step(crc, b);
            for (int d = 0; d < 4; d++) txdibits.push_back((b >> (2 * d)) & 3);
        }
        crc ^= 0xFFFFFFFFu;
        for (int i = 0; i < 4; i++) {
            uint8_t b = (uint8_t)(crc >> (8 * i));
            for (int d = 0; d < 4; d++) txdibits.push_back((b >> (2 * d)) & 3);
        }
        for (int i = 0; i < 48; i++) txdibits.push_back(0xFF); // 12-byte IPG (dv=0)
    };

    uint8_t buf[2048];
    for (;;) {
        ssize_t n = read(tap, buf, sizeof(buf));
        if (n > 0) {
            tcp_log("IN ", buf, (size_t)n);
            printf("[eth] TAP -> DUT %zd bytes (type %02x%02x) [rx=%u err=%u tx=%u]"
#ifdef DBG_APP
                   " [conn=%x arx=%u atx=%u]"
#endif
                   "\n",
                   n, buf[12], buf[13], dut->dbg_rx_frames, dut->dbg_rx_errs, dut->dbg_tx_frames
#ifdef DBG_APP
                   , dut->dbg_conn, dut->dbg_app_rx, dut->dbg_app_tx
#endif
                   );
            fflush(stdout);
            push_frame(buf, (size_t)n);
        }
        for (int i = 0; i < 8192; i++) tick();
        if (txdibits.empty() && n <= 0) {
            struct pollfd pfd = { tap, POLLIN, 0 };
            poll(&pfd, 1, 1);
        }
    }
}
