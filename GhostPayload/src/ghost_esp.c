//
//  ghost_esp.c — corner boxes, health track, name chip, tracer.
//
//  Drawn from inside `SceneEditBoxSelectTool.OnGUI`, on the Repaint event. The
//  driver GameObject below is the same trick the managed patch used, but the
//  method body is hooked natively, so IFix never sees a wrapper.
//
//  Everything is resolved by name; no dump offset is used. The look is
//  deliberately restrained: four corner brackets, one thin health track, one
//  name chip and a faint tracer. No boxes around the whole screen, no rainbow
//  unless the palette asks for it.
//

#include "ghost_esp.h"
#include "ghost_aim.h"
#include "ghost_channel.h"
#include "ghost_game.h"
#include "ghost_hook.h"
#include "ghost_menu.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static float clampf(float value, float low, float high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static Il2CppObject *driverObject;
static Il2CppObject *driverComponent;
static int hookInstalled;
static void (*originalOnGUI)(void *self);

/* ---- palette -------------------------------------------------------------- */

typedef struct { float r, g, b; } Rgb;

static const Rgb palette[8] = {
    { 0.36f, 0.95f, 0.76f }, /* mint      */
    { 0.49f, 0.83f, 1.00f }, /* ice       */
    { 1.00f, 0.44f, 0.68f }, /* rose      */
    { 1.00f, 0.78f, 0.34f }, /* amber     */
    { 0.72f, 0.61f, 1.00f }, /* violet    */
    { 1.00f, 0.36f, 0.37f }, /* red       */
    { 0.94f, 0.96f, 0.98f }, /* white     */
    { 0.66f, 1.00f, 0.38f }, /* lime      */
};

static GhostColor rgba(float r, float g, float b, float a) {
    GhostColor c = { r, g, b, a };
    return c;
}

static GhostColor accent(float alpha) {
    const ghost_settings_t *s = ghost_channel_current();
    Rgb c = palette[s->palette & 7];
    return rgba(c.r, c.g, c.b, alpha);
}

static GhostColor health_color(float ratio) {
    if (ratio > 0.5f) {
        float t = (ratio - 0.5f) * 2.0f;
        return rgba(1.0f - 0.62f * t, 0.78f + 0.18f * t, 0.30f + 0.26f * t, 1.0f);
    }
    float t = ratio * 2.0f;
    return rgba(1.0f, 0.30f + 0.48f * t, 0.30f, 1.0f);
}

/* ---- primitives ----------------------------------------------------------- */

static void fill(GhostRect rect, GhostColor color) {
    if (rect.width <= 0.0f || rect.height <= 0.0f) return;
    if (ghost.whiteTexture == NULL) {
        ghost.whiteTexture = ghost_call_obj(ghost.texture2D_white, NULL, NULL);
        if (ghost.whiteTexture == NULL) return;
    }
    void *colorArgs[1] = { &color };
    ghost_call_void(ghost.gui_setColor, NULL, colorArgs);
    void *args[2] = { &rect, ghost.whiteTexture };
    ghost_call_void(ghost.gui_drawTexture, NULL, args);
}

static void label(GhostRect rect, const char *text, GhostColor color, int fontSize) {
    if (ghost.labelStyle == NULL || text == NULL || text[0] == '\0') return;
    void *colorArgs[1] = { &color };
    ghost_call_void(ghost.gui_setContentColor, NULL, colorArgs);
    void *sizeArgs[1] = { &fontSize };
    ghost_call_void(ghost.style_setFontSize, ghost.labelStyle, sizeArgs);
    Il2CppString *value = ghost_string(text);
    if (value == NULL) return;
    void *args[3] = { &rect, value, ghost.labelStyle };
    ghost_call_void(ghost.gui_label, NULL, args);
}

/* 1-pixel Bresenham; used only for the tracer. */
static void line(float x0, float y0, float x1, float y1, GhostColor color) {
    int ix0 = (int)lrintf(x0), iy0 = (int)lrintf(y0);
    int ix1 = (int)lrintf(x1), iy1 = (int)lrintf(y1);
    int dx = abs(ix1 - ix0), sx = ix0 < ix1 ? 1 : -1;
    int dy = -abs(iy1 - iy0), sy = iy0 < iy1 ? 1 : -1;
    int err = dx + dy;
    int guard = 0;
    for (;;) {
        GhostRect dot = { (float)ix0, (float)iy0, 1.0f, 1.0f };
        fill(dot, color);
        if (ix0 == ix1 && iy0 == iy1) break;
        if (++guard > 4096) break;
        int e2 = err * 2;
        if (e2 >= dy) { err += dy; ix0 += sx; }
        if (e2 <= dx) { err += dx; iy0 += sy; }
    }
}

/* ---- FOV ring (immediate-mode GL, like the managed patch) ----------------- */

static void gl_vertex_px(float x, float y, float screenW, float screenH) {
    GhostVec3 v = { x / screenW, 1.0f - y / screenH, 0.0f };
    void *args[1] = { &v };
    ghost_call_void(ghost.gl_vertex3, NULL, args);
}

static void draw_gl_circle(float cx, float cy, float radius, int segments,
                           GhostColor color, float screenW, float screenH) {
    if (ghost.gl_pushMatrix == NULL || ghost.gl_loadOrtho == NULL ||
        ghost.gl_begin == NULL || ghost.gl_color == NULL ||
        ghost.gl_vertex3 == NULL || ghost.gl_end == NULL ||
        ghost.gl_popMatrix == NULL) {
        return;
    }
    ghost_call_void(ghost.gl_pushMatrix, NULL, NULL);
    ghost_call_void(ghost.gl_loadOrtho, NULL, NULL);
    int32_t mode = 1; /* GL.LINES */
    void *modeArgs[1] = { &mode };
    ghost_call_void(ghost.gl_begin, NULL, modeArgs);
    void *colorArgs[1] = { &color };
    ghost_call_void(ghost.gl_color, NULL, colorArgs);
    for (int i = 0; i < segments; i++) {
        float a0 = (float)i / (float)segments * 6.2831853f;
        float a1 = (float)(i + 1) / (float)segments * 6.2831853f;
        gl_vertex_px(cx + cosf(a0) * radius, cy + sinf(a0) * radius,
                     screenW, screenH);
        gl_vertex_px(cx + cosf(a1) * radius, cy + sinf(a1) * radius,
                     screenW, screenH);
    }
    ghost_call_void(ghost.gl_end, NULL, NULL);
    ghost_call_void(ghost.gl_popMatrix, NULL, NULL);
}

/* ---- style ---------------------------------------------------------------- */

static void ensure_style(void) {
    if (ghost.labelStyle != NULL) return;
    if (ghost.gui_getSkin == NULL || ghost.skin_getLabel == NULL ||
        ghost.style_ctor == NULL || ghost.guiStyle == NULL) {
        return;
    }
    Il2CppObject *skin = ghost_call_obj(ghost.gui_getSkin, NULL, NULL);
    if (skin == NULL) return;
    Il2CppObject *base = ghost_call_obj(ghost.skin_getLabel, skin, NULL);
    if (base == NULL) return;

    Il2CppObject *style = ghost_object_new(ghost.guiStyle);
    if (style == NULL) return;
    void *ctorArgs[1] = { base };
    ghost_call_void(ghost.style_ctor, style, ctorArgs);

    /* TextAnchor.MiddleCenter = 4, FontStyle.Bold = 1. */
    int32_t anchor = 4;
    void *anchorArgs[1] = { &anchor };
    ghost_call_void(ghost.style_setAlignment, style, anchorArgs);
    if (ghost.style_setFontStyle != NULL) {
        int32_t bold = 1;
        void *boldArgs[1] = { &bold };
        ghost_call_void(ghost.style_setFontStyle, style, boldArgs);
    }
    ghost.labelStyle = style;
}

void ghost_draw_fill(GhostRect rect, GhostColor color) { fill(rect, color); }
void ghost_draw_label(GhostRect rect, const char *text, GhostColor color,
                      int fontSize) { label(rect, text, color, fontSize); }
void ghost_draw_ensure_style(void) { ensure_style(); }

/* ---- one player ----------------------------------------------------------- */

static void draw_corners(GhostRect box, float thickness, float arm, GhostColor color) {
    float x = box.x, y = box.y, w = box.width, h = box.height;
    GhostRect pieces[8] = {
        { x, y, arm, thickness },
        { x, y, thickness, arm },
        { x + w - arm, y, arm, thickness },
        { x + w - thickness, y, thickness, arm },
        { x, y + h - thickness, arm, thickness },
        { x, y + h - arm, thickness, arm },
        { x + w - arm, y + h - thickness, arm, thickness },
        { x + w - thickness, y + h - arm, thickness, arm },
    };
    for (int i = 0; i < 8; i++) fill(pieces[i], color);
}

static void draw_player(Il2CppObject *camera, Il2CppObject *player,
                        Il2CppObject *local, float screenW, float screenH,
                        const ghost_settings_t *s) {
    GhostVec3 root, head;
    if (!ghost_player_root(player, &root)) return;
    if (!ghost_player_head(player, &head)) head = root;

    GhostVec3 sRoot, sHead;
    if (!ghost_world_to_screen(camera, root, &sRoot)) return;
    if (!ghost_world_to_screen(camera, head, &sHead)) sHead = sRoot;

    float top = screenH - sHead.y;
    float bottom = screenH - sRoot.y;
    if (bottom - top < 6.0f) {
        /* Head and feet nearly coincide: use a distance-derived fallback so the
           box does not collapse on a far target. */
        float distance = local != NULL ? ghost_game_distance(player, local) : -1.0f;
        float fallback = distance > 0.0f ? 9000.0f / distance : 12.0f;
        if (fallback < 10.0f) fallback = 10.0f;
        if (fallback > 160.0f) fallback = 160.0f;
        bottom = top + fallback;
    }

    float height = bottom - top;
    float boxScale = clampf(s->esp_box_scale, 0.4f, 3.0f);
    float textScale = clampf(s->esp_text_scale, 0.5f, 3.0f);
    float width = height * 0.46f * boxScale;
    float cx = (sRoot.x + sHead.x) * 0.5f;
    float x = cx - width * 0.5f;

    if (bottom < 0.0f || top > screenH || x > screenW || x + width < 0.0f) return;

    int downed = ghost_player_is_downed(player);
    GhostColor main = downed ? rgba(0.62f, 0.66f, 0.72f, 0.95f) : accent(0.95f);
    float ui = screenH / 900.0f;
    if (ui < 0.75f) ui = 0.75f;
    if (ui > 1.6f) ui = 1.6f;

    /* Corner brackets — the box itself, gated on the BOX flag like every
       other visual. In the "edge" style the full outline is also filled,
       with the panel's fill alpha instead of a hardcoded one. */
    if (s->flags & GHOST_FLAG_BOX) {
        if (s->box_style == 1) {
            GhostRect outline = { x, top, width, height };
            fill(outline, rgba(main.r, main.g, main.b,
                               clampf(s->esp_fill_alpha, 0.0f, 1.0f)));
        }

        float thickness = 1.4f * ui;
        if (thickness < 1.0f) thickness = 1.0f;
        float arm = width < height ? width * 0.26f : height * 0.26f;
        if (arm < 4.0f) arm = 4.0f;
        draw_corners((GhostRect){ x, top, width, height }, thickness, arm, main);
    }

    /* Health track under the box. */
    if (s->flags & GHOST_FLAG_HEALTH) {
        int hp = 100, maxHP = 100;
        ghost_player_health(player, &hp, &maxHP);
        float ratio = maxHP > 0 ? (float)hp / (float)maxHP : 0.0f;
        if (ratio < 0.0f) ratio = 0.0f;
        if (ratio > 1.0f) ratio = 1.0f;

        float barH = 3.2f * ui;
        GhostRect back = { x, bottom + 3.0f * ui, width, barH };
        fill(back, rgba(0.02f, 0.03f, 0.04f, 0.62f));
        if (ratio > 0.0f) {
            GhostRect fillRect = { x + 0.5f, bottom + 3.5f * ui,
                                   (width - 1.0f) * ratio, barH - 1.0f };
            fill(fillRect, health_color(ratio));
        }
    }

    /* Name / distance chip. */
    if (s->flags & (GHOST_FLAG_NAME | GHOST_FLAG_DISTANCE)) {
        char name[64];
        ghost_player_nickname(player, name, sizeof(name));
        if (name[0] == '\0') snprintf(name, sizeof(name), "player");

        float distance = local != NULL ? ghost_game_distance(player, local) : -1.0f;
        char text[112];
        if ((s->flags & GHOST_FLAG_NAME) && (s->flags & GHOST_FLAG_DISTANCE) &&
            distance >= 0.0f) {
            snprintf(text, sizeof(text), "%.18s  |  %dm", name,
                     (int)(distance + 0.5f));
        } else if (s->flags & GHOST_FLAG_NAME) {
            snprintf(text, sizeof(text), "%.24s", name);
        } else if (distance >= 0.0f) {
            snprintf(text, sizeof(text), "%dm", (int)(distance + 0.5f));
        } else {
            text[0] = '\0';
        }

        float chipH = 15.0f * ui * textScale;
        GhostRect chip = { x - 2.0f * ui, top - chipH - 5.0f * ui,
                           width + 4.0f * ui, chipH };
        fill(chip, rgba(0.02f, 0.03f, 0.04f, 0.58f));
        GhostRect edge = { chip.x, chip.y, chip.width, 1.2f * ui };
        fill(edge, main);

        int fontSize = (int)(10.0f * ui * textScale);
        if (fontSize < 8) fontSize = 8;
        label(chip, text, rgba(0.95f, 0.97f, 1.0f, 0.96f), fontSize);
    }

    /* Head marker — small, so it reads as a dot and not a second box. */
    GhostRect headDot = { sHead.x - 1.5f * ui, screenH - sHead.y - 1.5f * ui,
                          3.0f * ui, 3.0f * ui };
    fill(headDot, main);

    /* Tracer from the bottom centre. */
    if (s->flags & GHOST_FLAG_TRACER) {
        line(screenW * 0.5f, screenH, cx, bottom,
             rgba(main.r, main.g, main.b, 0.30f));
    }
}

/* ---- frame ---------------------------------------------------------------- */

void ghost_esp_draw(void) {
    if (!ghost.ready) return;
    ghost_channel_tick();
    const ghost_settings_t *s = ghost_channel_current();
    if (ghost.screen_width == NULL || ghost.screen_height == NULL) return;

    int32_t width = 0, height = 0;
    if (!ghost_call_i32(ghost.screen_width, NULL, NULL, &width)) return;
    if (!ghost_call_i32(ghost.screen_height, NULL, NULL, &height)) return;
    if (width <= 0 || height <= 0) return;

    float screenW = (float)width;
    float screenH = (float)height;

    /* The FOV ring belongs to the aim, not the ESP layer — drawn whenever the
       assist is armed, with or without ESP, exactly like the managed patch.
       The radius is the aim cone projected through the camera's vertical FOV,
       so the ring really is the edge of what the assist can reach. */
    if ((s->flags & GHOST_FLAG_FOV_RING) && (s->flags & GHOST_FLAG_AIM)) {
        float camFov = 60.0f;
        Il2CppObject *fovCamera = ghost_camera_main();
        if (fovCamera != NULL) {
            float fov = 0.0f;
            if (ghost_camera_fov(fovCamera, &fov) && fov > 1.0f) camFov = fov;
        }
        float coneHalf = s->aim_fov * 0.5f * (3.14159265f / 180.0f);
        float camHalf = camFov * 0.5f * (3.14159265f / 180.0f);
        float radius = tanf(coneHalf) / tanf(camHalf) * (screenH * 0.5f);
        if (radius > 1.0f && radius < screenH * 4.0f) {
            GhostColor ring = accent(1.0f);
            draw_gl_circle(screenW * 0.5f, screenH * 0.5f, radius, 72,
                           rgba(ring.r, ring.g, ring.b, 0.14f), screenW, screenH);
            draw_gl_circle(screenW * 0.5f, screenH * 0.5f, radius - 1.0f, 72,
                           rgba(ring.r, ring.g, ring.b, 0.38f), screenW, screenH);
            draw_gl_circle(screenW * 0.5f, screenH * 0.5f, 2.5f, 12,
                           rgba(ring.r, ring.g, ring.b, 0.65f), screenW, screenH);
        }
    }

    if (!(s->flags & GHOST_FLAG_ESP)) return;

    Il2CppObject *camera = ghost_camera_main();
    if (camera == NULL) return;

    ensure_style();

    Il2CppObject *players[64];
    Il2CppObject *local = NULL;
    int count = ghost_game_players(players, 64, &local);

    for (int i = 0; i < count; i++) {
        Il2CppObject *player = players[i];
        if (player == NULL || player == local) continue;
        if (ghost_player_is_local(player)) continue;
        if (ghost_player_is_teammate(player)) continue;

        int downed = ghost_player_is_downed(player);
        int hp = 0, maxHP = 0;
        ghost_player_health(player, &hp, &maxHP);
        if (!downed && hp <= 0) continue;

        float distance = local != NULL ? ghost_game_distance(player, local) : -1.0f;
        if (distance >= 0.0f && distance > s->esp_max_distance) continue;

        draw_player(camera, player, local, screenW, screenH, s);
    }

    /* GUI.color and GUI.contentColor are global; put both back so the game's
       own OnGUI is untouched. */
    GhostColor white = { 1.0f, 1.0f, 1.0f, 1.0f };
    void *args[1] = { &white };
    ghost_call_void(ghost.gui_setColor, NULL, args);
    ghost_call_void(ghost.gui_setContentColor, NULL, args);
}

/* ---- hook ----------------------------------------------------------------- */

static void ongui_replacement(void *self) {
    if (self == driverComponent) {
        if (ghost.event_current != NULL && ghost.event_getType != NULL) {
            Il2CppObject *event = ghost_call_obj(ghost.event_current, NULL, NULL);
            int32_t type = -1;
            if (event != NULL) ghost_call_i32(ghost.event_getType, event, NULL, &type);
            if (type == 7) { /* EventType.Repaint */
                ghost_aim_reassert();
                ghost_esp_draw();
                ghost_menu_frame();
            }
        } else {
            ghost_aim_reassert();
            ghost_esp_draw();
            ghost_menu_frame();
        }
        /* Never run the original on our driver: its private fields are null. */
        return;
    }
    if (originalOnGUI != NULL) originalOnGUI(self);
}

static int create_driver(void) {
    if (driverObject != NULL) return 1;
    if (ghost.gameObject_ctor == NULL || ghost.gameObject == NULL ||
        ghost.sceneTool == NULL || ghost.gameObject_addComponent == NULL) {
        return 0;
    }

    Il2CppObject *name = ghost_string("ghost_driver");
    if (name == NULL) return 0;

    Il2CppObject *object = ghost_object_new(ghost.gameObject);
    if (object == NULL) return 0;
    void *ctorArgs[1] = { name };
    if (!ghost_call_void(ghost.gameObject_ctor, object, ctorArgs)) return 0;

    Il2CppObject *type = ghost_type_object(ghost.sceneTool);
    if (type == NULL) return 0;
    void *addArgs[1] = { type };
    Il2CppObject *component = ghost_call_obj(ghost.gameObject_addComponent, object, addArgs);
    if (component == NULL) return 0;

    if (ghost.object_dontDestroyOnLoad != NULL) {
        void *keepArgs[1] = { object };
        ghost_call_void(ghost.object_dontDestroyOnLoad, NULL, keepArgs);
    }

    driverObject = object;
    driverComponent = component;
    return 1;
}

int ghost_esp_install(void) {
    if (hookInstalled) return 1;
    if (!ghost.ready || ghost.sceneTool_ongui == NULL) return 0;
    if (!create_driver()) return 0;

    void **slot = (void **)ghost.sceneTool_ongui;
    if (*slot == NULL) return 0;

    if (ghost_hook_pointer(slot, (void *)ongui_replacement,
                           (void **)&originalOnGUI) != 0) {
        return 0;
    }
    hookInstalled = 1;
    return 1;
}

int ghost_esp_ready(void) {
    return hookInstalled;
}
