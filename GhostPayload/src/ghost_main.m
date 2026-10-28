//
//  ghost_main.m — the payload's entry point.
//
//  The dylib is mapped by `GhostInjector` while the game is still inside
//  `UIApplicationMain` and before IL2CPP has a domain. This constructor only
//  starts a waiting thread; the thread does the real work once the runtime is
//  up, then hops to the main queue to create the driver GameObject and install
//  the two hooks.
//
//  No file is written, no environment is required (the port is optional), and
//  the payload never talks to the container.
//

#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdlib.h>
#import <unistd.h>

#include "ghost.h"
#include "ghost_aim.h"
#include "ghost_channel.h"
#include "ghost_esp.h"
#include "ghost_game.h"
#include "ghost_il2cpp.h"
#include "ghost_menu.h"

static int ghost_port(void) {
    const char *value = getenv(GHOST_ENV_PORT);
    if (value != NULL) {
        int port = atoi(value);
        if (port > 0 && port < 65536) return port;
    }
    return GHOST_DEFAULT_PORT;
}

static void ghost_install_retry(int attempt) {
    if (!ghost.ready) return;

    if (!ghost_aim_ready()) ghost_aim_install();
    if (!ghost_esp_ready()) ghost_esp_install();

    if (ghost_aim_ready() && ghost_esp_ready()) {
        NSLog(@"[ghost] hooks live — aim=%d esp=%d",
              ghost_aim_ready(), ghost_esp_ready());
        return;
    }

    /* The driver's OnGUI compiles on its first frame; LateUpdate is already
       compiled. A few hundred retries cover a slow first frame on a cold
       start without ever giving up on a pause/resume. */
    if (attempt > 200) {
        NSLog(@"[ghost] install timed out — aim=%d esp=%d",
              ghost_aim_ready(), ghost_esp_ready());
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        ghost_install_retry(attempt + 1);
    });
}

static void *ghost_bootstrap(void *context) {
    (void)context;
    int announced = 0;
    while (!ghost_il2cpp_ready()) {
        if (!announced) {
            NSLog(@"[ghost] waiting for il2cpp");
            announced = 1;
        }
        usleep(200 * 1000);
    }

    while (!ghost_game_resolve()) {
        usleep(200 * 1000);
    }
    NSLog(@"[ghost] il2cpp ready — COW.GamePlay.Player resolved");

    dispatch_async(dispatch_get_main_queue(), ^{
        ghost_channel_defaults();
        ghost_channel_set_image_handler(ghost_menu_on_image);
        ghost_channel_open(ghost_port());
        ghost_install_retry(0);
    });
    return NULL;
}

__attribute__((constructor))
static void ghost_entry(void) {
    NSLog(@"[ghost] payload mapped");
    pthread_t thread;
    if (pthread_create(&thread, NULL, ghost_bootstrap, NULL) == 0) {
        pthread_detach(thread);
    }
}
