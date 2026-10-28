//
//  ghost_game.c — resolution and the handful of readers the payload needs.
//

#include "ghost_game.h"

#include <string.h>

GhostGame ghost;

static Il2CppClass *klassOf(const char *ns, const char *name) {
    return ghost_class(ns, name);
}

static const MethodInfo *methodOf(Il2CppClass *klass, const char *name, int params) {
    if (klass == NULL) return NULL;
    return ghost_method(klass, name, params);
}

/* The list accessors are looked up on the runtime class of the object the game
   returned, so the generic instantiation does not have to be named. */
static const MethodInfo *cachedCount;
static const MethodInfo *cachedItem;
static Il2CppClass *cachedListClass;

static void resolveListAccessors(Il2CppClass *klass) {
    if (klass == NULL || klass == cachedListClass) return;
    cachedCount = ghost_method(klass, "get_Count", 0);
    cachedItem = ghost_method(klass, "get_Item", 1);
    cachedListClass = klass;
}

int ghost_game_resolve(void) {
    if (ghost.ready) return 1;
    if (!ghost_il2cpp_ready()) return 0;

    ghost.player = klassOf("COW.GamePlay", "Player");
    if (ghost.player == NULL) return 0;

    ghost.camera = klassOf("UnityEngine", "Camera");
    ghost.transform = klassOf("UnityEngine", "Transform");
    ghost.gameObject = klassOf("UnityEngine", "GameObject");
    ghost.component = klassOf("UnityEngine", "Component");
    ghost.sceneTool = klassOf("COW.GamePlay", "SceneEditBoxSelectTool");
    ghost.gui = klassOf("UnityEngine", "GUI");
    ghost.guiSkin = klassOf("UnityEngine", "GUISkin");
    ghost.guiStyle = klassOf("UnityEngine", "GUIStyle");
    ghost.texture2D = klassOf("UnityEngine", "Texture2D");
    ghost.eventClass = klassOf("UnityEngine", "Event");
    ghost.objectClass = klassOf("UnityEngine", "Object");
    ghost.screenClass = klassOf("UnityEngine", "Screen");
    ghost.timeClass = klassOf("UnityEngine", "Time");
    ghost.quaternionClass = klassOf("UnityEngine", "Quaternion");
    ghost.inputClass = klassOf("UnityEngine", "Input");
    ghost.glClass = klassOf("UnityEngine", "GL");
    ghost.touchscreenClass = klassOf("UnityEngine.InputSystem", "Touchscreen");
    ghost.pointerClass = klassOf("UnityEngine.InputSystem", "Pointer");
    ghost.buttonControlClass = klassOf("UnityEngine.InputSystem.Controls", "ButtonControl");
    ghost.touchControlClass = klassOf("UnityEngine.InputSystem.Controls", "TouchControl");
    ghost.vector2ControlClass = klassOf("UnityEngine.InputSystem.Controls", "Vector2Control");

    Il2CppClass *facade = klassOf("COW", "GameFacade");

    ghost.player_lateUpdate = methodOf(ghost.player, "LateUpdate", 0);
    ghost.player_isLocalPlayer = methodOf(ghost.player, "IsLocalPlayer", 0);
    ghost.player_isLocalTeammate = methodOf(ghost.player, "IsLocalTeammate", 1);
    ghost.player_isDieing = methodOf(ghost.player, "get_IsDieing", 0);
    ghost.player_curHP = methodOf(ghost.player, "get_CurHP", 0);
    ghost.player_maxHP = methodOf(ghost.player, "get_MaxHP", 0);
    ghost.player_rootTransform = methodOf(ghost.player, "get_RootTransform", 0);
    ghost.player_nickName = methodOf(ghost.player, "get_NickName", 0);
    ghost.player_getHeadTF = methodOf(ghost.player, "GetHeadTF", 0);
    ghost.player_isVisible = methodOf(ghost.player, "IsVisible", 0);
    ghost.player_setAimRotation = methodOf(ghost.player, "SetAimRotation", 2);
    ghost.player_aimRotationOffset = ghost_field_offset(ghost.player, "m_CurrentAimRotation");

    ghost.facade_currentMatch = methodOf(facade, "CurrentMatch", 0);
    ghost.facade_currentLocalPlayer = methodOf(facade, "CurrentLocalPlayer", 0);

    ghost.camera_main = methodOf(ghost.camera, "get_main", 0);
    ghost.camera_worldToScreen = methodOf(ghost.camera, "WorldToScreenPoint", 1);
    ghost.camera_getTransform = methodOf(ghost.component, "get_transform", 0);
    ghost.camera_fieldOfView = methodOf(ghost.camera, "get_fieldOfView", 0);
    ghost.transform_getPosition = methodOf(ghost.transform, "get_position", 0);
    ghost.transform_getRotation = methodOf(ghost.transform, "get_rotation", 0);
    ghost.transform_getForward = methodOf(ghost.transform, "get_forward", 0);
    ghost.transform_setRotation = methodOf(ghost.transform, "set_rotation", 1);
    ghost.quaternion_lookRotation = methodOf(ghost.quaternionClass, "LookRotation", 1);
    ghost.quaternion_slerp = methodOf(ghost.quaternionClass, "Slerp", 3);

    ghost.gameObject_ctor = methodOf(ghost.gameObject, ".ctor", 1);
    ghost.gameObject_addComponent = methodOf(ghost.gameObject, "AddComponent", 1);
    ghost.object_dontDestroyOnLoad = methodOf(ghost.objectClass, "DontDestroyOnLoad", 1);

    ghost.gui_drawTexture = methodOf(ghost.gui, "DrawTexture", 2);
    ghost.gui_label = methodOf(ghost.gui, "Label", 3);
    ghost.gui_getSkin = methodOf(ghost.gui, "get_skin", 0);
    ghost.gui_setColor = methodOf(ghost.gui, "set_color", 1);
    ghost.gui_setContentColor = methodOf(ghost.gui, "set_contentColor", 1);
    ghost.skin_getLabel = methodOf(ghost.guiSkin, "get_label", 0);
    ghost.style_setFontSize = methodOf(ghost.guiStyle, "set_fontSize", 1);
    ghost.style_setAlignment = methodOf(ghost.guiStyle, "set_alignment", 1);
    ghost.style_setFontStyle = methodOf(ghost.guiStyle, "set_fontStyle", 1);
    ghost.style_ctor = methodOf(ghost.guiStyle, ".ctor", 1);
    ghost.texture2D_white = methodOf(ghost.texture2D, "get_whiteTexture", 0);
    ghost.texture2D_ctor4 = methodOf(ghost.texture2D, ".ctor", 4);
    ghost.texture2D_loadRawPtr = methodOf(ghost.texture2D, "LoadRawTextureData", 2);
    ghost.texture2D_apply = methodOf(ghost.texture2D, "Apply", 0);

    ghost.event_current = methodOf(ghost.eventClass, "get_current", 0);
    ghost.event_getType = methodOf(ghost.eventClass, "get_type", 0);
    ghost.sceneTool_ongui = methodOf(ghost.sceneTool, "OnGUI", 0);
    ghost.screen_width = methodOf(ghost.screenClass, "get_width", 0);
    ghost.screen_height = methodOf(ghost.screenClass, "get_height", 0);
    ghost.time_unscaledTime = methodOf(ghost.timeClass, "get_unscaledTime", 0);
    ghost.time_deltaTime = methodOf(ghost.timeClass, "get_deltaTime", 0);

    /* Touch gate. `get_press` and `get_primaryTouch` are declared on Pointer,
       the base of Touchscreen; resolving on Pointer directly keeps them
       working if a build hides the inherited lookup. */
    ghost.input_touchCount = methodOf(ghost.inputClass, "get_touchCount", 0);
    ghost.input_mouseButtonDown = methodOf(ghost.inputClass, "GetMouseButtonDown", 1);
    ghost.input_mousePosition = methodOf(ghost.inputClass, "get_mousePosition", 0);
    ghost.touchscreen_current = methodOf(ghost.touchscreenClass, "get_current", 0);
    ghost.touchscreen_press = methodOf(ghost.pointerClass, "get_press", 0);
    ghost.pointer_primaryTouch = methodOf(ghost.pointerClass, "get_primaryTouch", 0);
    ghost.touch_position = methodOf(ghost.touchControlClass, "get_position", 0);
    ghost.vec2_readValue = methodOf(ghost.vector2ControlClass, "ReadValue", 0);
    ghost.button_isPressed = methodOf(ghost.buttonControlClass, "get_isPressed", 0);
    ghost.button_wasPressedThisFrame =
        methodOf(ghost.buttonControlClass, "get_wasPressedThisFrame", 0);

    /* Immediate-mode GL for the FOV ring. */
    ghost.gl_pushMatrix = methodOf(ghost.glClass, "PushMatrix", 0);
    ghost.gl_loadOrtho = methodOf(ghost.glClass, "LoadOrtho", 0);
    ghost.gl_begin = methodOf(ghost.glClass, "Begin", 1);
    ghost.gl_color = methodOf(ghost.glClass, "Color", 1);
    ghost.gl_vertex3 = methodOf(ghost.glClass, "Vertex3", 1);
    ghost.gl_end = methodOf(ghost.glClass, "End", 0);
    ghost.gl_popMatrix = methodOf(ghost.glClass, "PopMatrix", 0);

    /* The match type is obfuscated per build, so it is reached through the
       signature of CurrentMatch rather than by name. */
    if (ghost.facade_currentMatch != NULL) {
        ghost.match = ghost_return_class(ghost.facade_currentMatch);
        ghost.match_players = ghost_find_player_list_method(ghost.match);
    }

    /* Aim needs LateUpdate, the local-player reader, the rotation setter and
       the player list (targets come from it). ESP needs the camera and the
       GUI set; a build missing those still gets the aim layer instead of
       nothing. */
    int aimReady = ghost.player_lateUpdate != NULL &&
                   ghost.facade_currentLocalPlayer != NULL &&
                   ghost.player_setAimRotation != NULL &&
                   ghost.match_players != NULL;
    if (!aimReady) return 0;

    ghost.ready = 1;
    return 1;
}

int ghost_game_players(Il2CppObject **out, int capacity, Il2CppObject **local) {
    if (local != NULL) *local = NULL;
    if (!ghost.ready || ghost.match_players == NULL) return 0;

    Il2CppObject *match = ghost_call_obj(ghost.facade_currentMatch, NULL, NULL);
    if (match == NULL) return 0;

    Il2CppObject *list = ghost_call_obj(ghost.match_players, match, NULL);
    if (list == NULL) return 0;

    resolveListAccessors(((GhostObject *)list)->klass);
    if (cachedCount == NULL || cachedItem == NULL) return 0;

    if (local != NULL) {
        *local = ghost_call_obj(ghost.facade_currentLocalPlayer, NULL, NULL);
    }

    int32_t count = 0;
    if (!ghost_call_i32(cachedCount, list, NULL, &count)) return 0;
    if (count <= 0) return 0;
    if (count > capacity) count = capacity;

    int written = 0;
    for (int32_t i = 0; i < count; i++) {
        void *args[1] = { &i };
        Il2CppObject *player = ghost_call_obj(cachedItem, list, args);
        if (player != NULL) out[written++] = player;
    }
    return written;
}

int ghost_player_is_local(Il2CppObject *player) {
    int value = 0;
    if (player == NULL || ghost.player_isLocalPlayer == NULL) return 0;
    if (!ghost_call_bool(ghost.player_isLocalPlayer, player, NULL, &value)) return 0;
    return value;
}

int ghost_player_is_teammate(Il2CppObject *player) {
    int value = 0;
    uint8_t includeSelf = 0;
    void *args[1] = { &includeSelf };
    if (player == NULL || ghost.player_isLocalTeammate == NULL) return 0;
    if (!ghost_call_bool(ghost.player_isLocalTeammate, player, args, &value)) return 0;
    return value;
}

int ghost_player_is_downed(Il2CppObject *player) {
    int value = 0;
    if (player == NULL || ghost.player_isDieing == NULL) return 0;
    if (!ghost_call_bool(ghost.player_isDieing, player, NULL, &value)) return 0;
    return value;
}

int ghost_player_health(Il2CppObject *player, int *hp, int *maxHP) {
    int32_t current = 0, maximum = 0;
    if (player == NULL) return 0;
    if (ghost.player_curHP == NULL || !ghost_call_i32(ghost.player_curHP, player, NULL, &current)) {
        return 0;
    }
    if (ghost.player_maxHP != NULL) {
        ghost_call_i32(ghost.player_maxHP, player, NULL, &maximum);
    }
    if (hp != NULL) *hp = current;
    if (maxHP != NULL) *maxHP = maximum > 0 ? maximum : 100;
    return 1;
}

int ghost_player_visible(Il2CppObject *player) {
    int value = 0;
    if (player == NULL || ghost.player_isVisible == NULL) return 1;
    if (!ghost_call_bool(ghost.player_isVisible, player, NULL, &value)) return 1;
    return value;
}

static int transform_position(Il2CppObject *transform, GhostVec3 *position) {
    if (transform == NULL || ghost.transform_getPosition == NULL) return 0;
    return ghost_call_vec3(ghost.transform_getPosition, transform, NULL, position);
}

int ghost_player_root(Il2CppObject *player, GhostVec3 *position) {
    if (player == NULL || ghost.player_rootTransform == NULL) return 0;
    Il2CppObject *transform = ghost_call_obj(ghost.player_rootTransform, player, NULL);
    return transform_position(transform, position);
}

int ghost_player_head(Il2CppObject *player, GhostVec3 *position) {
    if (player == NULL || ghost.player_getHeadTF == NULL) return 0;
    Il2CppObject *transform = ghost_call_obj(ghost.player_getHeadTF, player, NULL);
    if (transform == NULL) return 0;
    return transform_position(transform, position);
}

float ghost_game_distance(Il2CppObject *a, Il2CppObject *b) {
    GhostVec3 pa, pb;
    if (!ghost_player_root(a, &pa) || !ghost_player_root(b, &pb)) return -1.0f;
    float dx = pa.x - pb.x, dy = pa.y - pb.y, dz = pa.z - pb.z;
    return __builtin_sqrtf(dx * dx + dy * dy + dz * dz);
}

void ghost_player_nickname(Il2CppObject *player, char *out, size_t capacity) {
    if (out == NULL || capacity == 0) return;
    out[0] = '\0';
    if (player == NULL || ghost.player_nickName == NULL) return;
    Il2CppObject *value = ghost_call_obj(ghost.player_nickName, player, NULL);
    if (value == NULL) return;

    /* Il2CppString is { Il2CppObject header; int32_t length; uint16_t chars[]; }
       and the header is the documented class + monitor pair. */
    int32_t length = *(int32_t *)((char *)value + 16);
    const uint16_t *chars = (const uint16_t *)((char *)value + 20);
    if (length <= 0) return;
    if ((size_t)length >= capacity) length = (int32_t)(capacity - 1);

    size_t written = 0;
    for (int32_t i = 0; i < length && written + 1 < capacity; i++) {
        uint16_t c = chars[i];
        if (c < 0x80) {
            out[written++] = (char)c;
        } else if (c < 0x800) {
            if (written + 2 >= capacity) break;
            out[written++] = (char)(0xC0 | (c >> 6));
            out[written++] = (char)(0x80 | (c & 0x3F));
        } else {
            if (written + 3 >= capacity) break;
            out[written++] = (char)(0xE0 | (c >> 12));
            out[written++] = (char)(0x80 | ((c >> 6) & 0x3F));
            out[written++] = (char)(0x80 | (c & 0x3F));
        }
    }
    out[written] = '\0';
}

Il2CppObject *ghost_camera_main(void) {
    if (!ghost.ready || ghost.camera_main == NULL) return NULL;
    return ghost_call_obj(ghost.camera_main, NULL, NULL);
}

int ghost_world_to_screen(Il2CppObject *camera, GhostVec3 world, GhostVec3 *screen) {
    if (camera == NULL || ghost.camera_worldToScreen == NULL) return 0;
    void *args[1] = { &world };
    GhostVec3 result;
    if (!ghost_call_vec3(ghost.camera_worldToScreen, camera, args, &result)) return 0;
    if (screen != NULL) *screen = result;
    return result.z > 0.01f;
}

Il2CppObject *ghost_camera_transform(Il2CppObject *camera) {
    if (camera == NULL || ghost.camera_getTransform == NULL) return NULL;
    return ghost_call_obj(ghost.camera_getTransform, camera, NULL);
}

int ghost_camera_fov(Il2CppObject *camera, float *fov) {
    if (camera == NULL || ghost.camera_fieldOfView == NULL) return 0;
    return ghost_call_f32(ghost.camera_fieldOfView, camera, NULL, fov);
}

int ghost_camera_rotation(Il2CppObject *camera, GhostQuat *rotation) {
    Il2CppObject *transform = ghost_camera_transform(camera);
    if (transform == NULL || ghost.transform_getRotation == NULL) return 0;
    return ghost_call_quat(ghost.transform_getRotation, transform, NULL, rotation);
}

int ghost_camera_forward(Il2CppObject *camera, GhostVec3 *forward) {
    Il2CppObject *transform = ghost_camera_transform(camera);
    if (transform == NULL || ghost.transform_getForward == NULL) return 0;
    return ghost_call_vec3(ghost.transform_getForward, transform, NULL, forward);
}

int ghost_camera_position(Il2CppObject *camera, GhostVec3 *position) {
    Il2CppObject *transform = ghost_camera_transform(camera);
    if (transform == NULL || ghost.transform_getPosition == NULL) return 0;
    return ghost_call_vec3(ghost.transform_getPosition, transform, NULL, position);
}

int ghost_look_rotation(GhostVec3 forward, GhostQuat *rotation) {
    if (ghost.quaternion_lookRotation == NULL) return 0;
    void *args[1] = { &forward };
    return ghost_call_quat(ghost.quaternion_lookRotation, NULL, args, rotation);
}

int ghost_slerp(GhostQuat a, GhostQuat b, float t, GhostQuat *rotation) {
    if (ghost.quaternion_slerp == NULL) return 0;
    void *args[3] = { &a, &b, &t };
    return ghost_call_quat(ghost.quaternion_slerp, NULL, args, rotation);
}

/* ---- touch input ---------------------------------------------------------- */

/* Probed once: 0 legacy Input, 1 Input System package, 2 nothing usable.
   The legacy `Input.touchCount` throws under an Input-System-only build, so
   a failed probe is the signal to move on, not an error. */
static int touchMode = -1;

int ghost_touch_mode(void) {
    if (touchMode == -1) {
        if (ghost.input_touchCount != NULL) {
            int32_t count = 0;
            if (ghost_call_i32(ghost.input_touchCount, NULL, NULL, &count)) {
                touchMode = 0;
            }
        }
        if (touchMode == -1) {
            touchMode = (ghost.touchscreen_current != NULL &&
                         ghost.touchscreen_press != NULL &&
                         ghost.button_isPressed != NULL) ? 1 : 2;
        }
    }
    return touchMode;
}

static Il2CppObject *primary_touch(void) {
    if (ghost.touchscreen_current == NULL || ghost.pointer_primaryTouch == NULL) {
        return NULL;
    }
    Il2CppObject *screen = ghost_call_obj(ghost.touchscreen_current, NULL, NULL);
    if (screen == NULL) return NULL;
    return ghost_call_obj(ghost.pointer_primaryTouch, screen, NULL);
}

static Il2CppObject *touch_press(Il2CppObject *touch) {
    if (touch == NULL || ghost.touchscreen_press == NULL) return NULL;
    return ghost_call_obj(ghost.touchscreen_press, touch, NULL);
}

int ghost_touch_down(void) {
    if (ghost_touch_mode() == 0) {
        int32_t count = 0;
        return ghost_call_i32(ghost.input_touchCount, NULL, NULL, &count) &&
               count > 0;
    }
    if (touchMode == 1) {
        Il2CppObject *press = touch_press(primary_touch());
        if (press == NULL) return 0;
        int pressed = 0;
        return ghost_call_bool(ghost.button_isPressed, press, NULL, &pressed) &&
               pressed;
    }
    return 0;
}

int ghost_touch_began(void) {
    if (ghost_touch_mode() == 0) {
        if (ghost.input_mouseButtonDown == NULL) return 0;
        int32_t button = 0;
        void *args[1] = { &button };
        int down = 0;
        return ghost_call_bool(ghost.input_mouseButtonDown, NULL, args, &down) &&
               down;
    }
    if (touchMode == 1) {
        Il2CppObject *press = touch_press(primary_touch());
        if (press == NULL || ghost.button_wasPressedThisFrame == NULL) return 0;
        int began = 0;
        return ghost_call_bool(ghost.button_wasPressedThisFrame, press, NULL,
                               &began) && began;
    }
    return 0;
}

int ghost_touch_position(float *x, float *y) {
    float px = 0.0f, py = 0.0f;
    int ok = 0;
    if (ghost_touch_mode() == 0) {
        GhostVec3 pos;
        if (ghost.input_mousePosition != NULL &&
            ghost_call_vec3(ghost.input_mousePosition, NULL, NULL, &pos)) {
            px = pos.x;
            py = pos.y;
            ok = 1;
        }
    } else if (touchMode == 1) {
        Il2CppObject *touch = primary_touch();
        if (touch != NULL && ghost.touch_position != NULL &&
            ghost.vec2_readValue != NULL) {
            Il2CppObject *position = ghost_call_obj(ghost.touch_position, touch, NULL);
            if (position != NULL &&
                ghost_call_vec2(ghost.vec2_readValue, position, NULL, &px, &py)) {
                ok = 1;
            }
        }
    }
    if (!ok) return 0;

    /* Unity screen space is bottom-left; the GUI rects use top-left. */
    int32_t height = 0;
    if (ghost.screen_height != NULL) {
        ghost_call_i32(ghost.screen_height, NULL, NULL, &height);
    }
    if (x != NULL) *x = px;
    if (y != NULL) *y = (float)height - py;
    return 1;
}

/* ---- texture --------------------------------------------------------------- */

Il2CppObject *ghost_texture_from_rgba(const uint8_t *rgba, int width, int height) {
    if (rgba == NULL || width <= 0 || height <= 0 || width > 160 || height > 160) {
        return NULL;
    }
    if (ghost.texture2D_ctor4 == NULL || ghost.texture2D_loadRawPtr == NULL ||
        ghost.texture2D_apply == NULL) {
        return NULL;
    }

    Il2CppObject *texture = ghost_object_new(ghost.texture2D);
    if (texture == NULL) return NULL;

    int32_t w = width, h = height;
    int32_t format = 4; /* TextureFormat.RGBA32 */
    int32_t mipChain = 0;
    void *ctorArgs[4] = { &w, &h, &format, &mipChain };
    if (!ghost_call_void(ghost.texture2D_ctor4, texture, ctorArgs)) return NULL;

    /* IntPtr is a one-field struct; runtime_invoke takes a pointer to the
       value, so the box is just the pointer to the buffer. */
    struct { void *value; } pointerBox = { (void *)rgba };
    int32_t byteCount = width * height * 4;
    void *loadArgs[2] = { &pointerBox, &byteCount };
    if (!ghost_call_void(ghost.texture2D_loadRawPtr, texture, loadArgs)) return NULL;

    if (!ghost_call_void(ghost.texture2D_apply, texture, NULL)) return NULL;
    return texture;
}
