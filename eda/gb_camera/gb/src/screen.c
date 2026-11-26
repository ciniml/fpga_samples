// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// The picture's tiles are tiles 0-223 of VRAM bank 1 (8800h addressing: tiles 0-127 at 9000h,
// 128-223 at 8800h). Even tile rows use BG palettes 0-3, odd rows 4-7: while a tile row is on the
// screen, the HBlank after each of its 8 lines writes 4 bytes of the next row's palettes into the
// other half (the STAT interrupt, mode 0, a stream of commands prepared here). Tile row 0's palettes
// are loaded in VBlank; during the last row the first half gets the text palettes for rows 15-17.
// The font (tiles 128-191 of VRAM bank 0) and a blank tile (192) are the rest of the screen.
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gb/hardware.h>
#include <gb/isr.h>
#include <string.h>
#include "screen.h"

extern const uint8_t font_tiles[64 * 16];

#define FONT_BASE  128u
#define BLANK_TILE 192u
#define NROW       14u

typedef struct {
    uint8_t bcps;
    uint8_t d[4];
} pal_cmd_t;

static pal_cmd_t stream[112];             // lines 8..119
pal_cmd_t *pal_ptr;                       // the STAT interrupt's next command
static uint8_t row0[32];                  // tile row 0's palettes (palettes 0-3)

// text: white, light grey, dark grey, black
static const palette_color_t ui_pal[16] = {
    RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0),
    RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0),
    RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0),
    RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0),
};

// HBlank of lines 8..119: one palette command (BCPS, then 4 bytes of BCPD)
void stat_isr(void) NAKED {
    __asm
    push af
    push hl
    ldh a, (_LY_REG)
    sub a, #8
    cp a, #112
    jr nc, 1$
    ld hl, #_pal_ptr
    ld a, (hl+)
    ld h, (hl)
    ld l, a
    ld a, (hl+)
    ldh (_BCPS_REG), a
    ld a, (hl+)
    ldh (_BCPD_REG), a
    ld a, (hl+)
    ldh (_BCPD_REG), a
    ld a, (hl+)
    ldh (_BCPD_REG), a
    ld a, (hl+)
    ldh (_BCPD_REG), a
    ld a, l
    ld (_pal_ptr), a
    ld a, h
    ld (_pal_ptr + 1), a
1$:
    pop hl
    pop af
    reti
    __endasm;
}
ISR_VECTOR(VECTOR_STAT, stat_isr)

// tile row 0's palettes into palettes 0-3 (VBlank; unrolled: the C loop took most of VBlank)
static void load_row0(void) NAKED {
    __asm
    ld hl, #_row0
    ld a, #0x80
    ldh (_BCPS_REG), a
    ld c, #0x69
    .rept 32
    ld a, (hl+)
    ldh (c), a
    .endm
    ret
    __endasm;
}

static void vbl(void) {
    pal_ptr = stream;
    load_row0();
}

// tile row r's 4 palettes (32 bytes)
static void row_palettes(uint8_t r, const uint8_t *p) {
    uint8_t c;
    if (r == 0) {
        memcpy(row0, p, 32);
        return;
    }
    for (c = 0; c < 8; c++) {
        pal_cmd_t *e = &stream[(r - 1) * 8 + c];
        e->bcps = 0x80 | ((r & 1) ? 32 : 0) | (c * 4);
        memcpy(e->d, p + c * 4, 4);
    }
}

// n blocks of 16 bytes from src to VRAM at dst (in VBlank: ~8 us a block)
static void dma(uint16_t src, uint16_t dst, uint8_t n) {
    HDMA1_REG = src >> 8;
    HDMA2_REG = src & 0xF0;
    HDMA3_REG = (dst >> 8) & 0x1F;
    HDMA4_REG = dst & 0xF0;
    HDMA5_REG = n - 1;
}

// tile rows a VBlank: attributes (16 bytes a row), then the tiles (16 blocks of DMA a row). SameBoy
// takes 2 rows, the Chromatic only 1 (2 overran VBlank there: broken tiles in the middle, 2026-11-26)
#ifndef ROWS_PER_VBL
#define ROWS_PER_VBL 1u
#endif

void screen_picture(uint16_t tiles, const uint8_t *attr, const uint8_t *pal) {
    uint8_t q, r;
    for (q = 0; q < NROW; q += ROWS_PER_VBL) {
        uint8_t last = q + ROWS_PER_VBL < NROW ? q + ROWS_PER_VBL : NROW;
        wait_vbl_done();
        VBK_REG = 1;
        for (r = q; r < last; r++) memcpy((uint8_t *)(0x9800 + (1 + r) * 32 + 2), attr + r * 16, 16);
        for (r = q; r < last; r++) dma(tiles + r * 256, r < 8 ? 0x9000 + r * 256 : 0x8800 + (r - 8) * 256, 16);
        VBK_REG = 0;
        for (r = q; r < last; r++) row_palettes(r, pal + r * 32);
        if (q == 0) load_row0();
    }
}

void screen_text(uint8_t x, uint8_t y, const char *s) {
    uint8_t t[20], n = 0;
    while (*s && x + n < 20) {
        char c = *s++;
        if (c >= 'a' && c <= 'z') c -= 32;
        t[n++] = (c >= 0x20 && c < 0x60) ? FONT_BASE + (c - 0x20) : FONT_BASE;
    }
    set_bkg_tiles(x, y, n, 1, t);
}

void screen_number(uint8_t x, uint8_t y, uint16_t v, uint8_t digits) {
    char b[6];
    uint8_t i;
    b[digits] = 0;
    for (i = digits; i > 0; i--) {
        b[i - 1] = '0' + v % 10;
        v /= 10;
    }
    screen_text(x, y, b);
}

void screen_init(void) {
    static const uint8_t zero[16] = {0};
    uint8_t x, y, row[20];
    DISPLAY_OFF;
    LCDC_REG &= ~LCDCF_BG8000;            // 8800h addressing
    set_bkg_data(FONT_BASE, 64, font_tiles);
    set_bkg_data(BLANK_TILE, 1, zero);
    fill_bkg_rect(0, 0, 20, 18, BLANK_TILE);
    VBK_REG = 1;
    fill_bkg_rect(0, 0, 20, 18, 0);
    for (y = 0; y < NROW; y++) {
        // the sides of a picture row: the row's first palette
        row[0] = row[1] = row[18] = row[19] = (y & 1) ? 4 : 0;
        for (x = 0; x < 16; x++) row[2 + x] = 0x08 | ((y & 1) ? 4 : 0);
        set_bkg_tiles(0, 1 + y, 20, 1, row);
    }
    VBK_REG = 0;
    for (y = 0; y < NROW; y++) {
        for (x = 0; x < 16; x++) row[x] = y * 16 + x;
        set_bkg_tiles(2, 1 + y, 16, 1, row);
    }
    // palettes: text everywhere until a picture comes
    for (y = 0; y < 8; y++) {
        pal_cmd_t *e = &stream[(NROW - 1) * 8 + y];   // during the last row: palettes 0-3 for the text
        e->bcps = 0x80 | (y * 4);
        memcpy(e->d, (const uint8_t *)ui_pal + y * 4, 4);
    }
    for (y = 0; y < NROW; y++) row_palettes(y, (const uint8_t *)ui_pal);
    set_bkg_palette(0, 4, ui_pal);
    set_bkg_palette(4, 4, ui_pal);
    pal_ptr = stream;
    CRITICAL {
        add_VBL(vbl);
    }
    STAT_REG = STATF_MODE00;
    set_interrupts(VBL_IFLAG | LCD_IFLAG);
    SHOW_BKG;
    DISPLAY_ON;
}
