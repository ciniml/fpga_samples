// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// vfio-user bridge for the Verilated NvmeController.
//
// Exposes the RTL controller as a vfio-user PCI device (class code
// 010802h) so that SPDK's userspace VFIOUSER initiator drives the real
// RTL queue mechanics: BAR0 register accesses reach the CSR port, the
// doorbell page (BAR0 offset 1000h) is a shared-memory sparse mmap
// that the host writes directly and the bridge polls into the RTL,
// SQE/CQE/PRP traffic flows through the controller's DMA master port
// into the client's DMA-mapped memory (vfu_sgl_read/write).
//
// Unlike the NVMe/TCP bridge, no NVMe logic lives here: queues, phase
// tags, PRPs and doorbells are all handled by the RTL.
//
// Usage: nvme_vfio_bridge <socket-dir>
//   creates <socket-dir>/cntrl; connect SPDK with
//   -r 'trtype:VFIOUSER traddr:<socket-dir>'

#include "VNvmeController.h"
#include "verilated.h"

#define _Static_assert static_assert // the C headers use C11 _Static_assert
extern "C" {
#include "libvfio-user.h"
}

#include <fcntl.h>
#include <linux/pci_regs.h>
#include <poll.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#ifndef SIM_LBA_COUNT
#define SIM_LBA_COUNT 2048
#endif

static const size_t BAR0_SIZE = 0x4000;
static const size_t DB_OFFSET = 0x1000;
static const size_t DB_SIZE = 0x1000;

static vfu_ctx_t* g_ctx;

// ---------------------------------------------------------------------
// DMA helpers (into the client's DMA-mapped memory)
// ---------------------------------------------------------------------
static bool dma_rw(uint64_t addr, void* buf, size_t len, bool is_write) {
    dma_sg_t* sg = (dma_sg_t*)alloca(dma_sg_size());
    if (vfu_addr_to_sgl(g_ctx, (vfu_dma_addr_t)addr, len, sg, 1,
                        is_write ? PROT_WRITE : PROT_READ) <= 0) {
        fprintf(stderr, "[vfio] dma %s: bad address %#lx len %zu\n",
                is_write ? "write" : "read", (unsigned long)addr, len);
        return false;
    }
    // DIRECT_ACCESS: copy through the mapped fd. The socket fallback
    // must never be used - SPDK's client does not service
    // server-initiated DMA messages while it polls its queues.
    int rc = is_write ? vfu_sgl_write(g_ctx, sg, 1, buf, VFU_SGL_DIRECT_ACCESS)
                      : vfu_sgl_read(g_ctx, sg, 1, buf, VFU_SGL_DIRECT_ACCESS);
    if (rc < 0) {
        fprintf(stderr, "[vfio] dma %s failed at %#lx: %s\n",
                is_write ? "write" : "read", (unsigned long)addr, strerror(errno));
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------
// RTL driver
// ---------------------------------------------------------------------
class RtlCtrl {
public:
    RtlCtrl() : dut(new VNvmeController) {
        bmem.resize((size_t)SIM_LBA_COUNT * 128, 0);
        dut->i_rst = 1;
        dut->i_clk = 0;
        dut->i_csr_wen = 0;
        dut->i_csr_addr = 0;
        dut->i_csr_wdata = 0;
        dut->i_hm_ready = 1;
        dut->i_hm_rvalid = 0;
        dut->i_hm_rdata = 0;
        dut->i_mem_rdata = 0;
    dut->i_mem_ready = 1;
        for (int i = 0; i < 10; i++) tick();
        dut->i_rst = 0;
        for (int i = 0; i < 10; i++) tick();
    }

    void tick() {
        dut->i_clk = 0;
        dut->eval();
        // sample ports with the clock low
        bool hm_valid = dut->o_hm_valid;
        bool hm_write = dut->o_hm_write;
        uint64_t hm_addr = dut->o_hm_addr;
        uint32_t hm_wdata = dut->o_hm_wdata;
        bool m_wen = dut->o_mem_wen;
        bool m_ren = dut->o_mem_ren;
        uint32_t m_addr = dut->o_mem_addr;
        uint32_t m_wdata = dut->o_mem_wdata;
        dut->i_clk = 1;
        dut->eval();
        // backing RAM (1-cycle read latency)
        if (m_wen && m_addr < bmem.size()) bmem[m_addr] = m_wdata;
        if (m_ren) dut->i_mem_rdata = (m_addr < bmem.size()) ? bmem[m_addr] : 0;
        // host memory port: complete the DMA access at the edge where
        // it was accepted; read data is presented in the next cycle
        dut->i_hm_rvalid = 0;
        if (hm_valid) {
            if (hm_write) {
                dma_rw(hm_addr, &hm_wdata, 4, true);
            } else {
                uint32_t v = 0;
                dma_rw(hm_addr, &v, 4, false);
                dut->i_hm_rdata = v;
                dut->i_hm_rvalid = 1;
            }
        }
        dut->eval();
    }

    void run(int cycles) {
        for (int i = 0; i < cycles; i++) tick();
    }

    void csr_write(uint16_t addr, uint32_t data) {
        dut->i_csr_addr = addr & 0x3FFF;
        dut->i_csr_wdata = data;
        dut->i_csr_wen = 1;
        tick();
        dut->i_csr_wen = 0;
        tick();
    }

    uint32_t csr_read(uint16_t addr) {
        dut->i_csr_addr = addr & 0x3FFF;
        dut->eval();
        uint32_t v = dut->o_csr_rdata;
        tick();
        return v;
    }

private:
    std::unique_ptr<VNvmeController> dut;
    std::vector<uint32_t> bmem;
};

static RtlCtrl* g_rtl;

// ---------------------------------------------------------------------
// BAR0 access (non-mmap part: the register file)
// ---------------------------------------------------------------------
static ssize_t bar0_cb(vfu_ctx_t*, char* buf, size_t count, loff_t offset, bool is_write) {
    if ((offset & 3) != 0 || (count % 4) != 0 || offset + count > (loff_t)BAR0_SIZE) {
        errno = EINVAL;
        return -1;
    }
    for (size_t i = 0; i < count; i += 4) {
        uint16_t a = (uint16_t)(offset + i);
        if (is_write) {
            uint32_t v;
            memcpy(&v, buf + i, 4);
            g_rtl->csr_write(a, v);
        } else {
            uint32_t v = g_rtl->csr_read(a);
            memcpy(buf + i, &v, 4);
        }
    }
    // let the queue engine make progress right after a register kick
    g_rtl->run(64);
    return count;
}

static void dma_register_cb(vfu_ctx_t*, vfu_dma_info_t* info) {
    printf("[vfio] dma map iova=%#lx size=%#lx %s\n",
           (unsigned long)(uintptr_t)info->iova.iov_base,
           (unsigned long)info->iova.iov_len,
           info->vaddr ? "(mapped)" : "(not mappable)");
    fflush(stdout);
}

static void dma_unregister_cb(vfu_ctx_t*, vfu_dma_info_t*) {}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) {
        fprintf(stderr, "usage: %s <socket-dir>\n", argv[0]);
        return 1;
    }
    std::string sock = std::string(argv[1]) + "/cntrl";
    unlink(sock.c_str());

    RtlCtrl rtl;
    g_rtl = &rtl;

    g_ctx = vfu_create_ctx(VFU_TRANS_SOCK, sock.c_str(), LIBVFIO_USER_FLAG_ATTACH_NB,
                           nullptr, VFU_DEV_TYPE_PCI);
    if (!g_ctx) { perror("vfu_create_ctx"); return 1; }
    vfu_setup_log(g_ctx, [](vfu_ctx_t*, int level, const char* msg) {
        if (level <= LOG_WARNING) fprintf(stderr, "[libvfio-user] %s\n", msg);
    }, LOG_WARNING);

    if (vfu_pci_init(g_ctx, VFU_PCI_TYPE_EXPRESS, PCI_HEADER_TYPE_NORMAL, 0) < 0) {
        perror("vfu_pci_init");
        return 1;
    }
    vfu_pci_set_id(g_ctx, 0x1af4, 0x1001, 0x1af4, 0x1100); // virtio-ish test IDs
    vfu_pci_set_class(g_ctx, 0x01, 0x08, 0x02);            // NVM Express

    // doorbell page: shared memory the client writes directly
    int dbfd = memfd_create("nvme-doorbells", 0);
    if (dbfd < 0 || ftruncate(dbfd, BAR0_SIZE) < 0) { perror("memfd"); return 1; }
    uint32_t* dbmem = (uint32_t*)mmap(nullptr, BAR0_SIZE, PROT_READ | PROT_WRITE,
                                      MAP_SHARED, dbfd, 0);
    if (dbmem == MAP_FAILED) { perror("mmap doorbells"); return 1; }

    struct iovec mmap_area = { (void*)DB_OFFSET, DB_SIZE };
    if (vfu_setup_region(g_ctx, VFU_PCI_DEV_BAR0_REGION_IDX, BAR0_SIZE, bar0_cb,
                         VFU_REGION_FLAG_RW | VFU_REGION_FLAG_MEM,
                         &mmap_area, 1, dbfd, 0) < 0) {
        perror("vfu_setup_region");
        return 1;
    }
    if (vfu_setup_device_dma(g_ctx, LIBVFIO_USER_MAX_DMA_REGIONS,
                             dma_register_cb, dma_unregister_cb) < 0) {
        perror("vfu_setup_device_dma");
        return 1;
    }
    if (vfu_realize_ctx(g_ctx) < 0) { perror("vfu_realize_ctx"); return 1; }

    printf("[vfio] NVMe controller on %s (ns=1, %u blocks x 512B)\n",
           sock.c_str(), (unsigned)SIM_LBA_COUNT);
    fflush(stdout);

    uint32_t db_shadow[10] = {}; // admin + 4 I/O pairs
    bool attached = false;
    for (;;) {
        if (!attached) {
            if (vfu_attach_ctx(g_ctx) == 0) {
                attached = true;
                printf("[vfio] client attached\n");
                fflush(stdout);
            } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
                perror("vfu_attach_ctx");
                return 1;
            } else {
                usleep(10000);
                continue;
            }
        }

        struct pollfd pfd = { vfu_get_poll_fd(g_ctx), POLLIN, 0 };
        poll(&pfd, 1, 0);
        if (pfd.revents & POLLIN) {
            if (vfu_run_ctx(g_ctx) < 0) {
                if (errno == ENOTCONN) {
                    printf("[vfio] client detached\n");
                    fflush(stdout);
                    attached = false;
                    memset(db_shadow, 0, sizeof(db_shadow));
                    continue;
                }
                if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                    perror("vfu_run_ctx");
                    return 1;
                }
            }
        }

        // forward doorbell writes (SQ/CQ pairs for QID 0..4 at BAR0+1000h)
        volatile uint32_t* db = dbmem + DB_OFFSET / 4;
        for (int i = 0; i < 10; i++) {
            uint32_t v = db[i];
            if (v != db_shadow[i]) {
                db_shadow[i] = v;
                rtl.csr_write((uint16_t)(0x1000 + i * 4), v);
            }
        }

        rtl.run(256);
    }
}
