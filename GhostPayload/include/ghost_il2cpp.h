//
//  ghost_il2cpp.h — the only IL2CPP surface the payload needs.
//
//  Everything is resolved through dlsym at runtime. No header from Unity is
//  shipped, no struct layout is assumed beyond the two the runtime documents
//  (Il2CppObject and MethodInfo's leading methodPointer), and no offset from
//  the dump is baked in. That is what makes the route survive a game update.
//

#ifndef GHOST_IL2CPP_H
#define GHOST_IL2CPP_H

#include <stdint.h>
#include <stddef.h>

typedef struct Il2CppDomain Il2CppDomain;
typedef struct Il2CppAssembly Il2CppAssembly;
typedef struct Il2CppImage Il2CppImage;
typedef struct Il2CppClass Il2CppClass;
typedef struct Il2CppObject Il2CppObject;
typedef struct Il2CppString Il2CppString;
typedef struct Il2CppException Il2CppException;
typedef struct Il2CppType Il2CppType;
typedef struct MethodInfo MethodInfo;
typedef struct FieldInfo FieldInfo;

/* Il2CppObject's documented prefix: every managed object starts with its
   class and its monitor. Anything after that is the instance's own fields. */
typedef struct {
    Il2CppClass *klass;
    void *monitor;
} GhostObject;

typedef struct { float x, y, z; } GhostVec3;
typedef struct { float x, y, z, w; } GhostQuat;
typedef struct { float r, g, b, a; } GhostColor;
typedef struct { float x, y, width, height; } GhostRect;

/* Resolve every entry point. Returns 1 when the runtime answered, 0 when the
   symbols are not exported (some hardened builds strip them). Safe to call
   repeatedly; the second call is a no-op. */
int ghost_il2cpp_init(void);

/* Domain readiness — the assemblies are not populated until the runtime has
   initialised, so this is the real gate, not the symbol resolution. */
int ghost_il2cpp_ready(void);

/* Class lookup by (namespace, name) over every loaded image. */
Il2CppClass *ghost_class(const char *ns, const char *name);

/* Method lookup on a class. `params` is the argument count, or -1 to accept the
   only overload with that name. Returns NULL when ambiguous or absent. */
const MethodInfo *ghost_method(Il2CppClass *klass, const char *name, int params);

/* Field offset on a class, or -1. */
long ghost_field_offset(Il2CppClass *klass, const char *name);

/* Invoke helpers. `obj` is the instance for instance methods, NULL for statics.
   `params` is the same array il2cpp_runtime_invoke expects. Value-type results
   come back unboxed into the out pointer. */
Il2CppObject *ghost_call_obj(const MethodInfo *m, void *obj, void **params);
int ghost_call_i32(const MethodInfo *m, void *obj, void **params, int32_t *out);
int ghost_call_f32(const MethodInfo *m, void *obj, void **params, float *out);
int ghost_call_bool(const MethodInfo *m, void *obj, void **params, int *out);
int ghost_call_void(const MethodInfo *m, void *obj, void **params);
int ghost_call_vec3(const MethodInfo *m, void *obj, void **params, GhostVec3 *out);
int ghost_call_vec2(const MethodInfo *m, void *obj, void **params, float *x, float *y);
int ghost_call_quat(const MethodInfo *m, void *obj, void **params, GhostQuat *out);

/* Managed string from a C string. NULL on failure. */
Il2CppString *ghost_string(const char *utf8);

/* Type object for a class, for AddComponent(Type). */
Il2CppObject *ghost_type_object(Il2CppClass *klass);

/* Allocate an uninitialised instance (the .ctor is invoked separately). */
Il2CppObject *ghost_object_new(Il2CppClass *klass);

/* Class of a method's return type, without needing an instance. Used to reach
   the obfuscated match type from `GameFacade.CurrentMatch`'s signature. */
Il2CppClass *ghost_return_class(const MethodInfo *method);

/* Walk a class's methods looking for the one that returns a player list.
   Returns NULL when nothing matches, which is the signal to fall back to the
   per-frame scan. */
const MethodInfo *ghost_find_player_list_method(Il2CppClass *matchClass);

/* Last exception message, for the log. Empty when the last call was clean. */
const char *ghost_last_error(void);

/* True when the last invoke raised. Clears the flag. */
int ghost_take_error(void);

#endif /* GHOST_IL2CPP_H */
