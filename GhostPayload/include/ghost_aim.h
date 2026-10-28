//
//  ghost_aim.h — the LateUpdate hook.
//

#ifndef GHOST_AIM_H
#define GHOST_AIM_H

/* Hook Player.LateUpdate. Must run on Unity's main thread. Returns 1 when the
   hook is live, 0 when the method pointer is not compiled yet. */
int ghost_aim_install(void);

/* One solve, called from the LateUpdate replacement for every player. */
void ghost_aim_tick(void *self);

/* Reapply the last solved rotation to the camera transform. Called from the
   OnGUI Repaint pass, after the camera controller may have overwritten it. */
void ghost_aim_reassert(void);

int ghost_aim_ready(void);

#endif /* GHOST_AIM_H */
