/* SLogic16U3 logic analyzer (eda/slogic16u3_la): capture over USB 3.0 with libusb asynchronous
 * transfers, the stream format of rtl/la/la_pkg.veryl, and the test mode check.
 *
 *     cc -O2 -o la_stream la_stream.c -lusb-1.0
 *
 *     la_stream [-a CFG] [-b CFG] [-s SECONDS] [-o PREFIX] [-t VOLTS] [-q QUEUE] [-z SIZE]
 *     la_stream -T            test-mode matrix: every configuration checked sample by sample
 *
 * CFG (one group: -a = CH0..7, -b = CH8..15; a group without one is off), comma separated:
 *     ch=1|2|4|8          channels (the group's lowest ones)
 *     rate=800M|400M|..   internal clock 800 MHz / div (or div=N): div 1, 2, 4 or >= 8
 *     clk=rise|fall|both  the group's clock input instead (CK0 for A, CK1 for B; cksel=other swaps),
 *                         at most one used edge per 10 ns
 *     skew=0..7           edge clocks: take the sample this many 1.25 ns before the edge
 *     test                PRBS instead of the pins (A: PRBS15, B: PRBS17) and a test clock of
 *     thalf=N             half period N samples (a power of two) for the edge clocks; the data is
 *                         then checked
 * -o PREFIX writes the packed samples of each group to PREFIX_a.bin / PREFIX_b.bin (W bits per
 * sample from bit 0 of byte 0 on). -t sets the CH threshold (volts at the probe, ~6.7 V x duty).
 */
#include <libusb-1.0/libusb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define VID 0x1209
#define PID 0x0001

typedef struct {
    int en, wlog, cmode, test, skew, cksel;
    unsigned div, thalf;
} gcfg_t;

static libusb_context *ctx;
static libusb_device_handle *h;

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

static void reg_wr(int a, unsigned v) {
    if (libusb_control_transfer(h, 0x40, 0x03, v & 0xFFFF, a, NULL, 0, 1000) < 0) { fprintf(stderr, "reg write %02x failed\n", a); exit(1); }
}
static unsigned reg_rd(int a) {
    unsigned char b[4];
    if (libusb_control_transfer(h, 0xC0, 0x04, 0, a, b, 4, 1000) != 4) { fprintf(stderr, "reg read %02x failed\n", a); exit(1); }
    return b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
}

/* ---------------------------------------------------------------- test pattern model */
static uint8_t tab15[32767], tab17[131071];
static void make_tabs(void) {
    unsigned s = 0x7FFF;
    for (int i = 0; i < 32767; i++) {
        unsigned v = 0;
        for (int k = 0; k < 8; k++) { unsigned b = ((s >> 14) ^ (s >> 13)) & 1; v |= b << k; s = ((s << 1) | b) & 0x7FFF; }
        tab15[i] = v;
    }
    s = 0x1FFFF;
    for (int i = 0; i < 131071; i++) {
        unsigned v = 0;
        for (int k = 0; k < 8; k++) { unsigned b = ((s >> 16) ^ (s >> 13)) & 1; v |= b << k; s = ((s << 1) | b) & 0x1FFFF; }
        tab17[i] = v;
    }
}
static long gcd(long a, long b) { while (b) { long t = a % b; a = b; b = t; } return a; }

/* the expected packed stream of a group in test mode: sample j = raw(k0 + j D) (raw positions count
 * from word 0 of the capture; taken from position 8 on, LaFront), W bits each - periodic, one period
 * is P 64-bit words (P = raw period / gcd(D, raw period), odd) */
typedef struct { uint64_t *w; long p; } exp_t;
static void make_expected(exp_t *e, int g, const gcfg_t *c) {
    long L = g ? 131071 : 32767, D, k0;
    const uint8_t *tab = g ? tab17 : tab15;
    int W = 1 << c->wlog, H = c->thalf ? c->thalf : 1, s = c->skew;
    if (c->cmode == 0) { D = c->div ? c->div : 1; k0 = 8; }
    else {
        long first = 8 + s, k;
        if (c->cmode == 1) { D = 2 * H; k = H; }          /* rising: (2m+1) H */
        else if (c->cmode == 2) { D = 2 * H; k = 2 * H; } /* falling: 2m H, m >= 1 */
        else { D = H; k = H; }                            /* both: m H, m >= 1 */
        while (k < first) k += D;
        k0 = k - s;
    }
    e->p = L / gcd(D % L, L);
    e->w = calloc(e->p, 8);
    long n = e->p * 64 / W;
    for (long j = 0; j < n; j++) {
        unsigned v = tab[(k0 + (j % e->p) * (D % L)) % L] & ((1 << W) - 1);
        long b = j * W;
        e->w[b / 64] |= (uint64_t)v << (b % 64);
    }
}

/* ---------------------------------------------------------------- stream state */
typedef struct {
    gcfg_t c;
    exp_t e;
    int started, ended, flags;
    unsigned nseq, seqerr;
    uint64_t words;          /* 64-bit payload words received */
    uint64_t count;          /* END: samples */
    uint64_t nbad, first_bad;
    uint64_t bad_idx[64];    /* (the first mismatching word indices, the last word is judged at END) */
    int nbad_idx;
    uint64_t last;           /* the last payload word */
    FILE *out;
} st_t;
static st_t st[2];
static int capid;
static uint64_t total_bytes;
static int verify;

/* parser over 32-bit words across transfers */
static int p_state;          /* 0: header, 1: payload */
static unsigned p_hdr, p_left, p_have;
static uint32_t p_ev[2], p_lo;
static int p_err;

static void data_word(st_t *s, uint64_t w) {
    if (verify) {
        uint64_t x = s->e.w[s->words % s->e.p];
        if (x != w) {
            if (s->nbad_idx < 64) s->bad_idx[s->nbad_idx++] = s->words;
            if (!s->nbad) s->first_bad = s->words;
            s->nbad++;
        }
    }
    s->last = w;
    s->words++;
}

static void parse(const uint8_t *buf, int n) {
    for (int i = 0; i + 4 <= n; i += 4) {
        uint32_t w = buf[i] | buf[i + 1] << 8 | buf[i + 2] << 16 | (uint32_t)buf[i + 3] << 24;
        if (p_state == 0) {
            int ty = w >> 28, g = (w >> 26) & 3;
            if (g > 1 || (w >> 24 & 3) || (ty != 1 && ty != 4 && ty != 5)) {
                if (!p_err) fprintf(stderr, "bad header %08x\n", w);
                p_err++;
                continue;
            }
            p_hdr = w; p_left = w & 0xFFFF; p_have = 0;
            if (ty == 1) {
                st_t *s = &st[g];
                if (!s->started || s->ended) p_err++;
                if (((w >> 16) & 0xFF) != (s->nseq & 0xFF)) s->seqerr++;
                s->nseq++;
            }
            if (p_left) p_state = 1;
        } else {
            int ty = p_hdr >> 28, g = (p_hdr >> 26) & 3;
            if (ty == 1) {
                if (p_have & 1) {
                    uint64_t v = (uint64_t)w << 32 | p_lo;
                    data_word(&st[g], v);
                    if (st[g].out) fwrite(&v, 8, 1, st[g].out);
                } else p_lo = w;
            } else if (p_have < 2) p_ev[p_have] = w;
            p_have++;
            if (--p_left == 0) {
                p_state = 0;
                if (ty != 1) {
                    uint64_t b = (uint64_t)p_ev[1] << 32 | p_ev[0];
                    if (((p_hdr >> 16) & 0xFF) == (unsigned)(capid & 0xFF)) {
                        if (ty == 4) { st[g].started++; st[g].nseq = 0; }
                        else { st[g].ended++; st[g].count = b & 0xFFFFFFFFFFFFull; st[g].flags = (b >> 56) & 0xF; }
                    }
                }
            }
        }
    }
}

/* ---------------------------------------------------------------- transfers */
static int running, inflight, xfer_err;
static void LIBUSB_CALL cb(struct libusb_transfer *t) {
    if (t->status == LIBUSB_TRANSFER_COMPLETED || t->status == LIBUSB_TRANSFER_TIMED_OUT) {
        parse(t->buffer, t->actual_length);
        total_bytes += t->actual_length;
    } else if (t->status != LIBUSB_TRANSFER_CANCELLED) {
        fprintf(stderr, "transfer status %d\n", t->status);
        xfer_err++;
        running = 0;
    }
    if (running && libusb_submit_transfer(t) == 0) return;
    inflight--;
}

static int queue_n = 4, xfer_size = 1 << 20;

static void group_regs(int g, const gcfg_t *c) {
    int b = g ? 0x0A : 0x02;
    reg_wr(b, (c->cksel & 1) << 8 | (c->skew & 7) << 5 | (c->test & 1) << 4 | (c->cmode & 3) << 2 | (c->wlog & 3));
    reg_wr(b + 1, c->div & 0xFFFF);
    reg_wr(b + 2, (c->div >> 16) & 0xFF);
    reg_wr(b + 3, c->thalf);
}

static int report(int expect_flags[2]);
static void setup_streams(const gcfg_t *a, const gcfg_t *b, const char *prefix) {
    memset(st, 0, sizeof st);
    st[0].c = *a; st[1].c = *b;
    verify = 1;
    for (int g = 0; g < 2; g++) {
        if (!st[g].c.en) continue;
        if (!st[g].c.test) verify = 0;
        else make_expected(&st[g].e, g, &st[g].c);
        if (prefix) {
            char fn[512]; snprintf(fn, sizeof fn, "%s_%c.bin", prefix, 'a' + g);
            st[g].out = fopen(fn, "wb");
        }
    }
    p_state = 0; p_err = 0; total_bytes = 0; xfer_err = 0;
}

/* one capture; returns 0 when every enabled group ended cleanly (and checked, in test mode) */
static int capture(const gcfg_t *a, const gcfg_t *b, double secs, const char *prefix, int expect_flags[2], double *mbps) {
    unsigned char junk[65536]; int got;
    reg_wr(0x00, 0);                                                      /* stop, drain */
    while (libusb_bulk_transfer(h, 0x81, junk, sizeof junk, &got, 100) == 0) ;
    setup_streams(a, b, prefix);
    group_regs(0, a); group_regs(1, b);
    reg_wr(0x01, (a->en ? 1 : 0) | (b->en ? 2 : 0));
    capid = (capid + 1) & 0xFF;

    /* (the buffers are allocated once: usbfs limits the memory of a process, 16 MB by default) */
    static struct libusb_transfer *ts[64];
    static unsigned char *bufs[64];
    running = 1; inflight = 0;
    for (int i = 0; i < queue_n; i++) {
        if (!bufs[i]) {
            bufs[i] = libusb_dev_mem_alloc(h, xfer_size);
            if (!bufs[i]) bufs[i] = malloc(xfer_size);
        }
        ts[i] = libusb_alloc_transfer(0);
        libusb_fill_bulk_transfer(ts[i], h, 0x81, bufs[i], xfer_size, cb, NULL, 100);
        if (libusb_submit_transfer(ts[i])) { fprintf(stderr, "submit failed\n"); exit(1); }
        inflight++;
    }
    reg_wr(0x00, capid << 8 | 1);
    double t0 = now(), t1;
    struct timeval tv = {0, 50000};
    while (running && now() - t0 < secs) libusb_handle_events_timeout(ctx, &tv);
    reg_wr(0x00, capid << 8);                                             /* stop */
    t1 = now();
    uint64_t bytes_run = total_bytes;
    while (running && now() - t1 < 3.0 && !((!a->en || st[0].ended) && (!b->en || st[1].ended)))
        libusb_handle_events_timeout(ctx, &tv);
    running = 0;
    while (inflight > 0) libusb_handle_events_timeout(ctx, &tv);
    for (int i = 0; i < queue_n; i++) libusb_free_transfer(ts[i]);
    *mbps = bytes_run / (t1 - t0) / 1e6;
    return report(expect_flags) || xfer_err;
}

/* the result of a capture: START / END, sizes, sequence numbers, flags and (test mode) the data */
static int report(int expect_flags[2]) {
    int bad = p_err;
    if (p_err) printf("    stream format errors %d\n", p_err);
    for (int g = 0; g < 2; g++) {
        st_t *s = &st[g];
        if (!s->c.en) continue;
        int W = 1 << s->c.wlog;
        uint64_t valid_bits = s->count * W, nfull = valid_bits / 64;
        uint64_t exp_words = ((s->count + 7) / 8 * 8 * W + 63) / 64;
        uint64_t real_bad = 0;
        if (verify) {
            for (int k = 0; k < s->nbad_idx; k++) if (s->bad_idx[k] < nfull) real_bad++;
            if (s->nbad > (uint64_t)s->nbad_idx) real_bad += s->nbad - s->nbad_idx;   /* (beyond the recorded ones) */
            if (valid_bits % 64 && nfull < s->words) {
                uint64_t m = (1ull << (valid_bits % 64)) - 1, x = s->e.w[nfull % s->e.p];
                uint64_t lw = (nfull == s->words - 1) ? s->last : 0;   /* (the last word is the partial one) */
                if (nfull == s->words - 1 && (lw & m) != (x & m)) real_bad++;
            }
        }
        int ok = s->started == 1 && s->ended == 1 && s->seqerr == 0 && s->words == exp_words &&
                 real_bad == 0 && s->flags == expect_flags[g];
        printf("    %c: %llu samples, %llu words%s%s, flags %d, seq err %u%s%s\n", 'A' + g,
               (unsigned long long)s->count, (unsigned long long)s->words,
               s->words == exp_words ? "" : " (size mismatch)",
               s->started == 1 && s->ended == 1 ? "" : " (START/END missing)",
               s->flags, s->seqerr,
               verify ? (real_bad ? ", DATA ERRORS" : ", data ok") : "",
               s->flags != expect_flags[g] ? " (unexpected flags)" : "");
        if (verify && real_bad)
            printf("      %llu bad words, first at word %llu\n", (unsigned long long)real_bad, (unsigned long long)s->first_bad);
        if (!ok) bad = 1;
        if (s->out) fclose(s->out);
        free(s->e.w);
    }
    return bad;
}

/* ---------------------------------------------------------------- configuration strings */
static int parse_cfg(const char *str, gcfg_t *c) {
    memset(c, 0, sizeof *c);
    c->en = 1; c->wlog = 3; c->div = 1; c->thalf = 4;
    char buf[256]; snprintf(buf, sizeof buf, "%s", str);
    for (char *tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
        char *v = strchr(tok, '=');
        if (v) *v++ = 0;
        if (!strcmp(tok, "ch")) { int n = atoi(v); c->wlog = n >= 8 ? 3 : n >= 4 ? 2 : n >= 2 ? 1 : 0; }
        else if (!strcmp(tok, "div")) c->div = strtoul(v, NULL, 0);
        else if (!strcmp(tok, "rate")) {
            double r = atof(v); char u = v[strlen(v) - 1];
            r *= u == 'M' ? 1e6 : u == 'k' ? 1e3 : 1;
            c->div = (unsigned)(800e6 / r + 0.5);
            if (c->div < 1) c->div = 1;
        } else if (!strcmp(tok, "clk")) c->cmode = !strcmp(v, "rise") ? 1 : !strcmp(v, "fall") ? 2 : !strcmp(v, "both") ? 3 : 0;
        else if (!strcmp(tok, "skew")) c->skew = atoi(v);
        else if (!strcmp(tok, "test")) c->test = 1;
        else if (!strcmp(tok, "thalf")) c->thalf = atoi(v);
        else if (!strcmp(tok, "cksel")) c->cksel = !strcmp(v, "other");
        else { fprintf(stderr, "unknown option %s\n", tok); return -1; }
    }
    return 0;
}

static void describe(char *o, size_t n, const gcfg_t *c) {
    if (!c->en) { snprintf(o, n, "-"); return; }
    int W = 1 << c->wlog;
    if (c->cmode == 0) snprintf(o, n, "%dch %.4gM", W, 800.0 / c->div);
    else snprintf(o, n, "%dch %s%s skew%d", W, c->cmode == 1 ? "rise" : c->cmode == 2 ? "fall" : "both",
                  c->test ? "" : "", c->skew);
    if (c->test && c->cmode) snprintf(o + strlen(o), n - strlen(o), " %.4gMHz", 400.0 / c->thalf);
}

int main(int argc, char **argv) {
    gcfg_t a = {0}, b = {0};
    double secs = 5, vth = -1; const char *prefix = NULL; int matrix = 0, o;
    const char *infile = NULL; int fcap = -1, fflags[2] = {0, 0};
    while ((o = getopt(argc, argv, "a:b:s:o:t:q:z:Tf:c:F:")) != -1)
        switch (o) {
        case 'a': if (parse_cfg(optarg, &a)) return 2; break;
        case 'b': if (parse_cfg(optarg, &b)) return 2; break;
        case 's': secs = atof(optarg); break;
        case 'o': prefix = optarg; break;
        case 't': vth = atof(optarg); break;
        case 'q': queue_n = atoi(optarg); break;
        case 'z': xfer_size = atoi(optarg); break;
        case 'T': matrix = 1; break;
        case 'f': infile = optarg; break;
        case 'c': fcap = atoi(optarg); break;
        case 'F': fflags[0] = atoi(optarg) & 3; fflags[1] = (atoi(optarg) >> 2) & 3; break;
        default: return 2;
        }
    make_tabs();
    if (infile) {
        /* -f FILE -c CAPID [-F FLAGS]: check a stream saved to a file (32-bit words, little endian),
         * e.g. from the simulation (rtl/la/test), with the same configuration options */
        FILE *f = fopen(infile, "rb");
        if (!f) { perror(infile); return 1; }
        fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
        uint8_t *buf = malloc(n);
        if (fread(buf, 1, n, f) != (size_t)n) return 1;
        fclose(f);
        setup_streams(&a, &b, prefix);
        capid = fcap;
        parse(buf, n);
        int r = report(fflags);
        printf("%s\n", r ? "FAIL" : "PASS");
        return r;
    }
    libusb_init(&ctx);
    h = libusb_open_device_with_vid_pid(ctx, VID, PID);
    if (!h) { fprintf(stderr, "device not found\n"); return 1; }
    libusb_set_configuration(h, 1);
    if (libusb_claim_interface(h, 0)) { fprintf(stderr, "claim failed\n"); return 1; }
    unsigned id = reg_rd(0x00), status = reg_rd(0x01);
    if ((id & 0xFFFF) != 0x4C41) { fprintf(stderr, "not the logic analyzer bitstream (id %08x)\n", id); return 1; }
    if (!(status & 0x20)) fprintf(stderr, "warning: sample clock not running (status %08x)\n", status);
    if (vth >= 0) {
        unsigned d = (unsigned)(vth / 6.7 * 1024 + 0.5);
        if (d > 1023) d = 1023;
        reg_wr(0x10, d);
        usleep(20000);
    }
    int fails = 0;
    if (matrix) {
        static const struct { const char *a, *b; int fa, fb; double s; } m[] = {
            {"test,ch=4,div=1", NULL, 0, 0, 3},                    /* 800 MS/s x 4ch = 400 MB/s */
            {"test,ch=8,div=2", NULL, 0, 0, 3},                    /* 400 MS/s x 8ch */
            {"test,ch=8,div=4", "test,ch=8,div=4", 0, 0, 3},       /* 200 MS/s x 16ch */
            {"test,ch=4,div=2", "test,ch=4,div=2", 0, 0, 3},       /* 400 MS/s x 4 + 4 */
            {"test,ch=2,div=1", "test,ch=2,div=1", 0, 0, 3},       /* 800 MS/s x 2 + 2 */
            {NULL, "test,ch=4,div=1", 0, 0, 3},                    /* group B alone */
            {"test,ch=1,div=8", "test,ch=2,div=10", 0, 0, 2},      /* 100 / 80 MS/s */
            {"test,ch=8,div=9", "test,ch=4,div=13", 0, 0, 2},
            {"test,ch=8,div=800", "test,ch=8,div=8000", 0, 0, 2},  /* 1 MS/s / 100 kS/s */
            {"test,ch=8,clk=rise,thalf=4,skew=3", "test,ch=8,clk=rise,thalf=4", 0, 0, 2},   /* 100 MHz clocks */
            {"test,ch=4,clk=fall,thalf=4,skew=7", "test,ch=8,clk=rise,thalf=64", 0, 0, 2},
            {"test,ch=8,clk=both,thalf=8,skew=1", "test,ch=2,clk=both,thalf=16,skew=6", 0, 0, 2},  /* 50 / 25 MHz */
            {"test,ch=8,clk=both,thalf=1", "test,ch=8,div=8", 2, 0, 1},   /* too fast: flag 2 on A */
            {"test,ch=8,div=3", NULL, 2, 0, 1},                    /* div 3: not supported */
            {"test,ch=8,div=1", NULL, 1, 0, 1},                    /* 800 MB/s: overflow (flag 1) */
        };
        for (unsigned i = 0; i < sizeof m / sizeof m[0]; i++) {
            gcfg_t ca = {0}, cb = {0}; char da[64], db[64]; double mb;
            if (m[i].a) parse_cfg(m[i].a, &ca);
            if (m[i].b) parse_cfg(m[i].b, &cb);
            describe(da, sizeof da, &ca); describe(db, sizeof db, &cb);
            int ef[2] = {m[i].fa, m[i].fb};
            printf("[%2u] A %-28s B %-28s\n", i, da, db);
            int r = capture(&ca, &cb, m[i].s, NULL, ef, &mb);
            printf("    %s  %.1f MB/s\n", r ? "FAIL" : "PASS", mb);
            fails += r;
        }
        printf("%d of %zu failed\n", fails, sizeof m / sizeof m[0]);
    } else {
        if (!a.en && !b.en) { fprintf(stderr, "no group configured (-a / -b)\n"); return 2; }
        int ef[2] = {0, 0}; double mb;
        fails = capture(&a, &b, secs, prefix, ef, &mb);
        printf("%.1f MB/s%s\n", mb, fails ? " (problems above)" : "");
    }
    libusb_release_interface(h, 0); libusb_close(h); libusb_exit(ctx);
    return fails ? 1 : 0;
}
