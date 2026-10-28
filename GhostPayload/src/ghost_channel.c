//
//  ghost_channel.c — the app pushes a packed struct over 127.0.0.1.
//
//  This replaces `localConfig.json`. A loopback socket leaves nothing in the
//  game's sandbox, so there is no file to backdate and nothing for a container
//  sweep to find.
//

#include "ghost_channel.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static int channelFD = -1;
static int channelPort = GHOST_DEFAULT_PORT;
static double lastAttempt;
static double lastTick;
static uint8_t rx[131072];
static size_t rxLength;
static ghost_settings_t current;
static int currentSeq = -1;
static void (*imageHandler)(const uint8_t *rgba, int width, int height);

static double monotonic(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static uint32_t crc32(const uint8_t *data, size_t length) {
    uint32_t crc = 0xFFFFFFFFu;
    for (size_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc >> 1) ^ (0xEDB88320u & (uint32_t)(-(int32_t)(crc & 1)));
        }
    }
    return ~crc;
}

void ghost_channel_defaults(void) {
    memset(&current, 0, sizeof(current));
    current.magic = GHOST_MAGIC;
    current.version = GHOST_VERSION;
    current.flags = GHOST_FLAG_ESP | GHOST_FLAG_BOX | GHOST_FLAG_NAME |
                    GHOST_FLAG_DISTANCE | GHOST_FLAG_HEALTH;
    current.esp_max_distance = 250.0f;
    current.esp_box_scale = 1.15f;
    current.esp_text_scale = 1.0f;
    current.esp_fill_alpha = 0.16f;
    current.aim_fov = 150.0f;
    current.aim_smooth = 0.18f;
    current.aim_max_distance = 200.0f;
    current.aim_hit_chance = 0.85f;
    current.aim_reaction = 0.18f;
    current.aim_max_turn = 110.0f;
    current.palette = 0;
    current.box_style = 0;
    current.aim_bone = 0;
    current.seq = 0;
}

const ghost_settings_t *ghost_channel_current(void) { return &current; }

void ghost_channel_patch_flags(uint32_t set, uint32_t clear) {
    current.flags = (current.flags | set) & ~clear;
}

void ghost_channel_set_image_handler(void (*handler)(const uint8_t *rgba,
                                                     int width, int height)) {
    imageHandler = handler;
}

void ghost_channel_tick(void) {
    double now = monotonic();
    if (now - lastTick < 0.20) return;
    lastTick = now;
    ghost_channel_poll(NULL);
}

int ghost_channel_open(int port) {
    if (port > 0) channelPort = port;
    if (channelFD >= 0) return 0;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)channelPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int rc = connect(fd, (struct sockaddr *)&address, sizeof(address));
    if (rc != 0 && errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    channelFD = fd;
    rxLength = 0;
    return 0;
}

int ghost_channel_poll(ghost_settings_t *out) {
    double now = monotonic();
    if (channelFD < 0) {
        if (now - lastAttempt < 0.5) return 0;
        lastAttempt = now;
        if (ghost_channel_open(channelPort) != 0) return 0;
    }

    if (rxLength > sizeof(rx) - 4096) rxLength = 0; /* corrupt oversized frame */

    ssize_t got = recv(channelFD, rx + rxLength, sizeof(rx) - rxLength, 0);
    if (got == 0) {
        close(channelFD);
        channelFD = -1;
        rxLength = 0;
        return 0;
    }
    if (got < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) return 0;
        close(channelFD);
        channelFD = -1;
        rxLength = 0;
        return 0;
    }
    rxLength += (size_t)got;

    int applied = 0;
    for (;;) {
        if (rxLength < 4) break;
        uint32_t magic = 0;
        memcpy(&magic, rx, 4);

        /* Icon frame: magic, width, height, size, then size bytes of RGBA. */
        if (magic == GHOST_MAGIC_IMAGE) {
            if (rxLength < 16) break;
            uint32_t width = 0, height = 0, size = 0;
            memcpy(&width, rx + 4, 4);
            memcpy(&height, rx + 8, 4);
            memcpy(&size, rx + 12, 4);
            if (width == 0 || height == 0 || width > 160 || height > 160 ||
                size != width * height * 4 || size > 0x1FF00u) {
                memmove(rx, rx + 1, rxLength - 1); /* resync */
                rxLength -= 1;
                continue;
            }
            uint32_t total = 16u + size;
            if (rxLength < total) break; /* wait for the rest */
            if (imageHandler != NULL) {
                imageHandler(rx + 16, (int)width, (int)height);
            }
            memmove(rx, rx + total, rxLength - total);
            rxLength -= total;
            continue;
        }

        if (magic != GHOST_MAGIC) {
            memmove(rx, rx + 1, rxLength - 1); /* resync */
            rxLength -= 1;
            continue;
        }

        if (rxLength < sizeof(ghost_settings_t)) break;
        ghost_settings_t candidate;
        memcpy(&candidate, rx, sizeof(candidate));
        memmove(rx, rx + sizeof(candidate), rxLength - sizeof(candidate));
        rxLength -= sizeof(candidate);

        if (candidate.version != GHOST_VERSION) continue;
        uint32_t expected = crc32((const uint8_t *)&candidate,
                                  sizeof(candidate) - sizeof(uint32_t));
        if (expected != candidate.crc) continue;
        if ((int)candidate.seq == currentSeq) continue;

        currentSeq = (int)candidate.seq;
        current = candidate;
        applied = 1;
    }

    if (applied && out != NULL) *out = current;
    return applied;
}
