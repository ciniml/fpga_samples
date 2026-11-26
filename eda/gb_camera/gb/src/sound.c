// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Short effects on channel 1 (square) and channel 4 (noise).
#include <gb/gb.h>
#include <gb/hardware.h>
#include "sound.h"

void sound_init(void) {
    NR52_REG = 0x80;                      // on
    NR50_REG = 0x77;
    NR51_REG = 0xFF;
}

// channel 1: frequency x (f = 131072 / (2048 - x) Hz), envelope env
static void tone(uint16_t x, uint8_t env, uint8_t duty) {
    NR10_REG = 0x00;
    NR11_REG = duty;
    NR12_REG = env;
    NR13_REG = x & 0xFF;
    NR14_REG = 0x80 | (x >> 8);
}

static void noise(uint8_t env, uint8_t poly) {
    NR41_REG = 0x00;
    NR42_REG = env;
    NR43_REG = poly;
    NR44_REG = 0x80;
}

void sound_blip(void) { tone(1899, 0xA1, 0x80); }     // ~880 Hz, short
void sound_ok(void) { tone(1923, 0xC2, 0x80); }       // ~1047 Hz
void sound_beep(void) { tone(1985, 0xF2, 0x40); }     // ~2 kHz

void sound_shutter(void) {
    noise(0xF1, 0x31);                    // the shutter opening
    delay(60);
    noise(0xC1, 0x22);                    // and closing
}

void sound_saved(void) {
    tone(1798, 0xB1, 0x80);               // ~524 Hz, then ~659 Hz: two notes up
    delay(90);
    tone(1849, 0xC3, 0x80);
}
