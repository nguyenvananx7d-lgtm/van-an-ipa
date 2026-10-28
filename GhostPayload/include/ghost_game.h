//
//  ghost_game.h — every game/Unity symbol the payload touches, resolved once.
//
//  Nothing here is an offset from a dump. Classes come from
//  il2cpp_class_from_name, methods from il2cpp_class_get_method_from_name, and
//  the one obfuscated symbol (the match's player-list accessor) is discovered
//  by walking the match class for a zero-argument method whose return type is
//  a collection of Player. That is why a game update does not break this route.
//

#ifndef GHOST_GAME_H
#define GHOST_GAME_H

#include <stddef.h>

#include "ghost.h"
#include "ghost_il2cpp.h"

typedef struct {
    Il2CppClass *player;
    Il2CppClass *match;
    Il2CppClass *camera;
    Il2CppClass *transform;
    Il2CppClass *gameObject;
    Il2CppClass *component;
    Il2CppClass *sceneTool;
    Il2CppClass *gui;
    Il2CppClass *guiSkin;
    Il2CppClass *guiStyle;
    Il2CppClass *texture2D;
    Il2CppClass *eventClass;
    Il2CppClass *objectClass;
    Il2CppClass *screenClass;
    Il2CppClass *timeClass;
    Il2CppClass *quaternionClass;
    Il2CppClass *inputClass;
    Il2CppClass *glClass;
    Il2CppClass *touchscreenClass;
    Il2CppClass *pointerClass;
    Il2CppClass *buttonControlClass;
    Il2CppClass *touchControlClass;
    Il2CppClass *vector2ControlClass;

    const MethodInfo *player_lateUpdate;
    const MethodInfo *player_isLocalPlayer;
    const MethodInfo *player_isLocalTeammate;
    const MethodInfo *player_isDieing;
    const MethodInfo *player_curHP;
    const MethodInfo *player_maxHP;
    const MethodInfo *player_rootTransform;
    const MethodInfo *player_nickName;
    const MethodInfo *player_getHeadTF;
    const MethodInfo *player_isVisible;
    const MethodInfo *player_setAimRotation;
    long player_aimRotationOffset;

    const MethodInfo *facade_currentMatch;
    const MethodInfo *facade_currentLocalPlayer;
    const MethodInfo *match_players;

    const MethodInfo *camera_main;
    const MethodInfo *camera_worldToScreen;
    const MethodInfo *camera_getTransform;
    const MethodInfo *camera_fieldOfView;
    const MethodInfo *transform_getPosition;
    const MethodInfo *transform_getRotation;
    const MethodInfo *transform_getForward;
    const MethodInfo *transform_setRotation;
    const MethodInfo *quaternion_lookRotation;
    const MethodInfo *quaternion_slerp;

    /* Touch gate: legacy Input first, then the Input System package. */
    const MethodInfo *input_touchCount;
    const MethodInfo *input_mouseButtonDown;
    const MethodInfo *input_mousePosition;
    const MethodInfo *touchscreen_current;
    const MethodInfo *touchscreen_press;
    const MethodInfo *pointer_primaryTouch;
    const MethodInfo *touch_position;
    const MethodInfo *vec2_readValue;
    const MethodInfo *button_isPressed;
    const MethodInfo *button_wasPressedThisFrame;

    /* Immediate-mode GL, for the FOV ring (same path the managed patch uses). */
    const MethodInfo *gl_pushMatrix;
    const MethodInfo *gl_loadOrtho;
    const MethodInfo *gl_begin;
    const MethodInfo *gl_color;
    const MethodInfo *gl_vertex3;
    const MethodInfo *gl_end;
    const MethodInfo *gl_popMatrix;

    const MethodInfo *gameObject_ctor;
    const MethodInfo *gameObject_addComponent;
    const MethodInfo *object_dontDestroyOnLoad;

    const MethodInfo *gui_drawTexture;
    const MethodInfo *gui_label;
    const MethodInfo *gui_getSkin;
    const MethodInfo *gui_setColor;
    const MethodInfo *gui_setContentColor;
    const MethodInfo *skin_getLabel;
    const MethodInfo *style_setFontSize;
    const MethodInfo *style_setAlignment;
    const MethodInfo *style_setFontStyle;
    const MethodInfo *texture2D_white;
    const MethodInfo *texture2D_ctor4;
    const MethodInfo *texture2D_loadRawPtr;
    const MethodInfo *texture2D_apply;

    const MethodInfo *event_current;
    const MethodInfo *event_getType;
    const MethodInfo *sceneTool_ongui;
    const MethodInfo *screen_width;
    const MethodInfo *screen_height;
    const MethodInfo *time_unscaledTime;
    const MethodInfo *time_deltaTime;
    const MethodInfo *style_ctor;

    Il2CppObject *whiteTexture;
    Il2CppObject *labelStyle;
    int ready;
} GhostGame;

extern GhostGame ghost;

/* Resolve everything. Returns 1 when the minimum set for aim is present.
   Safe to call repeatedly; stops trying once ready. */
int ghost_game_resolve(void);

/* Enumerate the live player list into `out` (bounded). Returns the count.
   `local` receives the local player when it is in the list. */
int ghost_game_players(Il2CppObject **out, int capacity, Il2CppObject **local);

/* Distance between two players' root transforms. Returns -1 when a transform
   is missing. */
float ghost_game_distance(Il2CppObject *a, Il2CppObject *b);

/* Convenience readers. Return 0 on failure. */
int ghost_player_is_local(Il2CppObject *player);
int ghost_player_is_teammate(Il2CppObject *player);
int ghost_player_is_downed(Il2CppObject *player);
int ghost_player_health(Il2CppObject *player, int *hp, int *maxHP);
int ghost_player_visible(Il2CppObject *player);
int ghost_player_root(Il2CppObject *player, GhostVec3 *position);
int ghost_player_head(Il2CppObject *player, GhostVec3 *position);
void ghost_player_nickname(Il2CppObject *player, char *out, size_t capacity);
Il2CppObject *ghost_camera_main(void);

/* World-to-screen through the live camera. Returns 1 when the point is in
   front of the camera. */
int ghost_world_to_screen(Il2CppObject *camera, GhostVec3 world, GhostVec3 *screen);

/* Camera transform, for the aim solve. NULL when no camera is live. */
Il2CppObject *ghost_camera_transform(Il2CppObject *camera);

/* Vertical field of view in degrees, for projecting the aim cone. */
int ghost_camera_fov(Il2CppObject *camera, float *fov);

/* Current camera rotation, its forward vector and position. */
int ghost_camera_rotation(Il2CppObject *camera, GhostQuat *rotation);
int ghost_camera_forward(Il2CppObject *camera, GhostVec3 *forward);
int ghost_camera_position(Il2CppObject *camera, GhostVec3 *position);

/* Quaternion.LookRotation(forward) — returns 0 on failure. */
int ghost_look_rotation(GhostVec3 forward, GhostQuat *rotation);

/* Quaternion.Slerp(a, b, t). */
int ghost_slerp(GhostQuat a, GhostQuat b, float t, GhostQuat *rotation);

/* ---- touch input (shared by the aim gate and the in-game menu) ------------ */

/* 0 legacy Input, 1 Input System package, 2 nothing usable. Probed once. */
int ghost_touch_mode(void);

/* A finger is currently down (any finger). */
int ghost_touch_down(void);

/* A press began this frame. */
int ghost_touch_began(void);

/* Current press position in pixels, top-left origin. */
int ghost_touch_position(float *x, float *y);

/* ---- texture --------------------------------------------------------------- */

/* Build a Texture2D from RGBA8 bytes (top-left origin, straight alpha).
   Must run on Unity's main thread. NULL when the texture API is missing. */
Il2CppObject *ghost_texture_from_rgba(const uint8_t *rgba, int width, int height);

#endif /* GHOST_GAME_H */
