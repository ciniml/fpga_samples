// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
#ifndef SOUND_H
#define SOUND_H
void sound_init(void);
void sound_blip(void);      // a menu move
void sound_ok(void);        // a choice
void sound_beep(void);      // the self-timer
void sound_shutter(void);   // the shutter (two clicks, ~0.1 s)
void sound_saved(void);     // a picture kept (~0.2 s)
#endif
