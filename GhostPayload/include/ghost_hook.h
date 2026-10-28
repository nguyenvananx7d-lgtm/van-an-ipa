//
//  ghost_hook.h — in-process inline hooks for arm64.
//
//  A 16-byte absolute branch is written over the target's prologue and a
//  trampoline on a fresh page replays the displaced instructions and jumps
//  back. This is the same stub shape `taskport_build_trampoline` uses, but it
//  runs entirely inside our own address space, so it needs no task port, no
//  kernel write and no `disable_excguard_kill`.
//

#ifndef GHOST_HOOK_H
#define GHOST_HOOK_H

#include <stdint.h>

/* Returns 0 on success. `original_out` receives a callable trampoline that
   performs the displaced prologue and continues into the original body.
   Returns -2 when the prologue contains a PC-relative instruction that cannot
   be relocated; the caller must then use a metadata swap instead. */
int ghost_hook_install(void *target, void *replacement, void **original_out);

/* Restore the saved prologue. Safe to call twice. */
int ghost_hook_remove(void *target);

/* Make a page writable/executable. Used by the metadata-swap fallback. */
int ghost_make_writable(void *address, size_t size);

/* Hook a method through its MethodInfo->methodPointer slot.
   Tries an inline branch stub first; if the prologue cannot be relocated, the
   slot itself is swapped. `original_out` is always callable with the method's
   own signature. Returns 0 on success. */
int ghost_hook_pointer(void **slot, void *replacement, void **original_out);

#endif /* GHOST_HOOK_H */
