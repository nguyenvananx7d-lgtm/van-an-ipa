//
//  ghost_esp.h — the OnGUI replacement.
//

#ifndef GHOST_ESP_H
#define GHOST_ESP_H

#include "ghost_il2cpp.h"

/* Create the driver GameObject and hook SceneEditBoxSelectTool.OnGUI.
   Must run on Unity's main thread. Returns 1 when the hook is live, 0 when it
   is too early (the caller retries). */
int ghost_esp_install(void);

/* Draw one frame: the FOV ring when the assist is armed, then the ESP layer
   when its flag is set. */
void ghost_esp_draw(void);

/* True once the hook is installed. */
int ghost_esp_ready(void);

/* Shared draw primitives, also used by the in-game menu. */
void ghost_draw_fill(GhostRect rect, GhostColor color);
void ghost_draw_label(GhostRect rect, const char *text, GhostColor color,
                      int fontSize);
void ghost_draw_ensure_style(void);

#endif /* GHOST_ESP_H */
