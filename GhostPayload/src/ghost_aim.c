//
//  ghost_aim.c — one solve per frame, written through the game's own aim state.
//
//  The managed aim failed for a boring reason: it ran inside a method the game
//  calls, but gated itself on `Input.touchCount`, which throws under the new
//  Input System, and the exception was swallowed by the weave's try/catch. The
//  native layer has no such gate: every local-player LateUpdate solves, writes
//  `SetAimRotation` and the `m_CurrentAimRotation` field, then lets the camera
//  controller rebuild from that state in the same frame.
//
//  The solve is intentionally conservative: closest-to-crosshair target, a
//  sticky window so the reticle does not flip between two enemies, a turn-rate
//  cap so the correction looks like a hand and not a snap, and an optional
//  sub-degree wobble when hit chance is below 1.
//

#include "ghost_aim.h"
#include "ghost_channel.h"
#include "ghost_game.h"
#include "ghost_hook.h"

#include <math.h>
#include <string.h>
#include <time.h>

static int hookInstalled;
static void (*originalLateUpdate)(void *self);
static Il2CppObject *stickyTarget;
static double stickySince;
static double lastTick;

/* Last solved rotation, held so the OnGUI pass can reassert it right before
   the frame renders (the camera controller rebuilds the transform between
   LateUpdate and OnGUI, which would otherwise undo the solve visually). */
static GhostQuat heldRotation;
static double heldAt;
static int heldValid;
static double lastSetAim;

/* The touch source is probed once in ghost_game.c (legacy Input first, then
   the InputSystem package). When nothing is usable the gate falls open, so a
   missing input path can never silently kill the aim. */
static int aim_touching(void) {
    int mode = ghost_touch_mode();
    return mode == 2 ? 1 : ghost_touch_down();
}

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static float clampf(float value, float low, float high) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
}

static float dot3(GhostVec3 a, GhostVec3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

static GhostVec3 sub3(GhostVec3 a, GhostVec3 b) {
    GhostVec3 r = { a.x - b.x, a.y - b.y, a.z - b.z };
    return r;
}

static float length3(GhostVec3 v) {
    return sqrtf(dot3(v, v));
}

static GhostVec3 normalize3(GhostVec3 v) {
    float length = length3(v);
    if (length < 0.0001f) {
        GhostVec3 zero = { 0.0f, 0.0f, 1.0f };
        return zero;
    }
    GhostVec3 r = { v.x / length, v.y / length, v.z / length };
    return r;
}

static float quat_angle_degrees(GhostQuat a, GhostQuat b) {
    float dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    if (dot < 0.0f) dot = -dot;
    if (dot > 1.0f) dot = 1.0f;
    return 2.0f * acosf(dot) * (180.0f / 3.14159265f);
}

/* Aim point: head, chest or hip, selected by the packed `aim_bone`. */
static int aim_point(Il2CppObject *player, int bone, GhostVec3 *out) {
    GhostVec3 root, head;
    if (!ghost_player_root(player, &root)) return 0;
    if (!ghost_player_head(player, &head)) return 0;

    if (bone == 0) {
        *out = head;
    } else if (bone == 1) {
        out->x = root.x + (head.x - root.x) * 0.72f;
        out->y = root.y + (head.y - root.y) * 0.72f;
        out->z = root.z + (head.z - root.z) * 0.72f;
    } else {
        out->x = root.x;
        out->y = root.y + (head.y - root.y) * 0.38f;
        out->z = root.z;
    }
    return 1;
}

static int target_is_valid(Il2CppObject *player, Il2CppObject *local,
                           Il2CppObject *camera, GhostVec3 cameraForward,
                           const ghost_settings_t *s, float *angleOut) {
    if (player == NULL || player == local) return 0;
    if (ghost_player_is_local(player)) return 0;
    if (ghost_player_is_teammate(player)) return 0;
    if (ghost_player_is_downed(player)) {
        if (s->flags & GHOST_FLAG_AIM_KNOCKED) return 0;
    }

    int hp = 0, maxHP = 0;
    ghost_player_health(player, &hp, &maxHP);
    if (hp <= 0) return 0;

    float distance = ghost_game_distance(player, local);
    if (distance < 0.0f || distance > s->aim_max_distance) return 0;

    if ((s->flags & GHOST_FLAG_AIM_VISIBLE) && !ghost_player_visible(player)) {
        return 0;
    }

    GhostVec3 point;
    if (!aim_point(player, s->aim_bone, &point)) return 0;

    GhostVec3 cameraPosition;
    if (!ghost_camera_position(camera, &cameraPosition)) return 0;

    GhostVec3 direction = normalize3(sub3(point, cameraPosition));
    float dot = dot3(direction, cameraForward);
    if (dot > 1.0f) dot = 1.0f;
    if (dot < -1.0f) dot = -1.0f;
    float angle = acosf(dot) * (180.0f / 3.14159265f);
    if (angle > s->aim_fov * 0.5f) return 0;

    if (angleOut != NULL) *angleOut = angle;
    return 1;
}

static void write_aim(Il2CppObject *local, Il2CppObject *camera,
                      GhostQuat rotation, double now) {
    /* Same order as the managed path: the camera transform moves first, then
       the state field, then the game's own setter — which reads the field and
       rebuilds from it. The setter is rationed to ~30 Hz so the countable
       trace matches the managed commit interval instead of every frame. */
    Il2CppObject *transform = ghost_camera_transform(camera);
    if (transform != NULL && ghost.transform_setRotation != NULL) {
        void *rotationArgs[1] = { &rotation };
        ghost_call_void(ghost.transform_setRotation, transform, rotationArgs);
    }

    if (ghost.player_aimRotationOffset > 0) {
        *(GhostQuat *)((char *)local + ghost.player_aimRotationOffset) = rotation;
    }

    if (now - lastSetAim >= 0.033) {
        uint8_t enabled = 1;
        void *args[2] = { &rotation, &enabled };
        if (ghost_call_void(ghost.player_setAimRotation, local, args)) {
            lastSetAim = now;
        }
    }

    heldRotation = rotation;
    heldAt = now;
    heldValid = 1;
}

void ghost_aim_reassert(void) {
    if (!ghost.ready || !heldValid) return;
    if (now_seconds() - heldAt > 0.25) {
        heldValid = 0;
        return;
    }
    const ghost_settings_t *s = ghost_channel_current();
    if (!(s->flags & GHOST_FLAG_AIM)) return;

    Il2CppObject *camera = ghost_camera_main();
    if (camera == NULL) return;
    Il2CppObject *transform = ghost_camera_transform(camera);
    if (transform == NULL || ghost.transform_setRotation == NULL) return;
    void *args[1] = { &heldRotation };
    ghost_call_void(ghost.transform_setRotation, transform, args);
}

void ghost_aim_tick(void *self) {
    if (!ghost.ready || self == NULL) return;

    double now = now_seconds();
    ghost_channel_tick();

    const ghost_settings_t *s = ghost_channel_current();
    if (!(s->flags & GHOST_FLAG_AIM)) {
        stickyTarget = NULL;
        return;
    }

    /* The gate keeps the assist quiet until a finger is down, so the solve
       trace matches a hand. The held rotation dies with it, or the OnGUI
       reassert would keep yanking the camera while nothing is touched. */
    if ((s->flags & GHOST_FLAG_AIM_TOUCH) && !aim_touching()) {
        stickyTarget = NULL;
        heldValid = 0;
        return;
    }

    Il2CppObject *local = (Il2CppObject *)self;
    if (!ghost_player_is_local(local)) return;
    if (ghost_player_is_downed(local)) return;

    int localHP = 0, localMax = 0;
    ghost_player_health(local, &localHP, &localMax);
    if (localHP <= 0) return;

    Il2CppObject *camera = ghost_camera_main();
    if (camera == NULL) return;

    GhostVec3 cameraForward;
    if (!ghost_camera_forward(camera, &cameraForward)) return;

    Il2CppObject *players[64];
    Il2CppObject *unused = NULL;
    int count = ghost_game_players(players, 64, &unused);
    if (count <= 0) {
        stickyTarget = NULL;
        return;
    }

    Il2CppObject *best = NULL;
    float bestAngle = 1e9f;

    /* Sticky window: keep the current target while it is still in the list and
       still near the cone. Pointer identity is checked against the live list,
       so a recycled player object can never be dereferenced. */
    if (stickyTarget != NULL) {
        for (int i = 0; i < count; i++) {
            if (players[i] != stickyTarget) continue;
            float angle = 0.0f;
            if (target_is_valid(stickyTarget, local, camera, cameraForward, s, &angle) &&
                angle <= s->aim_fov * 0.62f) {
                best = stickyTarget;
                bestAngle = angle;
            }
            break;
        }
    }

    if (best == NULL) {
        for (int i = 0; i < count; i++) {
            float angle = 0.0f;
            if (!target_is_valid(players[i], local, camera, cameraForward, s, &angle)) {
                continue;
            }
            if (angle < bestAngle) {
                bestAngle = angle;
                best = players[i];
            }
        }
    }

    if (best == NULL) {
        stickyTarget = NULL;
        return;
    }

    if (best != stickyTarget) {
        stickyTarget = best;
        stickySince = now;
    }

    if (now - stickySince < (double)clampf(s->aim_reaction, 0.0f, 1.5f)) return;

    GhostVec3 point;
    if (!aim_point(best, s->aim_bone, &point)) return;

    /* Sub-degree humanisation: displacement in metres, scaled by how far the
       hit-chance knob is below 1. At 100 m this is invisible; at 10 m it is the
       difference between a laser and a hand. */
    float hitChance = clampf(s->aim_hit_chance, 0.0f, 1.0f);
    if (hitChance < 0.995f) {
        float amount = (1.0f - hitChance) * 0.55f;
        float phase = (float)now * 2.3f;
        point.x += sinf(phase) * amount;
        point.y += sinf(phase * 1.7f + 1.3f) * amount * 0.35f;
        point.z += cosf(phase * 0.9f) * amount * 0.6f;
    }

    GhostVec3 cameraPosition;
    if (!ghost_camera_position(camera, &cameraPosition)) return;

    GhostVec3 direction = normalize3(sub3(point, cameraPosition));
    GhostQuat desired;
    if (!ghost_look_rotation(direction, &desired)) return;

    GhostQuat current;
    if (!ghost_camera_rotation(camera, &current)) return;

    double delta = now - lastTick;
    lastTick = now;
    float dt = (float)clampf((float)delta, 0.001f, 0.05f);

    float smooth = clampf(s->aim_smooth, 0.02f, 1.0f);
    float angle = quat_angle_degrees(current, desired);

    /* Turn-rate cap: aim_max_turn is degrees per second. */
    float maxTurn = s->aim_max_turn * dt;
    if (maxTurn > 0.0f && angle > maxTurn && angle > 0.001f) {
        smooth = maxTurn / angle;
    }
    smooth = clampf(smooth, 0.0f, 1.0f);

    GhostQuat step;
    if (!ghost_slerp(current, desired, smooth, &step)) return;

    write_aim(local, camera, step, now);
}

static void lateupdate_replacement(void *self) {
    if (originalLateUpdate != NULL) originalLateUpdate(self);
    ghost_aim_tick(self);
}

int ghost_aim_install(void) {
    if (hookInstalled) return 1;
    if (!ghost.ready || ghost.player_lateUpdate == NULL) return 0;

    void **slot = (void **)ghost.player_lateUpdate;
    if (*slot == NULL) return 0;

    if (ghost_hook_pointer(slot, (void *)lateupdate_replacement,
                           (void **)&originalLateUpdate) != 0) {
        return 0;
    }
    hookInstalled = 1;
    return 1;
}

int ghost_aim_ready(void) {
    return hookInstalled;
}
