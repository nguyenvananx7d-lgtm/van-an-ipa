//
//  ghost_il2cpp.c — runtime symbol resolution and the invoke helpers.
//

#include "ghost_il2cpp.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* ---- resolved entry points ------------------------------------------------ */

typedef struct {
    Il2CppDomain *(*domain_get)(void);
    const Il2CppAssembly **(*domain_get_assemblies)(const Il2CppDomain *, size_t *);
    Il2CppImage *(*assembly_get_image)(const Il2CppAssembly *);
    size_t (*image_get_class_count)(const Il2CppImage *);
    Il2CppClass *(*image_get_class)(const Il2CppImage *, size_t);
    Il2CppClass *(*class_from_name)(const Il2CppImage *, const char *, const char *);
    const MethodInfo *(*class_get_method_from_name)(Il2CppClass *, const char *, int);
    void *(*class_get_methods)(Il2CppClass *, void **);
    const char *(*method_get_name)(const MethodInfo *);
    uint32_t (*method_get_param_count)(const MethodInfo *);
    const Il2CppType *(*method_get_return_type)(const MethodInfo *);
    char *(*type_get_name)(const Il2CppType *);
    Il2CppClass *(*class_from_type)(const Il2CppType *);
    const MethodInfo *(*object_get_virtual_method)(Il2CppObject *, const MethodInfo *);
    const char *(*class_get_name)(Il2CppClass *);
    const char *(*class_get_namespace)(Il2CppClass *);
    FieldInfo *(*class_get_field_from_name)(Il2CppClass *, const char *);
    size_t (*field_get_offset)(FieldInfo *);
    Il2CppObject *(*runtime_invoke)(const MethodInfo *, void *, void **, Il2CppException **);
    void *(*object_unbox)(Il2CppObject *);
    Il2CppString *(*string_new)(const char *);
    Il2CppType *(*class_get_type)(Il2CppClass *);
    Il2CppObject *(*type_get_object)(const Il2CppType *);
    Il2CppObject *(*object_new)(Il2CppClass *);
} GhostApi;

static GhostApi api;
static int resolved;
static char lastError[192];

/* ---- small helpers -------------------------------------------------------- */

static void set_error(const char *text) {
    if (text == NULL) text = "unknown";
    snprintf(lastError, sizeof(lastError), "%s", text);
}

const char *ghost_last_error(void) { return lastError; }

int ghost_take_error(void) {
    int had = lastError[0] != '\0';
    lastError[0] = '\0';
    return had;
}

static void *sym(const char *name) {
    /* RTLD_DEFAULT covers a build where Unity is the main image; the explicit
       UnityFramework handle covers 2019.3+ where IL2CPP lives in a framework
       and its symbols are not exported to the global scope. */
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p != NULL) return p;
    static void *unity;
    if (unity == NULL) {
        unity = dlopen("UnityFramework", RTLD_NOW | RTLD_NOLOAD);
        if (unity == NULL) {
            unity = dlopen("@rpath/UnityFramework.framework/UnityFramework",
                           RTLD_NOW | RTLD_NOLOAD);
        }
    }
    if (unity != NULL) return dlsym(unity, name);
    return NULL;
}

int ghost_il2cpp_init(void) {
    if (resolved) return 1;
    memset(&api, 0, sizeof(api));
    api.domain_get = sym("il2cpp_domain_get");
    api.domain_get_assemblies = sym("il2cpp_domain_get_assemblies");
    api.assembly_get_image = sym("il2cpp_assembly_get_image");
    api.image_get_class_count = sym("il2cpp_image_get_class_count");
    api.image_get_class = sym("il2cpp_image_get_class");
    api.class_from_name = sym("il2cpp_class_from_name");
    api.class_get_method_from_name = sym("il2cpp_class_get_method_from_name");
    api.class_get_methods = sym("il2cpp_class_get_methods");
    api.method_get_name = sym("il2cpp_method_get_name");
    api.method_get_param_count = sym("il2cpp_method_get_param_count");
    api.method_get_return_type = sym("il2cpp_method_get_return_type");
    api.type_get_name = sym("il2cpp_type_get_name");
    api.class_from_type = sym("il2cpp_class_from_type");
    api.object_get_virtual_method = sym("il2cpp_object_get_virtual_method");
    api.class_get_name = sym("il2cpp_class_get_name");
    api.class_get_namespace = sym("il2cpp_class_get_namespace");
    api.class_get_field_from_name = sym("il2cpp_class_get_field_from_name");
    api.field_get_offset = sym("il2cpp_field_get_offset");
    api.runtime_invoke = sym("il2cpp_runtime_invoke");
    api.object_unbox = sym("il2cpp_object_unbox");
    api.string_new = sym("il2cpp_string_new");
    api.class_get_type = sym("il2cpp_class_get_type");
    api.type_get_object = sym("il2cpp_type_get_object");
    api.object_new = sym("il2cpp_object_new");

    if (api.domain_get == NULL || api.class_from_name == NULL ||
        api.runtime_invoke == NULL) {
        set_error("il2cpp exports not visible");
        return 0;
    }
    resolved = 1;
    return 1;
}

int ghost_il2cpp_ready(void) {
    if (!resolved && !ghost_il2cpp_init()) return 0;
    if (api.domain_get == NULL || api.domain_get_assemblies == NULL) return 0;
    Il2CppDomain *domain = api.domain_get();
    if (domain == NULL) return 0;
    size_t count = 0;
    const Il2CppAssembly **assemblies = api.domain_get_assemblies(domain, &count);
    return assemblies != NULL && count > 0;
}

/* ---- class cache ---------------------------------------------------------- */

typedef struct {
    char key[128];
    Il2CppClass *klass;
} GhostClassSlot;

static GhostClassSlot classCache[64];
static int classCacheCount;

Il2CppClass *ghost_class(const char *ns, const char *name) {
    if (!resolved && !ghost_il2cpp_init()) return NULL;
    if (ns == NULL) ns = "";
    if (name == NULL) return NULL;
    if (api.class_from_name == NULL || api.domain_get == NULL ||
        api.domain_get_assemblies == NULL || api.assembly_get_image == NULL) {
        return NULL;
    }

    char key[128];
    snprintf(key, sizeof(key), "%s::%s", ns, name);
    for (int i = 0; i < classCacheCount; i++) {
        if (strcmp(classCache[i].key, key) == 0) return classCache[i].klass;
    }

    Il2CppDomain *domain = api.domain_get();
    if (domain == NULL) return NULL;
    size_t count = 0;
    const Il2CppAssembly **assemblies = api.domain_get_assemblies(domain, &count);
    if (assemblies == NULL) return NULL;

    Il2CppClass *found = NULL;
    for (size_t i = 0; i < count && found == NULL; i++) {
        Il2CppImage *image = api.assembly_get_image(assemblies[i]);
        if (image == NULL) continue;
        found = api.class_from_name(image, ns, name);
    }

    if (found != NULL && classCacheCount < 64) {
        snprintf(classCache[classCacheCount].key,
                 sizeof(classCache[classCacheCount].key), "%s", key);
        classCache[classCacheCount].klass = found;
        classCacheCount++;
    }
    return found;
}

const MethodInfo *ghost_method(Il2CppClass *klass, const char *name, int params) {
    if (klass == NULL || name == NULL) return NULL;
    if (params >= 0) {
        if (api.class_get_method_from_name == NULL) return NULL;
        return api.class_get_method_from_name(klass, name, params);
    }
    if (api.class_get_methods == NULL || api.method_get_name == NULL) return NULL;
    void *iter = NULL;
    const MethodInfo *candidate = NULL;
    int matches = 0;
    const MethodInfo *m;
    while ((m = api.class_get_methods(klass, &iter)) != NULL) {
        const char *methodName = api.method_get_name(m);
        if (methodName != NULL && strcmp(methodName, name) == 0) {
            candidate = m;
            matches++;
        }
    }
    return matches == 1 ? candidate : NULL;
}

long ghost_field_offset(Il2CppClass *klass, const char *name) {
    if (klass == NULL || name == NULL) return -1;
    if (api.class_get_field_from_name == NULL || api.field_get_offset == NULL) {
        return -1;
    }
    FieldInfo *field = api.class_get_field_from_name(klass, name);
    if (field == NULL) return -1;
    return (long)api.field_get_offset(field);
}

Il2CppString *ghost_string(const char *utf8) {
    if (api.string_new == NULL || utf8 == NULL) return NULL;
    return api.string_new(utf8);
}

Il2CppObject *ghost_type_object(Il2CppClass *klass) {
    if (klass == NULL || api.class_get_type == NULL || api.type_get_object == NULL) {
        return NULL;
    }
    return api.type_get_object(api.class_get_type(klass));
}

Il2CppClass *ghost_return_class(const MethodInfo *method) {
    if (method == NULL || api.method_get_return_type == NULL ||
        api.class_from_type == NULL) {
        return NULL;
    }
    const Il2CppType *type = api.method_get_return_type(method);
    if (type == NULL) return NULL;
    return api.class_from_type(type);
}

Il2CppObject *ghost_object_new(Il2CppClass *klass) {
    if (klass == NULL || api.object_new == NULL) return NULL;
    return api.object_new(klass);
}

/* ---- invoke --------------------------------------------------------------- */

static const MethodInfo *virtual_method(const MethodInfo *m, void *obj) {
    /* A MethodInfo found on a base class calls the base body. For the handful
       of virtual readers (`IsVisible`, `IsLocalTeammate`, `GetHeadTF`) the
       override is what the game itself would run, so resolve it when the
       runtime exports the lookup. Non-virtual methods return themselves. */
    if (m == NULL || obj == NULL || api.object_get_virtual_method == NULL) return m;
    const MethodInfo *resolved =
        api.object_get_virtual_method((Il2CppObject *)obj, m);
    return resolved != NULL ? resolved : m;
}

static Il2CppObject *invoke(const MethodInfo *m, void *obj, void **params) {
    lastError[0] = '\0';
    if (m == NULL || api.runtime_invoke == NULL) {
        set_error("null method");
        return NULL;
    }
    m = virtual_method(m, obj);
    Il2CppException *exc = NULL;
    Il2CppObject *result = api.runtime_invoke(m, obj, params, &exc);
    if (exc != NULL) {
        /* The exception class name is enough to tell "method threw" from
           "wrong signature" in the log, and reading it needs no reflection. */
        GhostObject *header = (GhostObject *)exc;
        if (header->klass != NULL && api.class_get_name != NULL) {
            set_error(api.class_get_name(header->klass));
        } else {
            set_error("managed exception");
        }
        return NULL;
    }
    return result;
}

Il2CppObject *ghost_call_obj(const MethodInfo *m, void *obj, void **params) {
    return invoke(m, obj, params);
}

int ghost_call_void(const MethodInfo *m, void *obj, void **params) {
    invoke(m, obj, params);
    return lastError[0] == '\0';
}

int ghost_call_bool(const MethodInfo *m, void *obj, void **params, int *out) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    if (out != NULL) *out = *(uint8_t *)api.object_unbox(boxed) != 0;
    return 1;
}

int ghost_call_i32(const MethodInfo *m, void *obj, void **params, int32_t *out) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    if (out != NULL) *out = *(int32_t *)api.object_unbox(boxed);
    return 1;
}

int ghost_call_f32(const MethodInfo *m, void *obj, void **params, float *out) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    if (out != NULL) *out = *(float *)api.object_unbox(boxed);
    return 1;
}

int ghost_call_vec3(const MethodInfo *m, void *obj, void **params, GhostVec3 *out) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    if (out != NULL) *out = *(GhostVec3 *)api.object_unbox(boxed);
    return 1;
}

int ghost_call_vec2(const MethodInfo *m, void *obj, void **params, float *x, float *y) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    const float *v = (const float *)api.object_unbox(boxed);
    if (x != NULL) *x = v[0];
    if (y != NULL) *y = v[1];
    return 1;
}

int ghost_call_quat(const MethodInfo *m, void *obj, void **params, GhostQuat *out) {
    Il2CppObject *boxed = invoke(m, obj, params);
    if (boxed == NULL || api.object_unbox == NULL) return 0;
    if (out != NULL) *out = *(GhostQuat *)api.object_unbox(boxed);
    return 1;
}

/* ---- player list discovery ------------------------------------------------ */

const MethodInfo *ghost_find_player_list_method(Il2CppClass *matchClass) {
    if (matchClass == NULL || api.class_get_methods == NULL ||
        api.method_get_param_count == NULL || api.method_get_return_type == NULL ||
        api.type_get_name == NULL || api.method_get_name == NULL) {
        return NULL;
    }

    /* The accessor has to return a `List<Player>`: `ghost_game_players` reads
       it with `get_Count` + `get_Item(int)`. A `Dictionary<id, Player>` also
       has those names, but its indexer takes a key, not an ordinal, so taking
       the first collection-shaped method would corrupt the call. The build's
       own accessor is `ILPNGCMEFFI`; the name is checked first, and the
       signature scan is the update-proof fallback. */
    const MethodInfo *listFallback = NULL;
    void *iter = NULL;
    const MethodInfo *m;
    while ((m = api.class_get_methods(matchClass, &iter)) != NULL) {
        if (api.method_get_param_count(m) != 0) continue;
        const Il2CppType *ret = api.method_get_return_type(m);
        if (ret == NULL) continue;
        char *typeName = api.type_get_name(ret);
        if (typeName == NULL) continue;
        if (strstr(typeName, "Player") == NULL ||
            strstr(typeName, "List") == NULL ||
            strstr(typeName, "Dictionary") != NULL ||
            strstr(typeName, "HashSet") != NULL ||
            strstr(typeName, "ValueCollection") != NULL ||
            strstr(typeName, "KeyCollection") != NULL) {
            continue;
        }

        const char *methodName = api.method_get_name(m);
        if (methodName != NULL && strcmp(methodName, "ILPNGCMEFFI") == 0) {
            return m;
        }
        if (listFallback == NULL) listFallback = m;
    }
    return listFallback;
}
