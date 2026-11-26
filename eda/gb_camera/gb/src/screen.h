// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// The screen: a bar at the top (row 0), a 128x112 picture at tile (2, 1) with 4 palettes of its own
// for every tile row, film strips on its sides (sprites), text in rows 15-17.
#ifndef SCREEN_H
#define SCREEN_H
#include <stdint.h>

#define PIC_TILES 0x0E00u                 // 224 tiles of 16 bytes
#define PIC_ATTR  224u                    // a BG attribute per tile
#define PIC_PAL   448u                    // 14 rows x 4 palettes x 4 colours, RGB555

// text palettes (rows 15-17): 0 black on white, 1 brown on cream, 2 yellow on navy (selected)
#define TXT_NORMAL   0u
#define TXT_ACCENT   1u
#define TXT_SELECTED 2u

void screen_init(void);
// a picture to the screen over 14 frames (a tile row a VBlank), each row with its palettes and
// attributes (tiles: an address in cart RAM, WRAM or ROM, 16-byte aligned)
void screen_picture(uint16_t tiles, const uint8_t *attr, const uint8_t *pal);
extern void (*screen_poll)(void);         // called once a frame by screen_picture (the buttons)
// text in row 0 (the bar) or rows 15-17
void screen_text(uint8_t x, uint8_t y, const char *s);
void screen_text_pal(uint8_t x, uint8_t y, const char *s, uint8_t pal);
void screen_number(uint8_t x, uint8_t y, uint16_t v, uint8_t digits);
void screen_clear_text(void);              // the bar and rows 15-17
void screen_frame(uint8_t on);             // the film strips
void screen_cursor(uint8_t x, uint8_t y, uint8_t on);   // an arrow at tile (x, y)
void screen_flash(void);                   // the shutter: a white screen for a moment
#endif
