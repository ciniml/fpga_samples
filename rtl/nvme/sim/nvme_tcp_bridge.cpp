// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// NVMe/TCP target bridge for the Verilated NvmeCore.
//
// Plays the transport role of the transport-independent NVMe core:
// terminates NVMe/TCP (NVMe over Fabrics) connections from a userspace
// host such as SPDK, handles everything that belongs to the transport
// (ICReq/ICResp negotiation, Fabrics Connect / Property Get/Set,
// Keep Alive, R2T write data collection, CQE construction, and the
// fabrics-specific Identify Controller fields), and forwards the actual
// NVMe commands to the RTL simulation as SQE + h2c/c2h dword streams.
//
// Everything runs in user space: plain TCP sockets, no kernel NVMe
// involvement. One RTL command executes at a time; multiple host queues
// (one TCP connection per queue) are serialized into the core.
//
// Usage: nvme_tcp_bridge [port]     (default port 4420)
//   subsystem NQN: nqn.2026-09.org.fugafuga:nvme:veryl-sim

#include "VNvmeCore.h"
#include "verilated.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef SIM_LBA_COUNT
#define SIM_LBA_COUNT 2048
#endif

static const char* SUBNQN = "nqn.2026-09.org.fugafuga:nvme:veryl-sim";

// ---------------------------------------------------------------------
// little-endian helpers
// ---------------------------------------------------------------------
static uint16_t get16(const uint8_t* p) { return p[0] | (p[1] << 8); }
static uint32_t get32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t get64(const uint8_t* p) { return get32(p) | ((uint64_t)get32(p + 4) << 32); }
static void put16(uint8_t* p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t* p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void put64(uint8_t* p, uint64_t v) { put32(p, v); put32(p + 4, v >> 32); }

// ---------------------------------------------------------------------
// RTL simulation driver
// ---------------------------------------------------------------------
class RtlNvme {
public:
    RtlNvme() : dut(new VNvmeCore) {
        mem.resize((size_t)SIM_LBA_COUNT * 128, 0);
        dut->i_rst = 1;
        dut->i_clk = 0;
        dut->i_sq_valid = 0;
        dut->i_h2c_valid = 0;
        dut->i_c2h_ready = 0;
        dut->i_cpl_ready = 0;
        dut->i_mem_rdata = 0;
    dut->i_mem_ready = 1;
        for (int i = 0; i < 10; i++) tick();
        dut->i_rst = 0;
        for (int i = 0; i < 10; i++) tick();
    }

    // Execute one command. h2c holds the full host write data (may be
    // empty); c2h receives the controller data (Read/Identify).
    // Returns false on simulation timeout.
    bool exec(bool admin, const uint8_t sqe[64], const std::vector<uint8_t>& h2c,
              std::vector<uint8_t>& c2h, uint16_t& cid, uint16_t& status, uint32_t& dw0) {
        c2h.clear();
        // --- SQE phase ---
        for (int i = 0; i < 16; i++) {
            dut->i_sq_valid = 1;
            dut->i_sq_is_admin = admin;
            dut->i_sq_data = get32(sqe + i * 4);
            uint64_t guard = 0;
            for (;;) {
                dut->eval();
                bool ready = dut->o_sq_ready;
                tick();
                if (ready) break;
                if (++guard > TIMEOUT) return false;
            }
        }
        dut->i_sq_valid = 0;

        // --- data + completion phase ---
        size_t h2c_dw = h2c.size() / 4;
        size_t h2c_idx = 0;
        dut->i_c2h_ready = 1;
        dut->i_cpl_ready = 1;
        uint64_t guard = 0;
        for (;;) {
            dut->i_h2c_valid = h2c_idx < h2c_dw;
            if (h2c_idx < h2c_dw) dut->i_h2c_data = get32(h2c.data() + h2c_idx * 4);
            dut->eval();
            if (dut->o_cpl_valid) {
                cid = dut->o_cpl_cid;
                status = dut->o_cpl_status;
                dw0 = dut->o_cpl_dw0;
                tick(); // consume the completion
                break;
            }
            if (dut->o_c2h_valid) {
                uint8_t b[4];
                put32(b, dut->o_c2h_data);
                c2h.insert(c2h.end(), b, b + 4);
            }
            bool h2c_taken = dut->i_h2c_valid && dut->o_h2c_ready;
            tick();
            if (h2c_taken) h2c_idx++;
            if (++guard > TIMEOUT) return false;
        }
        dut->i_h2c_valid = 0;
        dut->i_c2h_ready = 0;
        dut->i_cpl_ready = 0;
        for (int i = 0; i < 4; i++) tick();
        return true;
    }

    uint64_t cycles = 0;

private:
    static const uint64_t TIMEOUT = 100000000ULL;

    void tick() {
        dut->i_clk = 0;
        dut->eval();
        // sample the memory port with the clock low (pre-edge values)
        bool wen = dut->o_mem_wen;
        bool ren = dut->o_mem_ren;
        uint32_t addr = dut->o_mem_addr;
        uint32_t wdata = dut->o_mem_wdata;
        dut->i_clk = 1;
        dut->eval();
        // synchronous RAM: write takes effect at the edge, read data is
        // visible in the following cycle
        if (wen && addr < mem.size()) mem[addr] = wdata;
        if (ren) dut->i_mem_rdata = (addr < mem.size()) ? mem[addr] : 0;
        dut->eval();
        cycles++;
    }

    std::unique_ptr<VNvmeCore> dut;
    std::vector<uint32_t> mem;
};

// ---------------------------------------------------------------------
// NVMe/TCP target
// ---------------------------------------------------------------------
enum PduType : uint8_t {
    PDU_ICREQ = 0x00,
    PDU_ICRESP = 0x01,
    PDU_H2C_TERM = 0x02,
    PDU_C2H_TERM = 0x03,
    PDU_CAPSULE_CMD = 0x04,
    PDU_CAPSULE_RESP = 0x05,
    PDU_H2C_DATA = 0x06,
    PDU_C2H_DATA = 0x07,
    PDU_R2T = 0x09,
};

static const uint32_t MAX_H2C_DATA = 131072;
static const size_t C2H_CHUNK = 8192;

struct PendingWrite {
    uint8_t sqe[64];
    bool admin;
    std::vector<uint8_t> data;
    uint32_t received = 0;
};

struct Conn {
    int fd = -1;
    std::vector<uint8_t> rx;
    bool ic_done = false;
    bool connected = false; // Fabrics Connect done
    uint16_t qid = 0;
    uint16_t sqsize = 0;
    uint16_t sqhd = 0;
    uint16_t next_ttag = 1;
    std::map<uint16_t, PendingWrite> pending;
};

class Bridge {
public:
    explicit Bridge(uint16_t port) : port_(port) {}

    int run() {
        int lfd = socket(AF_INET, SOCK_STREAM, 0);
        int one = 1;
        setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        sockaddr_in sa{};
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        sa.sin_port = htons(port_);
        if (bind(lfd, (sockaddr*)&sa, sizeof(sa)) < 0) { perror("bind"); return 1; }
        if (listen(lfd, 8) < 0) { perror("listen"); return 1; }
        printf("[bridge] NVMe/TCP target on 127.0.0.1:%u  subnqn=%s  ns=1 (%u blocks x 512B)\n",
               port_, SUBNQN, (unsigned)SIM_LBA_COUNT);
        fflush(stdout);

        for (;;) {
            std::vector<pollfd> pfds;
            pfds.push_back({lfd, POLLIN, 0});
            for (auto& c : conns_) pfds.push_back({c->fd, POLLIN, 0});
            if (poll(pfds.data(), pfds.size(), -1) < 0) {
                if (errno == EINTR) continue;
                perror("poll");
                return 1;
            }
            if (pfds[0].revents & POLLIN) {
                int cfd = accept(lfd, nullptr, nullptr);
                if (cfd >= 0) {
                    setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
                    auto c = std::make_unique<Conn>();
                    c->fd = cfd;
                    conns_.push_back(std::move(c));
                    printf("[bridge] connection accepted (fd=%d)\n", cfd);
                    fflush(stdout);
                }
            }
            for (size_t i = 0; i < conns_.size();) {
                bool alive = true;
                for (auto& p : pfds) {
                    if (p.fd == conns_[i]->fd && (p.revents & (POLLIN | POLLERR | POLLHUP))) {
                        alive = service(*conns_[i]);
                        break;
                    }
                }
                if (!alive) {
                    printf("[bridge] connection closed (fd=%d, qid=%u)\n", conns_[i]->fd, conns_[i]->qid);
                    fflush(stdout);
                    close(conns_[i]->fd);
                    conns_.erase(conns_.begin() + i);
                } else {
                    i++;
                }
            }
        }
    }

private:
    // ---- socket plumbing -------------------------------------------
    bool service(Conn& c) {
        uint8_t buf[65536];
        ssize_t n = read(c.fd, buf, sizeof(buf));
        if (n <= 0) return false;
        c.rx.insert(c.rx.end(), buf, buf + n);
        while (c.rx.size() >= 8) {
            uint32_t plen = get32(c.rx.data() + 4);
            if (plen < 8 || plen > 16 * 1024 * 1024) {
                fprintf(stderr, "[bridge] bad plen %u, dropping connection\n", plen);
                return false;
            }
            if (c.rx.size() < plen) break;
            if (!handle_pdu(c, c.rx.data(), plen)) return false;
            c.rx.erase(c.rx.begin(), c.rx.begin() + plen);
        }
        return true;
    }

    static bool send_all(int fd, const uint8_t* p, size_t n) {
        while (n > 0) {
            ssize_t w = write(fd, p, n);
            if (w <= 0) return false;
            p += w;
            n -= w;
        }
        return true;
    }

    // ---- PDU handling ----------------------------------------------
    bool handle_pdu(Conn& c, const uint8_t* pdu, uint32_t plen) {
        uint8_t type = pdu[0];
        switch (type) {
        case PDU_ICREQ: {
            if (plen < 128) return false;
            uint16_t pfv = get16(pdu + 8);
            if (pfv != 0) {
                fprintf(stderr, "[bridge] unsupported PDU format version %u\n", pfv);
                return false;
            }
            uint8_t resp[128] = {};
            resp[0] = PDU_ICRESP;
            resp[2] = 128;      // hlen
            put32(resp + 4, 128); // plen
            put16(resp + 8, 0); // pfv
            resp[10] = 0;       // cpda
            resp[11] = 0;       // digests disabled
            put32(resp + 12, MAX_H2C_DATA);
            c.ic_done = true;
            return send_all(c.fd, resp, sizeof(resp));
        }
        case PDU_CAPSULE_CMD: {
            if (!c.ic_done || plen < 8 + 64) return false;
            const uint8_t* sqe = pdu + 8;
            uint8_t pdo = pdu[3];
            const uint8_t* icd = nullptr;
            uint32_t icd_len = 0;
            if (plen > 72) { // in-capsule data present
                uint32_t off = pdo ? pdo : 72;
                if (off < plen) {
                    icd = pdu + off;
                    icd_len = plen - off;
                }
            }
            return handle_command(c, sqe, icd, icd_len);
        }
        case PDU_H2C_DATA: {
            if (plen < 24) return false;
            uint16_t ttag = get16(pdu + 10);
            uint32_t datao = get32(pdu + 12);
            uint32_t datal = get32(pdu + 16);
            uint8_t pdo = pdu[3];
            uint32_t off = pdo ? pdo : 24;
            auto it = c.pending.find(ttag);
            if (it == c.pending.end()) {
                fprintf(stderr, "[bridge] H2CData with unknown ttag %u\n", ttag);
                return false;
            }
            PendingWrite& pw = it->second;
            if (off + datal > plen || datao + datal > pw.data.size()) {
                fprintf(stderr, "[bridge] H2CData out of bounds\n");
                return false;
            }
            memcpy(pw.data.data() + datao, pdu + off, datal);
            pw.received += datal;
            if (pw.received >= pw.data.size()) {
                bool ok = execute(c, pw.sqe, pw.admin, pw.data);
                c.pending.erase(it);
                return ok;
            }
            return true;
        }
        case PDU_H2C_TERM:
            fprintf(stderr, "[bridge] host sent H2CTermReq\n");
            return false;
        default:
            fprintf(stderr, "[bridge] unexpected PDU type %02x\n", type);
            return false;
        }
    }

    // ---- command routing -------------------------------------------
    bool handle_command(Conn& c, const uint8_t* sqe, const uint8_t* icd, uint32_t icd_len) {
        uint8_t opc = sqe[0];
        uint16_t cid = get16(sqe + 2);

        if (opc == 0x7F) { // Fabrics command
            uint8_t fctype = sqe[4];
            switch (fctype) {
            case 0x01: { // Connect
                c.qid = get16(sqe + 42);
                c.sqsize = get16(sqe + 44);
                c.connected = true;
                printf("[bridge] fabrics connect: qid=%u sqsize=%u\n", c.qid, c.sqsize + 1);
                fflush(stdout);
                return send_resp(c, cid, 0, 1 /* cntlid */, 0);
            }
            case 0x00: { // Property Set
                uint32_t ofst = get32(sqe + 44);
                uint64_t val = get64(sqe + 48);
                if (ofst == 0x14) { // CC
                    cc_ = (uint32_t)val;
                    if (cc_ & 1) csts_ |= 1; else csts_ &= ~1u;
                    if ((cc_ >> 14) & 3) csts_ = (csts_ & ~0xCu) | 0x8; // shutdown complete
                }
                return send_resp(c, cid, 0, 0, 0);
            }
            case 0x04: { // Property Get
                uint32_t ofst = get32(sqe + 44);
                uint64_t val = 0;
                switch (ofst) {
                case 0x00: // CAP: MQES=255, TO=15, CSS=NVM
                    val = 0xFFull | (15ull << 24) | (1ull << 37);
                    break;
                case 0x08: val = 0x00010400; break; // VS 1.4
                case 0x14: val = cc_; break;
                case 0x1C: val = csts_; break;
                default: val = 0; break;
                }
                return send_resp(c, cid, 0, (uint32_t)val, (uint32_t)(val >> 32));
            }
            case 0x08: // Disconnect
                return send_resp(c, cid, 0, 0, 0);
            default:
                fprintf(stderr, "[bridge] unsupported fabrics fctype %02x\n", fctype);
                return send_resp(c, cid, make_error(0x02), 0, 0); // invalid field
            }
        }

        bool admin = c.qid == 0;
        if (admin && opc == 0x18) // Keep Alive
            return send_resp(c, cid, 0, 0, 0);
        if (admin && opc == 0x0C) // Async Event Request: completes only on an event
            return true;

        // NVM Write needs host data first
        if (!admin && opc == 0x01) {
            uint32_t nlb = get16(sqe + 48); // CDW12[15:0], 0-based
            uint32_t len = (nlb + 1) * 512;
            if (icd_len >= len) {
                std::vector<uint8_t> data(icd, icd + len);
                return execute(c, sqe, admin, data);
            }
            uint16_t ttag = c.next_ttag++;
            PendingWrite pw;
            memcpy(pw.sqe, sqe, 64);
            pw.admin = admin;
            pw.data.assign(len, 0);
            if (icd_len > 0) {
                memcpy(pw.data.data(), icd, icd_len);
                pw.received = icd_len;
            }
            c.pending.emplace(ttag, std::move(pw));
            return send_r2t(c, cid, ttag, icd_len, len - icd_len);
        }

        std::vector<uint8_t> no_data;
        return execute(c, sqe, admin, no_data);
    }

    // ---- RTL execution + response ----------------------------------
    bool execute(Conn& c, const uint8_t* sqe, bool admin, const std::vector<uint8_t>& h2c) {
        std::vector<uint8_t> c2h;
        uint16_t rtl_cid, status;
        uint32_t dw0;
        if (!rtl_.exec(admin, sqe, h2c, c2h, rtl_cid, status, dw0)) {
            fprintf(stderr, "[bridge] RTL timeout on opcode %02x\n", sqe[0]);
            return false;
        }
        uint16_t cid = get16(sqe + 2);
        printf("[bridge] %s opc=%02x cid=%04x nsid=%u cdw10=%08x sgl(type=%02x len=%u) -> status=%04x c2h=%zuB\n",
               admin ? "admin" : "io", sqe[0], cid, get32(sqe + 4), get32(sqe + 40),
               sqe[39], get32(sqe + 32), status, c2h.size());
        fflush(stdout);
        if (admin && sqe[0] == 0x06 && status == 0 && (get32(sqe + 40) & 0xFF) == 0x01)
            patch_identify_ctrl(c2h);
        if (!c2h.empty() && !send_c2h_data(c, cid, c2h)) return false;
        return send_resp(c, cid, status, dw0, 0);
    }

    // Fabrics-specific Identify Controller fields the transport owns
    // (NVMe-oF 1.1 figure 30). The RTL core stays transport-neutral.
    static void patch_identify_ctrl(std::vector<uint8_t>& d) {
        if (d.size() < 4096) return;
        put16(d.data() + 78, 1);              // CNTLID
        put16(d.data() + 320, 10);            // KAS: 1s granularity
        put16(d.data() + 514, 128);           // MAXCMD
        put32(d.data() + 536, 0x00300001);    // SGLS: SGL + offset + transport data block
        memset(d.data() + 768, 0, 256);       // SUBNQN
        strncpy((char*)d.data() + 768, SUBNQN, 255);
        put32(d.data() + 1792, 4);            // IOCCSZ: 64B capsule, no in-capsule data
        put32(d.data() + 1796, 1);            // IORCSZ: 16B response capsule
        put16(d.data() + 1800, 0);            // ICDOFF
        d[1803] = 1;                          // MSDBD: 1 SGL descriptor
    }

    static uint16_t make_error(uint8_t sc) {
        return (uint16_t)(1u << 14) | sc; // DNR | SCT=0 | SC
    }

    bool send_resp(Conn& c, uint16_t cid, uint16_t status15, uint32_t dw0, uint32_t dw1) {
        uint8_t pdu[24] = {};
        pdu[0] = PDU_CAPSULE_RESP;
        pdu[2] = 24;
        put32(pdu + 4, 24);
        uint8_t* cqe = pdu + 8;
        put32(cqe + 0, dw0);
        put32(cqe + 4, dw1);
        put16(cqe + 8, c.sqhd);
        put16(cqe + 12, cid);
        put16(cqe + 14, (uint16_t)(status15 << 1)); // phase = 0
        if (c.sqsize) c.sqhd = (c.sqhd + 1) % (c.sqsize + 1);
        return send_all(c.fd, pdu, sizeof(pdu));
    }

    bool send_r2t(Conn& c, uint16_t cid, uint16_t ttag, uint32_t offset, uint32_t len) {
        uint8_t pdu[24] = {};
        pdu[0] = PDU_R2T;
        pdu[2] = 24;
        put32(pdu + 4, 24);
        put16(pdu + 8, cid);
        put16(pdu + 10, ttag);
        put32(pdu + 12, offset);
        put32(pdu + 16, len);
        return send_all(c.fd, pdu, sizeof(pdu));
    }

    bool send_c2h_data(Conn& c, uint16_t cid, const std::vector<uint8_t>& data) {
        size_t off = 0;
        while (off < data.size()) {
            size_t chunk = std::min(C2H_CHUNK, data.size() - off);
            bool last = off + chunk >= data.size();
            std::vector<uint8_t> pdu(24 + chunk);
            pdu[0] = PDU_C2H_DATA;
            pdu[1] = last ? 0x04 : 0x00; // LAST_PDU
            pdu[2] = 24;
            pdu[3] = 24; // pdo
            put32(pdu.data() + 4, (uint32_t)(24 + chunk));
            put16(pdu.data() + 8, cid);
            put32(pdu.data() + 12, (uint32_t)off);
            put32(pdu.data() + 16, (uint32_t)chunk);
            memcpy(pdu.data() + 24, data.data() + off, chunk);
            if (!send_all(c.fd, pdu.data(), pdu.size())) return false;
            off += chunk;
        }
        return true;
    }

    uint16_t port_;
    std::vector<std::unique_ptr<Conn>> conns_;
    RtlNvme rtl_;
    uint32_t cc_ = 0;
    uint32_t csts_ = 0;
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    uint16_t port = 4420;
    if (argc > 1) port = (uint16_t)atoi(argv[1]);
    Bridge bridge(port);
    return bridge.run();
}
