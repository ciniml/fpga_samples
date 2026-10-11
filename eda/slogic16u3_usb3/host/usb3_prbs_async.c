/* EP1 IN throughput / integrity test of the SLogic16U3 USB 3.0 device with libusb asynchronous
 * transfers: keeps QUEUE bulk IN transfers of SIZE bytes in flight, so the host controller always has
 * a request scheduled, and checks every byte against PRBS15 (same source and bit order as usb3_prbs.py).
 *
 *     cc -O2 -o usb3_prbs_async usb3_prbs_async.c -lusb-1.0
 *     usb3_prbs_async [-s SECONDS] [-q QUEUE] [-b SIZE] [-n]      (-n: no check)
 */
#include <libusb-1.0/libusb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define PERIOD 32767
static unsigned char tab[PERIOD * 2];
static int phase = -1, nocheck, running = 1, inflight;
static unsigned long long total, errs, first_err = ~0ULL;

static void prbs15_table(void) {
    unsigned s = 0x7FFF;
    for (int i = 0; i < PERIOD; i++) {
        unsigned v = 0;
        for (int k = 0; k < 8; k++) {
            unsigned b = ((s >> 14) ^ (s >> 13)) & 1;
            v |= b << k;
            s = ((s << 1) | b) & 0x7FFF;
        }
        tab[i] = tab[i + PERIOD] = v;
    }
}

static int find_phase(const unsigned char *d) {
    for (int p = 0; p < PERIOD; p++)
        if (!memcmp(tab + p, d, 32)) return p;
    return -1;
}

static void check(const unsigned char *d, int n) {
    if (phase < 0) {          /* the first bytes after the mode switch may be left over from before it */
        int skip;
        for (skip = 0; skip < 8 && n - skip >= 32; skip++)
            if ((phase = find_phase(d + skip)) >= 0) break;
        if (phase < 0) { fprintf(stderr, "PRBS phase not found\n"); exit(1); }
        d += skip; n -= skip;
    }
    while (n > 0) {
        int c = n < PERIOD - phase ? n : PERIOD - phase;
        if (memcmp(d, tab + phase, c)) {
            for (int i = 0; i < c; i++)
                if (d[i] != tab[phase + i]) { errs++; if (first_err == ~0ULL) first_err = total + i; }
            if (n >= 32 && (phase = find_phase(d + n - 32)) >= 0) { phase = (phase + 32) % PERIOD; return; }
            phase = 0; return;
        }
        phase = (phase + c) % PERIOD; d += c; n -= c;
    }
}

static void LIBUSB_CALL cb(struct libusb_transfer *t) {
    if (t->status != LIBUSB_TRANSFER_COMPLETED) {
        fprintf(stderr, "transfer status %d after %llu bytes\n", t->status, total);
        running = 0; inflight--; return;
    }
    if (!nocheck) check(t->buffer, t->actual_length);
    total += t->actual_length;
    if (running && libusb_submit_transfer(t) == 0) return;
    inflight--;
}

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

int main(int argc, char **argv) {
    double secs = 10; int queue = 8, size = 1 << 20, o;
    while ((o = getopt(argc, argv, "s:q:b:n")) != -1)
        switch (o) {
        case 's': secs = atof(optarg); break;
        case 'q': queue = atoi(optarg); break;
        case 'b': size = atoi(optarg); break;
        case 'n': nocheck = 1; break;
        default: return 2;
        }
    prbs15_table();
    libusb_context *ctx; libusb_init(&ctx);
    libusb_device_handle *h = libusb_open_device_with_vid_pid(ctx, 0x1209, 0x0001);
    if (!h) { fprintf(stderr, "device not found\n"); return 1; }
    libusb_set_configuration(h, 1);
    if (libusb_claim_interface(h, 0)) { fprintf(stderr, "claim failed\n"); return 1; }
    unsigned char *junk = malloc(1 << 16); int got;
    libusb_control_transfer(h, 0x40, 0x02, 0x0000, 0, NULL, 0, 1000);      /* loopback mode, drain */
    while (libusb_bulk_transfer(h, 0x81, junk, 1 << 16, &got, 50) == 0) ;
    libusb_control_transfer(h, 0x40, 0x02, 0x0001, 0, NULL, 0, 1000);      /* PRBS mode */
    struct libusb_transfer **ts = calloc(queue, sizeof *ts);
    double t0 = now();
    for (int i = 0; i < queue; i++) {
        ts[i] = libusb_alloc_transfer(0);
        unsigned char *buf = libusb_dev_mem_alloc(h, size);
        if (!buf) buf = malloc(size);
        libusb_fill_bulk_transfer(ts[i], h, 0x81, buf, size, cb, NULL, 2000);
        if (libusb_submit_transfer(ts[i])) { fprintf(stderr, "submit failed (queue %d)\n", i); return 1; }
        inflight++;
    }
    struct timeval tv = {0, 100000};
    while (running && now() - t0 < secs) libusb_handle_events_timeout(ctx, &tv);
    running = 0;
    double dt = now() - t0;
    unsigned long long tot = total;
    while (inflight > 0) libusb_handle_events_timeout(ctx, &tv);
    libusb_control_transfer(h, 0x40, 0x02, 0x0000, 0, NULL, 0, 1000);
    printf("queue %d x %d B: %.1f MB in %.2f s = %.1f MB/s, %s", queue, size, tot / 1e6, dt, tot / dt / 1e6,
           nocheck ? "not checked\n" : "");
    if (!nocheck) {
        printf("byte errors %llu", errs);
        if (errs) printf(", first at %llu", first_err);
        printf("\n");
    }
    libusb_release_interface(h, 0); libusb_close(h); libusb_exit(ctx);
    return errs ? 1 : 0;
}
