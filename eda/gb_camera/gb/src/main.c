// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Viewfinder for the Game Boy Camera style cartridge of eda/gb_camera (GameCart mapper 6 + GbCamera).
//
// The camera as the Game Boy Camera's: RAM bank 10h maps its registers at 0xA000; writing 1 to
// 0xA000 shoots, 0xA000 bit 0 reads 1 until the 128x112 picture (16x14 tiles, 2 bpp) is in RAM
// bank 0 at 0xA100-0xAEFF. The tiles go to VRAM bank 1 by general purpose DMA, a quarter of the
// picture in each VBlank.
//
//   A        keep the picture (6 places: RAM banks 1-3, two pictures each)
//   UP/DOWN  exposure     LEFT/RIGHT contrast
//   SELECT   edge enhancement on / off     B  invert
//   START    pictures kept (LEFT/RIGHT to look through, START or B back)
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gb/hardware.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <gbdk/console.h>

#define CAM ((volatile uint8_t *)0xA000)
#define PIC_SIZE 0x0E00u
#define NSLOT 6

static uint16_t exposure = 0x1000;
static uint8_t contrast = 6;     // 0..15
static uint8_t edge = 0;
static uint8_t invert = 0;
static uint8_t nkept = 0;
static uint8_t buf[PIC_SIZE];
static uint8_t pad, latch;

static const palette_color_t grey[4] = {
    RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0)
};
// 4x4 Bayer order of the dither thresholds
static const uint8_t bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

static uint8_t pressed(uint8_t k) { return latch & k; }

// registers 1-4 and the thresholds 6-53 (RAM bank 10h selected)
static void set_registers(void) {
    uint8_t i, lev;
    int16_t span = 16 + contrast * 7;          // half the threshold range
    int16_t lo = 128 - span, hi = 128 + span;
    if (lo < 0) lo = 0;
    if (hi > 255) hi = 255;
    CAM[1] = 0x04 | (edge ? 0xE0 : 0x00);      // gain x1
    CAM[2] = exposure >> 8;
    CAM[3] = exposure & 0xFF;
    CAM[4] = 0x20 | (invert ? 0x08 : 0x00);    // edge ratio 1
    for (i = 0; i < 16; i++) {
        for (lev = 0; lev < 3; lev++) {
            int16_t a = lo + (hi - lo) * lev / 3;
            int16_t b = lo + (hi - lo) * (lev + 1) / 3;
            CAM[6 + i * 3 + lev] = (uint8_t)(a + (b - a) * (bayer[i] * 2 + 1) / 32);
        }
    }
}

// buttons pressed since the last look (sampled while waiting)
static void sample(void) {
    uint8_t p = joypad();
    latch |= p & ~pad;
    pad = p;
}

// n blocks of 16 bytes from src to VRAM at dst (in VBlank: ~8 us a block)
static void dma(uint16_t src, uint16_t dst, uint8_t n) {
    HDMA1_REG = src >> 8;
    HDMA2_REG = src & 0xF0;
    HDMA3_REG = (dst >> 8) & 0x1F;
    HDMA4_REG = dst & 0xF0;
    HDMA5_REG = n - 1;
}

// the picture at src (cart RAM, the bank already selected) to the screen: VRAM bank 1, one
// quarter in each VBlank. The background uses the 8800h tile addressing (the console's), so
// tiles 0-127 are at 9000h and tiles 128-223 at 8800h.
static void show(uint16_t src) {
    VBK_REG = 1;
    wait_vbl_done();
    dma(src, 0x9000, 64);
    sample();
    wait_vbl_done();
    dma(src + 0x400, 0x9400, 64);
    sample();
    wait_vbl_done();
    dma(src + 0x800, 0x8800, 64);
    sample();
    wait_vbl_done();
    dma(src + 0xC00, 0x8C00, 32);
    sample();
    VBK_REG = 0;
}

// (the console scrolls when a line wraps: lines of at most 19 characters)
static void status(void) {
    gotoxy(0, 16);
    printf("EXP %04X  CON %2u", exposure, contrast);
    gotoxy(0, 17);
    printf("EDGE %c INV %c  %u/%u", edge ? 'Y' : 'N', invert ? 'Y' : 'N', nkept < NSLOT ? nkept : NSLOT, NSLOT);
}

static void keep(void) {
    uint8_t s = nkept % NSLOT;
    SWITCH_RAM(0);
    memcpy(buf, (const uint8_t *)0xA100, PIC_SIZE);
    SWITCH_RAM(1 + s / 2);
    memcpy((uint8_t *)(0xA000 + (s & 1) * PIC_SIZE), buf, PIC_SIZE);
    if (nkept < 255) nkept++;
}

static void gallery(void) {
    uint8_t n = nkept < NSLOT ? nkept : NSLOT, s = 0, redraw = 1;
    gotoxy(0, 16);
    printf("PICTURES          ");
    gotoxy(0, 17);
    printf(n ? "LEFT/RIGHT, B     " : "NONE KEPT         ");
    for (;;) {
        if (redraw && n) {
            SWITCH_RAM(1 + s / 2);
            show(0xA000 + (s & 1) * PIC_SIZE);
            gotoxy(12, 16);
            printf("%u/%u ", s + 1, n);
            redraw = 0;
        }
        wait_vbl_done();
        latch = 0;
        sample();
        if (pressed(J_START) || pressed(J_B)) break;
        if (n && pressed(J_RIGHT)) { s = (s + 1) % n; redraw = 1; }
        if (n && pressed(J_LEFT)) { s = (s + n - 1) % n; redraw = 1; }
    }
    status();
}

static void screen_init(void) {
    uint8_t x, y, row[16];
    DISPLAY_OFF;
    set_bkg_palette(0, 1, grey);
    printf(" ");                                // the console loads its font into VRAM bank 0
    cls();
    // the picture: tiles 0-223 of VRAM bank 1 at (2, 1)
    for (y = 0; y < 14; y++) {
        for (x = 0; x < 16; x++) row[x] = y * 16 + x;
        set_bkg_tiles(2, 1 + y, 16, 1, row);
    }
    VBK_REG = 1;
    for (x = 0; x < 16; x++) row[x] = 0x08;     // attributes: tile bank 1, palette 0
    for (y = 0; y < 14; y++) set_bkg_tiles(2, 1 + y, 16, 1, row);
    VBK_REG = 0;
    gotoxy(5, 0);
    printf("GB CAMERA");
    status();
    SHOW_BKG;
    DISPLAY_ON;
}

void main(void) {
    cpu_fast();
    ENABLE_RAM;
    screen_init();
    for (;;) {
        SWITCH_RAM(0x10);
        set_registers();
        CAM[0] = 0x01;                          // shoot
        while (CAM[0] & 0x01) {
            sample();
        }
        SWITCH_RAM(0);
        show(0xA100);

        if (pressed(J_A)) keep();
        if (pressed(J_UP) && exposure < 0xE000) exposure += exposure >> 3;
        if (pressed(J_DOWN) && exposure > 0x0100) exposure -= exposure >> 3;
        if (pressed(J_RIGHT) && contrast < 15) contrast++;
        if (pressed(J_LEFT) && contrast > 0) contrast--;
        if (pressed(J_SELECT)) edge = !edge;
        if (pressed(J_B)) invert = !invert;
        if (pressed(J_START)) gallery();
        if (latch) status();
        latch = 0;
    }
}
