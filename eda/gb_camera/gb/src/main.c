// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// A pocket camera for the Game Boy Camera style cartridge of eda/gb_camera (GameCart mapper 6 +
// GbCamera): a title with SHOOT / VIEW, the viewfinder (shutter, self-timer, keep), the album.
//
// The camera as the Game Boy Camera's: RAM bank 10h maps its registers at 0xA000; writing 1 to
// 0xA000 shoots, 0xA000 bit 0 reads 1 until the 128x112 picture (16x14 tiles, 2 bpp) is in RAM
// bank 0 at 0xA100. Colour (register 36h bit 0, not in the Game Boy Camera): the tiles hold colour
// indices, 0xAF00 the BG attribute of every tile and 0xB000 the 4 palettes of every tile row
// (screen.c switches them row by row). Black and white: the Game Boy Camera's processing
// (exposure, contrast as dither thresholds) with grey palettes.
//
// Viewfinder:  A shutter    START self-timer    SELECT colour / black and white    B back
//              UP/DOWN brightness (colour: the palettes; black and white: exposure)
//              LEFT/RIGHT contrast (black and white)
// Album:       LEFT/RIGHT pictures    A delete    B back
// The album: 3 pictures in RAM banks 1-3 (tiles, attributes, palettes), which ones are used at
// 0xBF00 of RAM bank 0 (kept while the cartridge's FPGA is powered).
//
// DEMO (make demo): no camera; the picture of build/demo_data.c (gb_color_ref.py) instead.
#include <gb/gb.h>
#include <gb/cgb.h>
#include <gb/hardware.h>
#include <stdint.h>
#include <string.h>
#include "screen.h"
#include "sound.h"

#define CAM ((volatile uint8_t *)0xA000)
#define NSLOT 3
#define KEEP_TILES 0xA000u                // a kept picture in RAM bank 1 + slot
#define KEEP_ATTR  ((uint8_t *)0xAE00)
#define KEEP_PAL   ((uint8_t *)0xAF00)
#define ALBUM      ((uint8_t *)0xBF00)    // RAM bank 0: 'G', 'C', the slots used

static uint8_t colour = 1;
static int8_t bright = 0;                 // -4..4
static uint16_t exposure = 0x1000;
static uint8_t contrast = 6;              // 0..15
static uint8_t used;                      // album slots in use (bits)
static uint8_t pad, latch;

static uint8_t attr[PIC_ATTR];
static uint8_t pal[PIC_PAL];
static uint8_t raw_buf[PIC_TILES + 16];   // 16-byte aligned through buf
static uint8_t *buf;

static const uint8_t bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
static const uint16_t grey[4] = {RGB(31, 31, 31), RGB(21, 21, 21), RGB(10, 10, 10), RGB(0, 0, 0)};

extern const uint8_t title_tiles[PIC_TILES];
extern const uint8_t title_attr[PIC_ATTR];
extern const uint8_t title_pal[PIC_PAL];
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

// the next button pressed
static uint8_t wait_key(void) {
    uint8_t k;
    latch = 0;
    do {
        wait_vbl_done();
        sample();
        k = latch;
    } while (!k);
    latch = 0;
    return k;
}

static uint8_t count_used(void) {
    uint8_t s, n = 0;
    for (s = 0; s < NSLOT; s++) n += (used >> s) & 1;
    return n;
}

static void album_load(void) {
    SWITCH_RAM(0);
    if (ALBUM[0] != 'G' || ALBUM[1] != 'C') {
        ALBUM[0] = 'G';
        ALBUM[1] = 'C';
        ALBUM[2] = 0;
    }
    used = ALBUM[2] & ((1 << NSLOT) - 1);
}

static void album_save(void) {
    SWITCH_RAM(0);
    ALBUM[2] = used;
}

// registers 1-4, the thresholds 6-53 and colour (RAM bank 10h selected)
static void set_registers(void) {
    uint8_t i, lev;
    int16_t span = 16 + contrast * 7;
    int16_t lo = 128 - span, hi = 128 + span;
    if (lo < 0) lo = 0;
    if (hi > 255) hi = 255;
    CAM[1] = 0x04;
    CAM[2] = exposure >> 8;
    CAM[3] = exposure & 0xFF;
    CAM[4] = 0x20;
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

// a picture from ROM (16-byte alignment through buf)
static void show_rom(const uint8_t *tiles, const uint8_t *a, const uint8_t *p) {
    memcpy(buf, tiles, PIC_TILES);
    screen_picture((uint16_t)buf, a, p);
}

// one shot of the viewfinder to the screen
static void shoot(void) {
#ifdef DEMO
    if (colour) {
        memcpy(attr, demo_attr, PIC_ATTR);
        memcpy(pal, demo_pal, PIC_PAL);
        brighten();
    } else {
        grey_tables();
    }
    sample();
    show_rom(demo_tiles, attr, pal);
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

// ---- the viewfinder ----

static void shoot_status(void) {
    screen_clear_text();
    screen_text(1, 0, colour ? "COLOR" : "B&W");
    screen_text(11, 0, "PHOTO");
    screen_number(17, 0, count_used(), 1);
    screen_text(18, 0, "/3");
    if (colour) {
        screen_text(1, 15, "BRIGHT");
        screen_text(8, 15, bright < 0 ? "-" : "+");
        screen_number(9, 15, bright < 0 ? -bright : bright, 1);
    } else {
        screen_text(1, 15, "EXP");
        screen_number(5, 15, exposure >> 8, 3);
        screen_text(10, 15, "CON");
        screen_number(14, 15, contrast, 2);
    }
    screen_text_pal(1, 16, "A SHOT  START TIMER", TXT_ACCENT);
    screen_text_pal(1, 17, "SEL COLOR  B BACK  ", TXT_ACCENT);
}

// keep the picture on the screen (the last shot) in a free slot
static uint8_t keep(void) {
    uint8_t s;
    for (s = 0; s < NSLOT && ((used >> s) & 1); s++) {
    }
    if (s == NSLOT) return 0;
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
    used |= 1 << s;
    album_save();
    return 1;
}

// the shutter: sound and flash, then keep the picture or not
static void take(void) {
    uint8_t k;
    sound_shutter();
    screen_flash();
    screen_clear_text();
    screen_text(1, 0, "SHOT!");
    if (count_used() == NSLOT) {
        screen_text(1, 15, "THE ALBUM IS FULL");
        screen_text_pal(1, 17, "ANY KEY", TXT_ACCENT);
        wait_key();
        return;
    }
    screen_text(1, 15, "KEEP THIS PICTURE?");
    screen_text_pal(1, 17, "A YES     B NO", TXT_ACCENT);
    do {
        k = wait_key();
    } while (!(k & (J_A | J_B)));
    if (k & J_A) {
        keep();
        sound_saved();
        screen_text(1, 15, "KEPT IN THE ALBUM ");
        delay(600);
    } else {
        sound_blip();
    }
}

static void shoot_mode(void) {
    uint8_t timer = 0;
    uint16_t t0 = 0;
    shoot_status();
    latch = 0;
    for (;;) {
        shoot();
        if (timer) {
            // the self-timer: a beep a second, the shutter after 3
            if ((uint16_t)(sys_time - t0) >= 60) {
                t0 = sys_time;
                timer--;
                if (timer == 0) {
                    take();
                    shoot_status();
                    latch = 0;
                    continue;
                }
                sound_beep();
                screen_number(12, 0, timer, 1);
            }
            if (pressed(J_B)) {
                timer = 0;
                shoot_status();
            }
            latch = 0;
            continue;
        }
        if (pressed(J_B)) {
            sound_blip();
            return;
        }
        if (pressed(J_A)) {
            take();
            shoot_status();
            latch = 0;
            continue;
        }
        if (pressed(J_START)) {
            timer = 4;
            t0 = sys_time - 60;
            screen_text(1, 0, "TIMER      ");
            latch = 0;
            continue;
        }
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
        if (latch) {
            sound_blip();
            shoot_status();
        }
        latch = 0;
    }
}

// ---- the album ----

static void view_mode(void) {
    uint8_t s = 0, k;
    screen_clear_text();
    for (;;) {
        uint8_t n = count_used(), i, idx = 0;
        screen_clear_text();
        if (n == 0) {
            screen_text(1, 0, "ALBUM");
            screen_text(1, 15, "NO PICTURES YET");
            screen_text_pal(1, 17, "B BACK", TXT_ACCENT);
            do {
                k = wait_key();
            } while (!(k & J_B));
            sound_blip();
            return;
        }
        while (!((used >> s) & 1)) s = (s + 1) % NSLOT;
        for (i = 0; i < s; i++) idx += (used >> i) & 1;
        screen_text(1, 0, "ALBUM");
        screen_number(14, 0, idx + 1, 1);
        screen_text(15, 0, "/");
        screen_number(16, 0, n, 1);
        screen_text_pal(1, 16, "LEFT RIGHT A DELETE", TXT_ACCENT);
        screen_text_pal(1, 17, "B BACK", TXT_ACCENT);
        SWITCH_RAM(1 + s);
        memcpy(attr, KEEP_ATTR, PIC_ATTR);
        memcpy(pal, KEEP_PAL, PIC_PAL);
        screen_picture(KEEP_TILES, attr, pal);
        k = wait_key();
        if (k & J_B) {
            sound_blip();
            return;
        }
        if (k & (J_RIGHT | J_LEFT)) {
            sound_blip();
            do {
                s = (k & J_RIGHT) ? (s + 1) % NSLOT : (s + NSLOT - 1) % NSLOT;
            } while (!((used >> s) & 1));
        } else if (k & J_A) {
            screen_text(1, 15, "DELETE THIS ONE?");
            screen_text_pal(1, 16, "                   ", TXT_ACCENT);
            screen_text_pal(1, 17, "A YES     B NO", TXT_ACCENT);
            do {
                k = wait_key();
            } while (!(k & (J_A | J_B)));
            if (k & J_A) {
                used &= ~(1 << s);
                album_save();
                sound_ok();
            } else {
                sound_blip();
            }
        }
    }
}

// ---- the title ----

static uint8_t title(void) {
    uint8_t sel = 0, k;
    screen_clear_text();
    screen_text(1, 0, "GB CAMERA");
    show_rom(title_tiles, title_attr, title_pal);
    for (;;) {
        screen_text_pal(3, 16, " SHOOT ", sel == 0 ? TXT_SELECTED : TXT_NORMAL);
        screen_text_pal(11, 16, " VIEW ", sel == 1 ? TXT_SELECTED : TXT_NORMAL);
        screen_cursor(sel == 0 ? 2 : 10, 16, 1);
        k = wait_key();
        if (k & (J_LEFT | J_RIGHT | J_SELECT)) {
            sel ^= 1;
            sound_blip();
        } else if (k & (J_A | J_START)) {
            sound_ok();
            screen_cursor(0, 0, 0);
            return sel;
        }
    }
}

void main(void) {
    cpu_fast();
    ENABLE_RAM;
    buf = (uint8_t *)(((uint16_t)raw_buf + 15) & 0xFFF0);
    sound_init();
    screen_init();
    screen_poll = sample;
    screen_frame(1);
    album_load();
    for (;;) {
        if (title() == 0) shoot_mode();
        else view_mode();
    }
}
