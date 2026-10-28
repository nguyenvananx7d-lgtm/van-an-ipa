//
//  ghost_menu.h — floating icon + in-game toggle panel.
//
//  The icon sits over the game, drawn from the OnGUI driver. A tap opens the
//  panel; each row flips one flag on the live settings in place, so the change
//  is visible on the next frame. The next app push replaces the flags.
//

#ifndef GHOST_MENU_H
#define GHOST_MENU_H

#include <stdint.h>

/* One frame: draw the icon and the panel. Main thread (Repaint). */
void ghost_menu_frame(void);

/* Handle a tap at the current IMGUI mouse position. Called from the OnGUI
   replacement on MouseDown events. */
void ghost_menu_tap(void);

/* Image receiver for the channel's 'GHIM' frames. Safe to call from the poll
   thread; the texture is built on the main queue. */
void ghost_menu_on_image(const uint8_t *rgba, int width, int height);

#endif /* GHOST_MENU_H */
