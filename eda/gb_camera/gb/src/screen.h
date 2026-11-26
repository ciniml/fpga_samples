// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// The screen: a 128x112 picture at tile (2, 1) with 4 palettes of its own for every tile row, text
// in rows 15-17.
#ifndef SCREEN_H
#define SCREEN_H
#include <stdint.h>

#define PIC_TILES 0x0E00u                 // 224 tiles of 16 bytes
#define PIC_ATTR  224u                    // a BG attribute per tile
#define PIC_PAL   448u                    // 14 rows x 4 palettes x 4 colours, RGB555

void screen_init(void);
// a picture to the screen over 5 frames, the tile rows switched with their palettes and attributes
// (tiles: an address in cart RAM or WRAM, 16-byte aligned)
void screen_picture(uint16_t tiles, const uint8_t *attr, const uint8_t *pal);
void screen_text(uint8_t x, uint8_t y, const char *s);
void screen_number(uint8_t x, uint8_t y, uint16_t v, uint8_t digits);
#endif
