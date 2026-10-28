//
//  GhostInjector.m — launch + thread-hijack dlopen.
//

#import "GhostInjector.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/arm/thread_status.h>
#import <mach/task_info.h>
#import <mach/thread_info.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <stdarg.h>
#import <stdlib.h>
#import <string.h>
#import <sys/sysctl.h>
#import <unistd.h>

/* The iOS 26 SDK hides <mach/mach_vm.h>; the symbols are still exported. */
#ifndef mach_vm_address_t
typedef uint64_t mach_vm_address_t;
typedef uint64_t mach_vm_size_t;
#endif

extern kern_return_t mach_vm_allocate(mach_port_t target, uint64_t *address,
                                      uint64_t size, int flags);
extern kern_return_t mach_vm_deallocate(mach_port_t target, uint64_t address,
                                        uint64_t size);
extern kern_return_t mach_vm_protect(mach_port_t target, uint64_t address,
                                     uint64_t size, boolean_t set_maximum,
                                     vm_prot_t new_protection);
extern kern_return_t mach_vm_write(mach_port_t target, uint64_t address,
                                   vm_offset_t data, mach_msg_type_number_t data_count);
extern kern_return_t mach_vm_read_overwrite(mach_port_t target, uint64_t address,
                                            uint64_t size, uint64_t data,
                                            uint64_t *outsize);
extern kern_return_t task_for_pid(mach_port_t target, int pid, mach_port_t *task);

typedef int (*GhostSBSLaunch)(CFStringRef identifier, Boolean suspended);
typedef pid_t (*GhostSBSPid)(CFStringRef identifier);

static void ghost_log(void (^log)(NSString *), NSString *format, ...) {
    if (log == nil) return;
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    log(line);
}

static void *ghost_sbs_handle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                        RTLD_NOW);
    });
    return handle;
}

static pid_t ghost_process_id(CFStringRef bundle) {
    void *handle = ghost_sbs_handle();
    if (handle == NULL) return 0;
    GhostSBSPid pidForBundle = (GhostSBSPid)dlsym(handle, "SBSProcessIDForDisplayIdentifier");
    if (pidForBundle == NULL) return 0;
    return pidForBundle(bundle);
}

/* SBSProcessIDForDisplayIdentifier answers 0 on iOS 26 builds even while the
   game is running. The kernel proc table is what a jailed app can still read,
   so the pid is matched by short name. */
static pid_t ghost_scan_pid(const pid_t *exclude) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return 0;
    struct kinfo_proc *procs = malloc(size);
    if (procs == NULL) return 0;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
        free(procs);
        return 0;
    }
    size_t count = size / sizeof(struct kinfo_proc);
    pid_t found = 0;
    for (size_t i = 0; i < count; i++) {
        const char *comm = procs[i].kp_proc.p_comm;
        if (comm[0] == '\0') continue;
        if (strcasestr(comm, "freefire") == NULL &&
            strcasestr(comm, "free fire") == NULL) {
            continue;
        }
        pid_t candidate = procs[i].kp_proc.p_pid;
        if (exclude != NULL && candidate == *exclude) continue;
        found = candidate;
    }
    free(procs);
    return found;
}

/* LSApplicationWorkspace is the second launch route: SpringBoard's launch
   call answers 9 on iOS 26 even when SpringBoard is willing to open the
   title, and the workspace path does not depend on that code. */
static BOOL ghost_workspace_open(CFStringRef bundle) {
    Class cls = NSClassFromString(@"LSApplicationWorkspace");
    if (cls == Nil) return NO;
    id workspace = ((id (*)(id, SEL))objc_msgSend)((id)cls,
                                                   sel_registerName("defaultWorkspace"));
    if (workspace == nil) return NO;
    SEL selector = sel_registerName("openApplicationWithBundleID:");
    if (![workspace respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, selector,
                                                 (__bridge id)bundle);
}

static int ghost_launch(CFStringRef bundle) {
    void *handle = ghost_sbs_handle();
    if (handle == NULL) return -1;
    GhostSBSLaunch launch = (GhostSBSLaunch)dlsym(handle, "SBSLaunchApplicationWithIdentifier");
    if (launch == NULL) return -1;
    return launch(bundle, false);
}

static int ghost_read_remote(mach_port_t task, uint64_t address,
                             void *buffer, uint64_t size) {
    uint64_t read = 0;
    kern_return_t kr = mach_vm_read_overwrite(task, address, size,
                                              (uint64_t)(uintptr_t)buffer, &read);
    return kr == KERN_SUCCESS && read == size;
}

/* Find an image in the target's dyld image list by exact basename. The info
   array covers the shared-cache images too (libdyld included), which is what
   makes remote symbol resolution below possible. */
static int ghost_image_info(mach_port_t task, const char *needle,
                            uint64_t *baseOut) {
    struct task_dyld_info info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    if (task_info(task, TASK_DYLD_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }
    if (info.all_image_info_addr == 0) return 0;

    /* dyld_all_image_infos: version (u32), infoArrayCount (u32), infoArray (ptr). */
    uint8_t header[16];
    if (!ghost_read_remote(task, info.all_image_info_addr, header, sizeof(header))) {
        return 0;
    }
    uint32_t imageCount = 0;
    uint64_t arrayAddress = 0;
    memcpy(&imageCount, header + 4, 4);
    memcpy(&arrayAddress, header + 8, 8);
    if (imageCount == 0 || imageCount > 4096 || arrayAddress == 0) return 0;

    uint64_t entrySize = 24; /* imageLoadAddress, imageFilePath, imageFileModDate */
    for (uint32_t i = 0; i < imageCount; i++) {
        uint8_t entry[24];
        if (!ghost_read_remote(task, arrayAddress + (uint64_t)i * entrySize,
                               entry, sizeof(entry))) {
            continue;
        }
        uint64_t loadAddress = 0;
        uint64_t pathAddress = 0;
        memcpy(&loadAddress, entry, 8);
        memcpy(&pathAddress, entry + 8, 8);
        if (pathAddress == 0) continue;

        char path[1024];
        memset(path, 0, sizeof(path));
        if (!ghost_read_remote(task, pathAddress, path, sizeof(path) - 1)) continue;

        const char *basename = strrchr(path, '/');
        basename = basename != NULL ? basename + 1 : path;
        if (strcmp(basename, needle) == 0) {
            if (baseOut != NULL) *baseOut = loadAddress;
            return 1;
        }
    }
    return 0;
}

static int ghost_image_loaded(mach_port_t task, const char *payloadPath) {
    const char *needle = strrchr(payloadPath, '/');
    needle = needle != NULL ? needle + 1 : payloadPath;
    return ghost_image_info(task, needle, NULL);
}

/* A local symbol's address is meaningless in the target: both processes have
   their own shared-cache slide. dladdr gives the owning image and the offset
   inside it; the offset is slide-independent, so it is reapplied to the same
   image's base in the target. */
static uint64_t ghost_remote_symbol(mach_port_t task, void *localSymbol) {
    Dl_info info;
    if (localSymbol == NULL || dladdr(localSymbol, &info) == 0 ||
        info.dli_fbase == NULL || info.dli_saddr == NULL) {
        return 0;
    }
    const char *path = info.dli_fname;
    const char *basename = strrchr(path, '/');
    basename = basename != NULL ? basename + 1 : path;

    uint64_t remoteBase = 0;
    if (!ghost_image_info(task, basename, &remoteBase)) return 0;

    uint64_t offset = (uint64_t)(uintptr_t)info.dli_saddr -
                      (uint64_t)(uintptr_t)info.dli_fbase;
    return remoteBase + offset;
}

static void ghost_free_threads(thread_act_array_t threads,
                               mach_msg_type_number_t count) {
    if (threads == NULL) return;
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads,
                  count * sizeof(thread_act_t));
}

/* The victim is the least-important thread: idle and not the main thread when
   possible. The main thread is identified by its tid equalling the pid. Only
   when the process has a single thread is the main thread hijacked. */
static int ghost_pick_thread(thread_act_array_t threads,
                             mach_msg_type_number_t count, pid_t pid,
                             thread_act_t *victimOut) {
    thread_act_t nonMain = MACH_PORT_NULL;
    thread_act_t idle = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < count; i++) {
        thread_identifier_info_data_t identifier;
        mach_msg_type_number_t idCount = THREAD_IDENTIFIER_INFO_COUNT;
        int isMain = 0;
        if (thread_info(threads[i], THREAD_IDENTIFIER_INFO,
                        (thread_info_t)&identifier, &idCount) == KERN_SUCCESS &&
            identifier.thread_id == (uint64_t)pid) {
            isMain = 1;
        }
        if (isMain) continue;

        thread_basic_info_data_t basic;
        mach_msg_type_number_t basicCount = THREAD_BASIC_INFO_COUNT;
        int waiting = 0;
        if (thread_info(threads[i], THREAD_BASIC_INFO,
                        (thread_info_t)&basic, &basicCount) == KERN_SUCCESS &&
            (basic.run_state == TH_STATE_WAITING ||
             basic.run_state == TH_STATE_STOPPED)) {
            waiting = 1;
        }
        if (waiting && idle == MACH_PORT_NULL) idle = threads[i];
        if (nonMain == MACH_PORT_NULL) nonMain = threads[i];
    }

    thread_act_t choice = idle != MACH_PORT_NULL ? idle : nonMain;
    if (choice == MACH_PORT_NULL && count > 0) choice = threads[0];
    if (victimOut != NULL) *victimOut = choice;
    return choice != MACH_PORT_NULL;
}

@implementation GhostInjector

+ (NSString *)payloadPath {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"GhostPayload" ofType:@"dylib"];
    if (path != nil) return path;
    NSString *frameworks = [[[NSBundle mainBundle] bundlePath]
                            stringByAppendingPathComponent:@"Frameworks/GhostPayload.dylib"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:frameworks]) return frameworks;
    return nil;
}

+ (BOOL)payloadAvailable {
    return [self payloadPath] != nil;
}

+ (BOOL)taskPortAllowed {
    /* A self test of the task port. This used to be the route gate and was
       briefly replaced by the csops GET_TASK_ALLOW bit — which comes back
       clear on TrollStore signatures even when the entitlements are honoured,
       so the picker fell through to the relay route on working installs.
       The call runs once per process (InjectPlan caches the result) and is a
       kernel round trip, not an XPC one. */
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), getpid(), &task);
    if (kr == KERN_SUCCESS && task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), task);
        return YES;
    }
    return NO;
}

+ (void)terminateBundle:(NSString *)bundleID {
    CFStringRef bundle = (__bridge CFStringRef)bundleID;
    pid_t pid = ghost_process_id(bundle);
    if (pid <= 0) pid = ghost_scan_pid(NULL);
    if (pid <= 0) return;
    kill(pid, SIGKILL);
    usleep(700 * 1000);
}

/* The whole task is suspended before anything is read, so the game cannot
   progress while we pick a thread and set its state — the attach beats
   IL2CPP's first managed call, not just the first frame. */
static NSInteger ghost_map_payload(mach_port_t task, pid_t pid,
                                   const char *payloadPath,
                                   void (^log)(NSString *)) {
    kern_return_t kr;
    NSInteger result = 0;
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t threadCount = 0;
    mach_vm_address_t remote = 0;
    const uint64_t pageSize = 0x4000;
    int taskSuspended = 0;
    int remoteAllocated = 0;
    int victimSuspended = 0;
    thread_act_t victim = MACH_PORT_NULL;
    arm_thread_state64_t saved;
    mach_msg_type_number_t stateCount = ARM_THREAD_STATE64_COUNT;

    kr = task_suspend(task);
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] task_suspend failed: %d", kr);
        result = GhostInjectorErrorThreadState;
        goto cleanup;
    }
    taskSuspended = 1;

    kr = task_threads(task, &threads, &threadCount);
    if (kr != KERN_SUCCESS || threads == NULL || threadCount == 0) {
        ghost_log(log, @"[ghost] task_threads failed: %d", kr);
        result = GhostInjectorErrorThreads;
        goto cleanup;
    }

    if (!ghost_pick_thread(threads, threadCount, pid, &victim)) {
        ghost_log(log, @"[ghost] no runnable thread");
        result = GhostInjectorErrorThreads;
        goto cleanup;
    }

    kr = thread_get_state(victim, ARM_THREAD_STATE64,
                          (thread_state_t)&saved, &stateCount);
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] thread_get_state failed: %d", kr);
        result = GhostInjectorErrorThreadState;
        goto cleanup;
    }

    kr = mach_vm_allocate(task, &remote, pageSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS || remote == 0) {
        ghost_log(log, @"[ghost] mach_vm_allocate failed: %d", kr);
        result = GhostInjectorErrorRemoteMemory;
        goto cleanup;
    }
    remoteAllocated = 1;

    uint8_t *scratch = (uint8_t *)calloc(1, (size_t)pageSize);
    if (scratch == NULL) {
        result = GhostInjectorErrorRemoteMemory;
        goto cleanup;
    }

    /* `b .` at offset 0: the return address for dlopen. x0 survives, so the
       handle is readable from the thread state after the call. */
    uint32_t spin = 0x14000000u;
    memcpy(scratch, &spin, sizeof(spin));
    size_t pathLength = strlen(payloadPath);
    if (pathLength > 0x3000) pathLength = 0x3000;
    memcpy(scratch + 0x100, payloadPath, pathLength);

    kr = mach_vm_write(task, remote, (vm_offset_t)(uintptr_t)scratch,
                       (mach_msg_type_number_t)pageSize);
    free(scratch);
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] mach_vm_write failed: %d", kr);
        result = GhostInjectorErrorRemoteMemory;
        goto cleanup;
    }

    kr = mach_vm_protect(task, remote, pageSize, FALSE,
                         VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] mach_vm_protect failed: %d", kr);
        result = GhostInjectorErrorRemoteMemory;
        goto cleanup;
    }

    uint64_t remoteDlopen = ghost_remote_symbol(task, dlsym(RTLD_DEFAULT, "dlopen"));
    if (remoteDlopen == 0) {
        ghost_log(log, @"[ghost] remote dlopen address unresolved");
        result = GhostInjectorErrorRemoteMemory;
        goto cleanup;
    }

    arm_thread_state64_t hijack = saved;
    hijack.__x[0] = remote + 0x100;       /* path                       */
    hijack.__x[1] = RTLD_NOW;             /* flags                      */
    hijack.__sp = hijack.__sp & ~0xFULL;  /* ABI stack alignment        */
    hijack.__lr = remote;                 /* `b .` after dlopen returns */
    hijack.__pc = remoteDlopen;

    kr = thread_set_state(victim, ARM_THREAD_STATE64,
                          (thread_state_t)&hijack, ARM_THREAD_STATE64_COUNT);
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] thread_set_state failed: %d", kr);
        result = GhostInjectorErrorThreadState;
        goto cleanup;
    }

    /* Release the whole task: the victim runs dlopen while the other threads
       resume their normal early-start work. */
    kr = task_resume(task);
    taskSuspended = 0;
    if (kr != KERN_SUCCESS) {
        ghost_log(log, @"[ghost] task_resume failed: %d", kr);
        result = GhostInjectorErrorThreadState;
        goto cleanup;
    }
    ghost_log(log, @"[ghost] dlopen(%s) dispatched", payloadPath);

    int returned = 0;
    uint64_t handle = 0;
    for (int i = 0; i < 600; i++) { /* 12 s */
        usleep(20 * 1000);
        arm_thread_state64_t probe;
        mach_msg_type_number_t probeCount = ARM_THREAD_STATE64_COUNT;
        if (thread_get_state(victim, ARM_THREAD_STATE64,
                             (thread_state_t)&probe, &probeCount) != KERN_SUCCESS) {
            break;
        }
        if (probe.__pc == (uint64_t)remote) {
            returned = 1;
            handle = probe.__x[0];
            break;
        }
    }

    if (!returned) {
        /* The thread is still inside dlopen. Restoring its state would
           abandon a half-finished dyld call, so the game is killed instead;
           the caller retries with a fresh cold start. */
        ghost_log(log, @"[ghost] dlopen did not return — killing target");
        kill(pid, SIGKILL);
        result = GhostInjectorErrorTimeout;
        goto cleanup;
    }

    /* Stop the spinning victim, replay its real state, let it continue. */
    kr = thread_suspend(victim);
    if (kr == KERN_SUCCESS) {
        victimSuspended = 1;
        stateCount = ARM_THREAD_STATE64_COUNT;
        thread_set_state(victim, ARM_THREAD_STATE64,
                         (thread_state_t)&saved, ARM_THREAD_STATE64_COUNT);
    }
    if (victimSuspended) thread_resume(victim);
    victimSuspended = 0;

    int loaded = ghost_image_loaded(task, payloadPath);

    if (handle == 0) {
        ghost_log(log, @"[ghost] dlopen returned NULL");
        result = GhostInjectorErrorDlopenFailed;
        goto cleanup;
    }
    ghost_log(log, @"[ghost] dlopen handle 0x%llx, image %@",
              handle, loaded ? @"visible" : @"not found (loaded anyway)");
    result = 0;

cleanup:
    if (victimSuspended) thread_resume(victim);
    if (remoteAllocated) mach_vm_deallocate(task, remote, pageSize);
    ghost_free_threads(threads, threadCount);
    if (taskSuspended) task_resume(task);
    return result;
}

+ (NSInteger)launchBundle:(NSString *)bundleID
                  payload:(NSString *)payloadPath
                      log:(void (^)(NSString *))log {
    if (![[NSFileManager defaultManager] fileExistsAtPath:payloadPath]) {
        ghost_log(log, @"[ghost] payload missing: %@", payloadPath);
        return GhostInjectorErrorPayloadMissing;
    }

    CFStringRef bundle = (__bridge CFStringRef)bundleID;
    ghost_log(log, @"[ghost] launching %@", bundleID);

    int launchResult = ghost_launch(bundle);
    if (launchResult != 0) {
        /* A warm process answers the pid query below; a hard launch failure
           with no pid is the only fatal case. */
        ghost_log(log, @"[ghost] SBS launch returned %d (continuing)", launchResult);
    }

    pid_t pid = 0;
    BOOL triedWorkspace = NO;
    for (int i = 0; i < 400; i++) { /* 8 s */
        pid = ghost_process_id(bundle);
        if (pid <= 0) pid = ghost_scan_pid(NULL);
        if (pid > 0) break;
        if (!triedWorkspace && i >= 75) { /* ~1.5 s with nothing: second route */
            triedWorkspace = YES;
            BOOL opened = ghost_workspace_open(bundle);
            ghost_log(log, @"[ghost] workspace launch %@", opened ? @"accepted" : @"refused");
        }
        usleep(20 * 1000);
    }
    if (pid <= 0) {
        ghost_log(log, @"[ghost] pid never appeared");
        return GhostInjectorErrorPidTimeout;
    }
    ghost_log(log, @"[ghost] pid %d", pid);

    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = KERN_FAILURE;
    for (int i = 0; i < 100; i++) {
        kr = task_for_pid(mach_task_self(), pid, &task);
        if (kr == KERN_SUCCESS) break;
        usleep(20 * 1000);
    }
    if (kr != KERN_SUCCESS || task == MACH_PORT_NULL) {
        ghost_log(log, @"[ghost] task_for_pid failed: %d", kr);
        return GhostInjectorErrorTaskPort;
    }

    NSInteger result = ghost_map_payload(task, pid,
                                         [payloadPath UTF8String], log);
    mach_port_deallocate(mach_task_self(), task);
    return result;
}

@end
