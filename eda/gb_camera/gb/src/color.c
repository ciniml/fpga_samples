// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Grey-world white balance, then every tile into grey or one of six hues (red, yellow, green,
// cyan, blue, magenta), and for each class a palette from white to black through the mean colour
// of its tiles (saturation x1.5 below the lightest shade).
#include <gb/gb.h>
#include <string.h>
#include "color.h"

uint8_t col_attr[NTILE];
palette_color_t col_pal[NPAL * 4];

static uint16_t gr = 256, gb = 256;      // white balance gains, 8.8, smoothed over the shots
static uint16_t cs[NPAL][3];
static uint8_t cn[NPAL];
static const uint8_t lum[4] = {240, 165, 90, 20};   // the shades, colour 0 (lightest) .. 3

static uint8_t clamp8(int32_t v) { return v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v; }

void color_compute(void) {
    const uint8_t *pr = (const uint8_t *)0xAF00, *pg = (const uint8_t *)0xB000, *pb = (const uint8_t *)0xB100;
    uint16_t sr = 0, sg = 0, sb = 0;
    uint8_t t, c, k;
    for (t = 0; t < NTILE; t++) {
        sr += pr[t];
        sg += pg[t];
        sb += pb[t];
    }
    if (sr > 224 && sb > 224) {
        uint32_t nr = ((uint32_t)sg << 8) / sr, nb = ((uint32_t)sg << 8) / sb;
        if (nr > 1024) nr = 1024;
        if (nb > 1024) nb = 1024;
        if (nr < 64) nr = 64;
        if (nb < 64) nb = 64;
        gr = (uint16_t)((gr * 3u + nr) >> 2);
        gb = (uint16_t)((gb * 3u + nb) >> 2);
    }
    memset(cs, 0, sizeof cs);
    memset(cn, 0, sizeof cn);
    for (t = 0; t < NTILE; t++) {
        // (gains up to 4.0: 255 * (1024 >> 2) still fits 16 bits)
        uint16_t r16 = ((uint16_t)pr[t] * (gr >> 2)) >> 6, b16 = ((uint16_t)pb[t] * (gb >> 2)) >> 6;
        uint8_t r = r16 > 255 ? 255 : r16, g = pg[t], b = b16 > 255 ? 255 : b16;
        uint8_t mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        uint8_t mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
        uint8_t sat = mx - mn;
        int16_t d;
        if (sat < 12 || (uint16_t)sat * 3 < mx) {
            c = 0;
        } else if (mx == r) {
            d = (int16_t)g - b;
            c = 2 * d >= sat ? 2 : 2 * d <= -(int16_t)sat ? 6 : 1;
        } else if (mx == g) {
            d = (int16_t)b - r;
            c = 2 * d >= sat ? 4 : 2 * d <= -(int16_t)sat ? 2 : 3;
        } else {
            d = (int16_t)r - g;
            c = 2 * d >= sat ? 6 : 2 * d <= -(int16_t)sat ? 4 : 5;
        }
        col_attr[t] = 0x08 | (1 + c);
        cs[c][0] += r;
        cs[c][1] += g;
        cs[c][2] += b;
        cn[c]++;
    }
    for (c = 0; c < NPAL; c++) {
        uint16_t m[3], l;
        if (c == 0 || cn[c] == 0) {
            m[0] = m[1] = m[2] = 128;
        } else {
            m[0] = cs[c][0] / cn[c];
            m[1] = cs[c][1] / cn[c];
            m[2] = cs[c][2] / cn[c];
        }
        l = (m[0] + 2 * m[1] + m[2]) >> 2;
        if (l == 0) l = 1;
        for (k = 0; k < 4; k++) {
            uint8_t v[3], ch;
            for (ch = 0; ch < 3; ch++) {
                int32_t s = (int32_t)m[ch] * lum[k] / l;            // the mean colour at this shade
                int32_t e = k == 0 ? s : lum[k] + (s - lum[k]) * 3 / 2;
                v[ch] = clamp8(e);
            }
            col_pal[c * 4 + k] = RGB(v[0] >> 3, v[1] >> 3, v[2] >> 3);
        }
    }
}

void color_grey(void) {
    uint8_t t, c, k;
    for (t = 0; t < NTILE; t++) col_attr[t] = 0x09;
    for (c = 0; c < NPAL; c++)
        for (k = 0; k < 4; k++) col_pal[c * 4 + k] = RGB(lum[k] >> 3, lum[k] >> 3, lum[k] >> 3);
}

void color_apply(void) {
    wait_vbl_done();
    set_bkg_palette(1, NPAL, col_pal);
    VBK_REG = 1;
    set_bkg_tiles(2, 1, 16, 14, col_attr);
    VBK_REG = 0;
}
