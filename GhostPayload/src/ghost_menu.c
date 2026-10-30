//
//  ghost_menu.c — the floating icon and its toggle panel.
//
//  Everything is drawn with the same GUI primitives as the ESP (no second
//  renderer), and the icon texture is the logo the app ships over the channel
//  as a 'GHIM' frame. Taps are read through the shared touch probe in
//  ghost_game.c, so the menu works under both input stacks.
//

#include "ghost_menu.h"
#include "ghost_channel.h"
#include "ghost_esp.h"
#include "ghost_game.h"

#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *label; uint32_t flag; } MenuRow;

static const MenuRow rows[] = {
    { "ESP",          GHOST_FLAG_ESP },
    { "Box",          GHOST_FLAG_BOX },
    { "Name",         GHOST_FLAG_NAME },
    { "Distance",     GHOST_FLAG_DISTANCE },
    { "Health",       GHOST_FLAG_HEALTH },
    { "Tracer",       GHOST_FLAG_TRACER },
    { "FOV ring",     GHOST_FLAG_FOV_RING },
    { "Aim",          GHOST_FLAG_AIM },
    { "Aim visible",  GHOST_FLAG_AIM_VISIBLE },
    { "Aim knocked",  GHOST_FLAG_AIM_KNOCKED },
    { "Aim touch",    GHOST_FLAG_AIM_TOUCH },
};
#define MENU_ROWS ((int)(sizeof(rows) / sizeof(rows[0])))

static int menuOpen = 1;
static Il2CppObject *iconTexture;
static float iconX = -1.0f, iconY = -1.0f;
static float iconSize, panelW, rowH, titleH;
static float lastScreenW, lastScreenH;

static const float palette[8][3] = {
    { 0.36f, 0.95f, 0.76f }, /* mint   */
    { 0.49f, 0.83f, 1.00f }, /* ice    */
    { 1.00f, 0.44f, 0.68f }, /* rose   */
    { 1.00f, 0.78f, 0.34f }, /* amber  */
    { 0.72f, 0.61f, 1.00f }, /* violet */
    { 1.00f, 0.36f, 0.37f }, /* red    */
    { 0.94f, 0.96f, 0.98f }, /* white  */
    { 0.66f, 1.00f, 0.38f }, /* lime   */
};

static GhostColor rgba(float r, float g, float b, float a) {
    GhostColor c = { r, g, b, a };
    return c;
}

static GhostColor accentColor(float alpha) {
    const ghost_settings_t *s = ghost_channel_current();
    const float *p = palette[s->palette & 7];
    return rgba(p[0], p[1], p[2], alpha);
}

static float clampf(float value, float low, float high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static float uiScale(float screenH) {
    float ui = screenH / 900.0f;
    if (ui < 0.75f) ui = 0.75f;
    if (ui > 1.6f) ui = 1.6f;
    return ui;
}

static void layout(float screenW, float screenH) {
    float ui = uiScale(screenH);
    iconSize = 58.0f * ui;
    panelW = 196.0f * ui;
    rowH = 29.0f * ui;
    titleH = 44.0f * ui;

    if (iconX < 0.0f || lastScreenW != screenW || lastScreenH != screenH) {
        iconX = screenW - iconSize - 14.0f * ui;
        iconY = screenH * 0.42f;
        lastScreenW = screenW;
        lastScreenH = screenH;
    }
    iconX = clampf(iconX, 0.0f, screenW - iconSize);
    iconY = clampf(iconY, 0.0f, screenH - iconSize);
}

static GhostRect icon_rect(void) {
    GhostRect r = { iconX, iconY, iconSize, iconSize };
    return r;
}

static GhostRect row_rect(int index, float screenH) {
    float ui = uiScale(screenH);
    float panelX = iconX - panelW - 8.0f * ui;
    if (panelX < 2.0f * ui) panelX = 2.0f * ui;
    GhostRect r = {
        panelX + 5.0f * ui,
        iconY + titleH + (float)index * rowH,
        panelW - 10.0f * ui,
        rowH - 3.0f * ui,
    };
    return r;
}

static int in_rect(float x, float y, GhostRect r) {
    return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
}

/* Pointer taps arrive as IMGUI MouseDown events, the same route the managed
   patch uses. GUI/mouse coordinates are top-left, matching the icon rects. */
void ghost_menu_tap(void) {
    if (!ghost.ready) return;
    if (ghost.event_current == NULL || ghost.event_getMousePosition == NULL ||
        ghost.vec2_readValue == NULL) {
        return;
    }
    Il2CppObject *event = ghost_call_obj(ghost.event_current, NULL, NULL);
    if (event == NULL) return;
    Il2CppObject *position = ghost_call_obj(ghost.event_getMousePosition, event, NULL);
    if (position == NULL) return;
    float tx = 0.0f, ty = 0.0f;
    if (!ghost_call_vec2(ghost.vec2_readValue, position, NULL, &tx, &ty)) return;

    GhostRect icon = icon_rect();
    if (in_rect(tx, ty, icon)) {
        menuOpen = !menuOpen;
        return;
    }
    if (!menuOpen) return;

    for (int i = 0; i < MENU_ROWS; i++) {
        if (!in_rect(tx, ty, row_rect(i, lastScreenH))) continue;
        uint32_t flag = rows[i].flag;
        if (ghost_channel_current()->flags & flag) {
            ghost_channel_patch_flags(0, flag);
        } else {
            ghost_channel_patch_flags(flag, 0);
        }
        break;
    }
}

static void draw_icon(void) {
    GhostRect icon = icon_rect();

    /* Plate and frame first, unconditionally. The texture arriving over the
       channel can still be transparent (a decode hiccup) or a fake-null Unity
       object; drawing the plate under it keeps the entry point visible in
       every one of those states. */
    ghost_draw_fill(icon, rgba(0.03f, 0.04f, 0.06f, 0.88f));
    GhostColor edge = accentColor(0.95f);
    ghost_draw_fill((GhostRect){ icon.x, icon.y, icon.width, 2.0f }, edge);
    ghost_draw_fill((GhostRect){ icon.x, icon.y + icon.height - 2.0f,
                                 icon.width, 2.0f }, edge);
    ghost_draw_fill((GhostRect){ icon.x, icon.y, 2.0f, icon.height }, edge);
    ghost_draw_fill((GhostRect){ icon.x + icon.width - 2.0f, icon.y,
                                 2.0f, icon.height }, edge);

    /* A single accent pip, always drawn: it marks the tap target even when the
       texture is still transparent or missing entirely. */
    float pip = 5.0f * uiScale(lastScreenH);
    if (pip < 4.0f) pip = 4.0f;
    ghost_draw_fill((GhostRect){ icon.x + 4.0f, icon.y + 4.0f, pip, pip },
                    edge);

    if (iconTexture != NULL) {
        GhostColor white = { 1.0f, 1.0f, 1.0f, 1.0f };
        void *colorArgs[1] = { &white };
        ghost_call_void(ghost.gui_setColor, NULL, colorArgs);
        void *args[2] = { &icon, iconTexture };
        ghost_call_void(ghost.gui_drawTexture, NULL, args);
        return;
    }
    ghost_draw_label(icon, "VA", rgba(0.95f, 0.97f, 1.0f, 0.95f),
                     (int)(iconSize * 0.30f));
}

static void draw_panel(float screenH) {
    float ui = uiScale(screenH);
    float panelX = iconX - panelW - 8.0f * ui;
    if (panelX < 2.0f * ui) panelX = 2.0f * ui;
    float panelHeight = titleH + rowH * MENU_ROWS + 6.0f * ui;
    float panelY = iconY;
    if (panelY + panelHeight > screenH - 4.0f * ui) {
        panelY = screenH - panelHeight - 4.0f * ui;
    }

    GhostRect bg = { panelX, panelY, panelW, panelHeight };
    ghost_draw_fill(bg, rgba(0.02f, 0.03f, 0.05f, 0.93f));

    GhostColor edge = accentColor(0.9f);
    ghost_draw_fill((GhostRect){ bg.x, bg.y, bg.width, 1.4f * ui }, edge);
    ghost_draw_fill((GhostRect){ bg.x, bg.y, 1.4f * ui, bg.height }, edge);
    ghost_draw_fill((GhostRect){ bg.x + bg.width - 1.4f * ui, bg.y,
                                 1.4f * ui, bg.height }, edge);
    ghost_draw_fill((GhostRect){ bg.x, bg.y + bg.height - 1.4f * ui,
                                 bg.width, 1.4f * ui }, edge);

    GhostRect title = { bg.x + 6.0f * ui, bg.y + 2.0f * ui,
                        bg.width - 12.0f * ui, 18.0f * ui };
    ghost_draw_label(title, "VORTEX ARENA", edge, (int)(13.0f * ui));

    GhostRect dev = { bg.x + 6.0f * ui, bg.y + 19.0f * ui,
                      bg.width - 12.0f * ui, 13.0f * ui };
    ghost_draw_label(dev, "dev: ngvanan10",
                     rgba(0.62f, 0.65f, 0.70f, 0.92f), (int)(8.0f * ui));

    const ghost_settings_t *s = ghost_channel_current();
    for (int i = 0; i < MENU_ROWS; i++) {
        GhostRect r = row_rect(i, screenH);
        int on = (s->flags & rows[i].flag) != 0;
        ghost_draw_fill(r, on ? rgba(0.08f, 0.11f, 0.15f, 0.9f)
                              : rgba(0.04f, 0.05f, 0.07f, 0.8f));

        /* Status pill on the right. */
        float pillW = 30.0f * ui;
        GhostRect pill = { r.x + r.width - pillW - 4.0f * ui, r.y + 4.0f * ui,
                           pillW, r.height - 8.0f * ui };
        if (on) {
            ghost_draw_fill(pill, accentColor(0.9f));
            ghost_draw_label(pill, "ON", rgba(0.01f, 0.02f, 0.03f, 1.0f),
                             (int)(9.5f * ui));
        } else {
            ghost_draw_fill(pill, rgba(0.14f, 0.16f, 0.19f, 0.9f));
            ghost_draw_label(pill, "OFF", rgba(0.55f, 0.58f, 0.63f, 1.0f),
                             (int)(9.5f * ui));
        }

        GhostRect name = { r.x + 6.0f * ui, r.y, r.width - pillW - 18.0f * ui,
                           r.height };
        ghost_draw_label(name, rows[i].label,
                         on ? rgba(0.94f, 0.96f, 1.0f, 0.96f)
                            : rgba(0.62f, 0.65f, 0.70f, 0.9f),
                         (int)(10.0f * ui));
    }
}

void ghost_menu_frame(void) {
    if (!ghost.ready) return;
    if (ghost.screen_width == NULL || ghost.screen_height == NULL) return;

    int32_t width = 0, height = 0;
    if (!ghost_call_i32(ghost.screen_width, NULL, NULL, &width)) return;
    if (!ghost_call_i32(ghost.screen_height, NULL, NULL, &height)) return;
    if (width <= 0 || height <= 0) return;

    layout((float)width, (float)height);
    ghost_draw_ensure_style();

    draw_icon();
    if (menuOpen) draw_panel((float)height);

    /* The menu runs after the ESP pass, so it owns the global GUI colours
       from here on; put them back for the game's own OnGUI. */
    GhostColor white = { 1.0f, 1.0f, 1.0f, 1.0f };
    void *args[1] = { &white };
    ghost_call_void(ghost.gui_setColor, NULL, args);
    ghost_call_void(ghost.gui_setContentColor, NULL, args);
}

void ghost_menu_on_image(const uint8_t *rgba, int width, int height) {
    if (rgba == NULL || width <= 0 || height <= 0) return;
    size_t size = (size_t)width * (size_t)height * 4;
    uint8_t *copy = (uint8_t *)malloc(size);
    if (copy == NULL) return;
    memcpy(copy, rgba, size);

    /* The poll thread hands the bytes to the main queue; the texture ctor
       must run where Unity's graphics calls are legal. */
    dispatch_async(dispatch_get_main_queue(), ^{
        Il2CppObject *texture = ghost_texture_from_rgba(copy, width, height);
        free(copy);
        if (texture != NULL) iconTexture = texture;
    });
}
