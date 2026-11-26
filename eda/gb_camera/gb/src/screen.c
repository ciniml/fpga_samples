// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// The screen: a bar at the top (row 0), the 128x112 picture at tile (2, 1) between two film strips
// (sprites), text in rows 15-17.
//
// The picture's tiles are tiles 0-223 of VRAM bank 1 (8800h addressing: tiles 0-127 at 9000h,
// 128-223 at 8800h). Even tile rows use BG palettes 0-3, odd rows 4-7: the HBlank after each line
// of the tile row above (the bar for row 0) writes 4 bytes of the row's palettes into its half (the
// STAT interrupt, mode 0, a stream of 120 commands prepared here). VBlank loads the text palettes
// into 0-3; during the last picture row they come back for rows 15-17. The bar uses palette 3, the
// last one row 0's palettes overwrite (colours 0 and 1 change after its line 6: the bar's tiles
// use colours 2 and 3 only on line 7).
// VRAM bank 0: the bar font (colour 2 on 3) at BG tiles 0-63, a bar tile (64), the text font (3 on
// 0) at 128-191, a blank tile (192); the sprites' tiles at 8000h.
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gb/hardware.h>
#include <gb/isr.h>
#include <string.h>
#include "screen.h"

extern const uint8_t font_tiles[64 * 16];

#define BAR_FONT   0u
#define BAR_TILE   64u
#define FONT_BASE  128u
#define BLANK_TILE 192u
#define NROW       14u
#define NCMD       120u                   // lines 0..119
#define FRAME_SPR  0u                     // sprites 0-27: the film strips
#define CURSOR_SPR 28u

typedef struct {
    uint8_t bcps;
    uint8_t d[4];
} pal_cmd_t;

static pal_cmd_t stream[NCMD];
pal_cmd_t *pal_ptr;                       // the STAT interrupt's next command

// palettes 0-3 outside the picture: text, accent, selected, the bar
static const palette_color_t ui_pal[16] = {
    RGB(31, 31, 31), RGB(22, 22, 22), RGB(12, 12, 12), RGB(2, 2, 4),       // 0 text: black on white
    RGB(31, 29, 22), RGB(28, 22, 12), RGB(18, 10, 4), RGB(10, 4, 2),        // 1 accent: brown on cream
    RGB(4, 8, 20), RGB(10, 14, 26), RGB(20, 22, 30), RGB(31, 31, 20),       // 2 selected: yellow on navy
    RGB(31, 31, 31), RGB(20, 20, 20), RGB(31, 31, 31), RGB(6, 8, 12),       // 3 bar: white (2) on slate (3)
};
static const palette_color_t spr_pal[4] = {
    RGB(0, 0, 0), RGB(30, 30, 28), RGB(9, 9, 10), RGB(1, 1, 2),           // film: holes, edge, black
};

// sprite tiles (8x16 pairs): film edge with holes, film band, cursor
static const uint8_t spr_tiles[] = {
    // 0, 1: the edge: black (3) with a 4x4 hole (1) in each half
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xC3, 0xFF, 0xFF, 0xFF, 0xFF,
    // 2, 3: the band: black with a grey (2) line next to the picture
    0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF,
    0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF, 0x01, 0xFF,
    // 4, 5: the band of the right side (grey line on its left)
    0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF,
    0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF, 0x80, 0xFF,
    // 6, 7: the cursor, a black arrow in the upper half
    0x00, 0x00, 0x40, 0x40, 0x60, 0x60, 0x70, 0x70, 0x78, 0x78, 0x70, 0x70, 0x60, 0x60, 0x40, 0x40,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

// HBlank of lines 0..119: one palette command (BCPS, then 4 bytes of BCPD)
void stat_isr(void) NAKED {
    __asm
    push af
    push hl
    ldh a, (_LY_REG)
    cp a, #120
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

// the text palettes into palettes 0-3 (VBlank; unrolled)
static void load_ui(void) NAKED {
    __asm
    ld hl, #_ui_pal
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
    load_ui();
}

// the 4 palettes (32 bytes) written while the lines above tile row t are shown (t = 14: the text)
static void row_palettes(uint8_t t, const uint8_t *p) {
    uint8_t c;
    for (c = 0; c < 8; c++) {
        pal_cmd_t *e = &stream[t * 8 + c];
        e->bcps = 0x80 | ((t & 1) ? 32 : 0) | (c * 4);
        memcpy(e->d, p + c * 4, 4);
    }
}

// n blocks of 16 bytes from src to VRAM at dst (in VBlank)
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

void (*screen_poll)(void);

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
        if (screen_poll) screen_poll();
    }
}

void screen_text_pal(uint8_t x, uint8_t y, const char *s, uint8_t pal) {
    uint8_t t[20], a[20], n = 0, base = y == 0 ? BAR_FONT : FONT_BASE;
    if (y == 0) pal = 3;
    while (*s && x + n < 20) {
        char c = *s++;
        if (c >= 'a' && c <= 'z') c -= 32;
        t[n] = base + ((c >= 0x20 && c < 0x60) ? c - 0x20 : 0);
        a[n++] = pal;
    }
    set_bkg_tiles(x, y, n, 1, t);
    VBK_REG = 1;
    set_bkg_tiles(x, y, n, 1, a);
    VBK_REG = 0;
}

void screen_text(uint8_t x, uint8_t y, const char *s) { screen_text_pal(x, y, s, 0); }

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

void screen_clear_text(void) {
    fill_bkg_rect(0, 15, 20, 3, BLANK_TILE);
    VBK_REG = 1;
    fill_bkg_rect(0, 15, 20, 3, 0);
    VBK_REG = 0;
    fill_bkg_rect(0, 0, 20, 1, BAR_TILE);
}

void screen_frame(uint8_t on) {
    uint8_t i;
    for (i = 0; i < 28; i++) {
        uint8_t col = i / 7, k = i % 7;
        static const uint8_t xs[4] = {0, 8, 144, 152};
        move_sprite(FRAME_SPR + i, on ? xs[col] + 8 : 0, on ? 8 + k * 16 + 16 : 0);
    }
}

void screen_cursor(uint8_t x, uint8_t y, uint8_t on) {
    move_sprite(CURSOR_SPR, on ? x * 8 + 8 : 0, on ? y * 8 + 16 : 0);
}

void screen_flash(void) {
    DISPLAY_OFF;                          // a white screen on the CGB
    delay(60);
    DISPLAY_ON;
}

void screen_init(void) {
    static const uint8_t zero[16] = {0};
    static const uint8_t bar[16] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    uint8_t x, y, row[20], t[16 * 8];
    DISPLAY_OFF;
    LCDC_REG &= ~LCDCF_BG8000;            // 8800h addressing
    set_bkg_data(FONT_BASE, 64, font_tiles);
    // the bar font: glyph pixels colour 2 (hi 1, lo 0) on colour 3
    for (y = 0; y < 8; y++) {
        for (x = 0; x < 16 * 8; x += 2) {
            uint8_t b = font_tiles[y * 128 + x];
            t[x] = ~b;
            t[x + 1] = 0xFF;
        }
        set_bkg_data(BAR_FONT + y * 8, 8, t);
    }
    set_bkg_data(BAR_TILE, 1, bar);
    set_bkg_data(BLANK_TILE, 1, zero);
    fill_bkg_rect(0, 0, 20, 18, BLANK_TILE);
    fill_bkg_rect(0, 0, 20, 1, BAR_TILE);
    VBK_REG = 1;
    fill_bkg_rect(0, 0, 20, 18, 0);
    fill_bkg_rect(0, 0, 20, 1, 3);
    for (y = 0; y < NROW; y++) {
        // the sides of a picture row (under the film strips): the row's first palette
        row[0] = row[1] = row[18] = row[19] = (y & 1) ? 4 : 0;
        for (x = 0; x < 16; x++) row[2 + x] = 0x08 | ((y & 1) ? 4 : 0);
        set_bkg_tiles(0, 1 + y, 20, 1, row);
    }
    VBK_REG = 0;
    for (y = 0; y < NROW; y++) {
        for (x = 0; x < 16; x++) row[x] = y * 16 + x;
        set_bkg_tiles(2, 1 + y, 16, 1, row);
    }
    // sprites: 8x16, the film strips and the cursor
    SPRITES_8x16;
    set_sprite_data(0, 8, spr_tiles);
    set_sprite_palette(0, 1, spr_pal);
    for (x = 0; x < 28; x++) {
        uint8_t col = x / 7;
        set_sprite_tile(FRAME_SPR + x, col == 0 || col == 3 ? 0 : col == 1 ? 2 : 4);
        set_sprite_prop(FRAME_SPR + x, 0);
    }
    set_sprite_tile(CURSOR_SPR, 6);
    set_sprite_prop(CURSOR_SPR, 0);
    screen_cursor(0, 0, 0);
    screen_frame(0);
    // palettes: the text everywhere until a picture comes
    for (y = 0; y <= NROW; y++) row_palettes(y, (const uint8_t *)ui_pal);
    set_bkg_palette(0, 4, ui_pal);
    set_bkg_palette(4, 4, ui_pal);
    pal_ptr = stream;
    CRITICAL {
        add_VBL(vbl);
    }
    STAT_REG = STATF_MODE00;
    set_interrupts(VBL_IFLAG | LCD_IFLAG);
    SHOW_BKG;
    SHOW_SPRITES;
    DISPLAY_ON;
}
