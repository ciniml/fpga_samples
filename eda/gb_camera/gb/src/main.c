// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Viewfinder for the Game Boy Camera style cartridge of eda/gb_camera (GameCart mapper 6 + GbCamera).
//
// The camera as the Game Boy Camera's: RAM bank 10h maps its registers at 0xA000; writing 1 to
// 0xA000 shoots, 0xA000 bit 0 reads 1 until the 128x112 picture (16x14 tiles, 2 bpp) is in RAM
// bank 0 at 0xA100. Colour (register 36h bit 0, not in the Game Boy Camera): the tiles hold colour
// indices, 0xAF00 the BG attribute of every tile and 0xB000 the 4 palettes of every tile row
// (screen.c switches them row by row). Black and white: the Game Boy Camera's processing
// (exposure, contrast as dither thresholds, edge enhancement, invert) with grey palettes.
//
//   SELECT   colour / black and white
//   UP/DOWN  brightness (colour: the palettes; black and white: exposure)
//   LEFT/RIGHT contrast (black and white)      B  effect (black and white): edge, invert, both
//   A        keep the picture (3 places: RAM banks 1-3)
//   START    pictures kept (LEFT/RIGHT to look through, START or B back)
//
// DEMO (make demo): no camera; the picture of build/demo_data.c (gb_color_ref.py) instead.
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gb/hardware.h>
#include <stdint.h>
#include <string.h>
#include "screen.h"

#define CAM ((volatile uint8_t *)0xA000)
#define NSLOT 3
// a kept picture in RAM bank 1 + slot
#define KEEP_TILES 0xA000u
#define KEEP_ATTR  ((uint8_t *)0xAE00)
#define KEEP_PAL   ((uint8_t *)0xAF00)

static uint8_t colour = 1;
static int8_t bright = 0;                 // -4..4
static uint16_t exposure = 0x1000;
static uint8_t contrast = 6;              // 0..15
static uint8_t edge = 0;
static uint8_t invert = 0;
static uint8_t nkept = 0;
static uint8_t pad, latch;

static uint8_t attr[PIC_ATTR];
static uint8_t pal[PIC_PAL];
static uint8_t raw_buf[PIC_TILES + 16];   // 16-byte aligned through buf
static uint8_t *buf;

// 4x4 Bayer order of the dither thresholds
static const uint8_t bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
static const uint16_t grey[4] = {RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0)};

#ifdef DEMO
extern const uint8_t demo_tiles[PIC_TILES];
extern const uint8_t demo_attr[PIC_ATTR];
extern const uint8_t demo_pal[PIC_PAL];
#endif

static uint8_t pressed(uint8_t k) { return latch & k; }

// buttons pressed since the last look (sampled while waiting)
static void sample(void) {
    uint8_t p = joypad();
    latch |= p & ~pad;
    pad = p;
}

// registers 1-4, the thresholds 6-53 and colour (RAM bank 10h selected)
static void set_registers(void) {
    uint8_t i, lev;
    int16_t span = 16 + contrast * 7;
    int16_t lo = 128 - span, hi = 128 + span;
    if (lo < 0) lo = 0;
    if (hi > 255) hi = 255;
    CAM[1] = 0x04 | (edge ? 0xE0 : 0x00);
    CAM[2] = exposure >> 8;
    CAM[3] = exposure & 0xFF;
    CAM[4] = 0x20 | (invert ? 0x08 : 0x00);
    for (i = 0; i < 16; i++) {
        for (lev = 0; lev < 3; lev++) {
            int16_t a = lo + (hi - lo) * lev / 3;
            int16_t b = lo + (hi - lo) * (lev + 1) / 3;
            CAM[6 + i * 3 + lev] = (uint8_t)(a + (b - a) * (bayer[i] * 2 + 1) / 32);
        }
    }
    CAM[0x36] = colour;
}

// black and white: every tile the first palette of its row's half, all palettes grey
static void grey_tables(void) {
    uint8_t t, i;
    for (t = 0; t < PIC_ATTR; t++) attr[t] = 0x08 | (((t >> 4) & 1) << 2);
    for (i = 0; i < PIC_PAL / 2; i++) ((uint16_t *)pal)[i] = grey[i & 3];
}

// colour: brightness on the palettes
static void brighten(void) {
    uint8_t i;
    int8_t d = bright * 2;
    if (d == 0) return;
    for (i = 0; i < PIC_PAL / 2; i++) {
        uint16_t v = ((uint16_t *)pal)[i];
        int8_t r = (v & 31) + d, g = ((v >> 5) & 31) + d, b = ((v >> 10) & 31) + d;
        r = r < 0 ? 0 : r > 31 ? 31 : r;
        g = g < 0 ? 0 : g > 31 ? 31 : g;
        b = b < 0 ? 0 : b > 31 ? 31 : b;
        ((uint16_t *)pal)[i] = r | g << 5 | (uint16_t)b << 10;
    }
}

static void status(void) {
    screen_text(0, 15, colour ? "COLOR   " : "B&W     ");
    screen_text(8, 15, "KEPT ");
    screen_number(13, 15, nkept < NSLOT ? nkept : NSLOT, 1);
    screen_text(14, 15, "/3");
    if (colour) {
        screen_text(0, 16, "BRIGHT ");
        screen_text(7, 16, bright < 0 ? "-" : "+");
        screen_number(8, 16, bright < 0 ? -bright : bright, 1);
        screen_text(9, 16, "           ");
        screen_text(0, 17, "SEL B&W  START VIEW ");
    } else {
        screen_text(0, 16, "EXP ");
        screen_number(4, 16, exposure >> 8, 3);
        screen_text(7, 16, " CON ");
        screen_number(12, 16, contrast, 2);
        screen_text(14, 16, edge ? " E" : "  ");
        screen_text(16, 16, invert ? " I  " : "    ");
        screen_text(0, 17, "SEL COLOR B EFFECT  ");
    }
}

// the picture of the shot to the screen
static void shoot(void) {
#ifdef DEMO
    memcpy(buf, demo_tiles, PIC_TILES);
    if (colour) {
        memcpy(attr, demo_attr, PIC_ATTR);
        memcpy(pal, demo_pal, PIC_PAL);
        brighten();
    } else {
        grey_tables();
    }
    sample();
    screen_picture((uint16_t)buf, attr, pal);
#else
    SWITCH_RAM(0x10);
    set_registers();
    CAM[0] = 0x01;
    while (CAM[0] & 0x01) {
        sample();
    }
    SWITCH_RAM(0);
    if (colour) {
        memcpy(attr, (const uint8_t *)0xAF00, PIC_ATTR);
        memcpy(pal, (const uint8_t *)0xB000, PIC_PAL);
        brighten();
    } else {
        grey_tables();
    }
    sample();
    screen_picture(0xA100, attr, pal);
#endif
    sample();
}

static void keep(void) {
    uint8_t s = nkept % NSLOT;
#ifdef DEMO
    memcpy(buf, demo_tiles, PIC_TILES);
#else
    SWITCH_RAM(0);
    memcpy(buf, (const uint8_t *)0xA100, PIC_TILES);
#endif
    SWITCH_RAM(1 + s);
    memcpy((uint8_t *)KEEP_TILES, buf, PIC_TILES);
    memcpy(KEEP_ATTR, attr, PIC_ATTR);
    memcpy(KEEP_PAL, pal, PIC_PAL);
    if (nkept < 255) nkept++;
}

static void gallery(void) {
    uint8_t n = nkept < NSLOT ? nkept : NSLOT, s = 0, redraw = 1;
    screen_text(0, 16, n ? "PICTURE  /3         " : "NONE KEPT           ");
    screen_text(0, 17, "LEFT RIGHT  B BACK  ");
    for (;;) {
        if (redraw && n) {
            SWITCH_RAM(1 + s);
            memcpy(attr, KEEP_ATTR, PIC_ATTR);
            memcpy(pal, KEEP_PAL, PIC_PAL);
            screen_picture(KEEP_TILES, attr, pal);
            screen_number(8, 16, s + 1, 1);
            redraw = 0;
        }
        wait_vbl_done();
        latch = 0;
        sample();
        if (pressed(J_START) || pressed(J_B)) break;
        if (n && pressed(J_RIGHT)) { s = (s + 1) % n; redraw = 1; }
        if (n && pressed(J_LEFT)) { s = (s + n - 1) % n; redraw = 1; }
    }
    latch = 0;
    status();
}

void main(void) {
    cpu_fast();
    ENABLE_RAM;
    buf = (uint8_t *)(((uint16_t)raw_buf + 15) & 0xFFF0);
    screen_init();
    status();
    for (;;) {
        shoot();
        if (pressed(J_A)) keep();
        if (pressed(J_UP)) {
            if (colour) { if (bright < 4) bright++; }
            else if (exposure < 0xE000) exposure += exposure >> 3;
        }
        if (pressed(J_DOWN)) {
            if (colour) { if (bright > -4) bright--; }
            else if (exposure > 0x0100) exposure -= exposure >> 3;
        }
        if (!colour && pressed(J_RIGHT) && contrast < 15) contrast++;
        if (!colour && pressed(J_LEFT) && contrast > 0) contrast--;
        if (pressed(J_SELECT)) colour = !colour;
        if (!colour && pressed(J_B)) {
            uint8_t fx = (edge | invert << 1) + 1;
            edge = fx & 1;
            invert = (fx >> 1) & 1;
        }
        if (pressed(J_START)) gallery();
        if (latch) status();
        latch = 0;
    }
}
