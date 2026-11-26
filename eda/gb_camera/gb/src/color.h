// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Colour for the camera pictures: the camera's tile colours (RAM bank 0, 0xAF00 R / 0xB000 G /
// 0xB100 B, 16x14 tiles) -> a palette 1..7 for every tile and the 7 palettes.
#ifndef COLOR_H
#define COLOR_H
#include <gb/cgb.h>
#include <stdint.h>

#define NTILE 224
#define NPAL 7                           // palettes 1..7 (0 is the screen's own)
extern uint8_t col_attr[NTILE];          // BG attributes of the picture (tile bank 1 + palette)
extern palette_color_t col_pal[NPAL * 4];

void color_compute(void);                // RAM bank 0 selected
void color_grey(void);                   // all tiles grey
void color_apply(void);                  // to the screen (picture at (2, 1))
#endif
