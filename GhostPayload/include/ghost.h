//
//  ghost.h — shared ABI between the app and the payload.
//
//  The struct below crosses a loopback socket, so it is packed and versioned.
//  The flag bits are deliberately the same bit positions the managed patch uses
//  (`ESPLogic.template.cs`), so a config translated from the app UI means the
//  same thing on both routes.
//

#ifndef GHOST_H
#define GHOST_H

#include <stdint.h>

#define GHOST_MAGIC 0x47485354u /* 'GHST' */
#define GHOST_MAGIC_IMAGE 0x4748494Du /* 'GHIM' — RGBA icon frame */
#define GHOST_VERSION 4

/* Feature bits — same layout as the managed mask. */
#define GHOST_FLAG_ESP          (1u << 0)
#define GHOST_FLAG_BOX          (1u << 1)
#define GHOST_FLAG_NAME         (1u << 2)
#define GHOST_FLAG_DISTANCE     (1u << 3)
#define GHOST_FLAG_HEALTH       (1u << 4)
#define GHOST_FLAG_TRACER       (1u << 6)
#define GHOST_FLAG_FOV_RING     (1u << 10) /* managed EspFov bit */
#define GHOST_FLAG_AIM          (1u << 15)
#define GHOST_FLAG_AIM_VISIBLE  (1u << 16)
#define GHOST_FLAG_AIM_KNOCKED  (1u << 17)
#define GHOST_FLAG_AIM_TOUCH    (1u << 18)

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t version;
    uint32_t flags; /* wide enough for every managed mask bit (v4) */

    float esp_max_distance;
    float esp_box_scale;
    float esp_text_scale;
    float esp_fill_alpha;

    float aim_fov;
    float aim_smooth;
    float aim_max_distance;
    float aim_hit_chance;
    float aim_reaction;
    float aim_max_turn;

    uint8_t palette;
    uint8_t box_style;
    uint8_t aim_bone;
    uint8_t reserved;

    uint32_t seq;
    uint32_t crc;
} ghost_settings_t;

/* Default port; the app passes GHOST_PORT in the child's environment when it
   needs a different one (two devices behind the same debug proxy, etc.). */
#define GHOST_DEFAULT_PORT 47831
#define GHOST_ENV_PORT "GHOST_PORT"

/* Environment variable the injector sets in the child so the payload can log
   under a name the app can find without a file. */
#define GHOST_ENV_TOKEN "GHOST_TOKEN"

#endif /* GHOST_H */
