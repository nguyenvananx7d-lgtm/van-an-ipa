//
//  ghost_channel.h — settings over loopback, no file.
//

#ifndef GHOST_CHANNEL_H
#define GHOST_CHANNEL_H

#include "ghost.h"

/* Open (or re-open) the loopback connection. Called lazily by the poll, so a
   payload that starts before the app is listening simply retries. */
int ghost_channel_open(int port);

/* Non-blocking read. Returns 1 when a new, CRC-valid frame was applied. */
int ghost_channel_poll(ghost_settings_t *out);

/* Poll at most every 200 ms. Safe to call from both the GUI and the aim tick. */
void ghost_channel_tick(void);

/* Last known settings, always valid (defaults are installed at start). */
const ghost_settings_t *ghost_channel_current(void);

/* Seed the defaults the payload uses when no app is attached. */
void ghost_channel_defaults(void);

/* Flip flag bits on the live settings in place. The in-game menu uses this;
   the next app push replaces the flags wholesale. */
void ghost_channel_patch_flags(uint32_t set, uint32_t clear);

/* Receive the floating-icon image (RGBA8, top-left origin). The handler runs
   on the main queue when a 'GHIM' frame arrives. */
void ghost_channel_set_image_handler(void (*handler)(const uint8_t *rgba,
                                                     int width, int height));

#endif /* GHOST_CHANNEL_H */
