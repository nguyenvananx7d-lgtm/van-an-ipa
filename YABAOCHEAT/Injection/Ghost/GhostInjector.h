//
//  GhostInjector.h — launch-and-map, the app side of the Ghost route.
//
//  The injector does three things and nothing else:
//
//    1. asks SpringBoard to open the game by bundle id;
//    2. waits for the pid, takes its task port and suspends the whole task;
//    3. points one idle non-main thread at `dlopen` with the payload path,
//       waits for the call to return, restores the thread and detaches.
//
//  It never opens the game's container, never writes a file, and never needs a
//  kernel exploit: the app already carries `platform-application` and
//  `get-task-allow`.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GhostInjectorError) {
    GhostInjectorErrorPayloadMissing = -1,
    GhostInjectorErrorLaunchFailed = -2,
    GhostInjectorErrorPidTimeout = -3,
    GhostInjectorErrorTaskPort = -4,
    GhostInjectorErrorThreads = -5,
    GhostInjectorErrorRemoteMemory = -6,
    GhostInjectorErrorThreadState = -7,
    GhostInjectorErrorDlopenFailed = -8,
    GhostInjectorErrorTimeout = -9,
};

@interface GhostInjector : NSObject

/// YES when `GhostPayload.dylib` is inside the app bundle.
+ (BOOL)payloadAvailable;

/// Path of the bundled payload, or nil.
+ (nullable NSString *)payloadPath;

/// Launch `bundleID` and map `payloadPath` into it. Blocking; call from a
/// background queue. `log` is invoked on the calling thread for every stage.
/// Returns 0 on success, a `GhostInjectorError` otherwise.
+ (NSInteger)launchBundle:(NSString *)bundleID
                  payload:(NSString *)payloadPath
                      log:(void (^_Nullable)(NSString *line))log;

/// SIGKILL a running instance, so the next launch is a cold start with no old
/// runtime still mapped. Safe when the game is not running.
+ (void)terminateBundle:(NSString *)bundleID;

/// True when `task_for_pid` answers for the app itself — proof the installed
/// app kept its `get-task-allow` entitlement, which is what lets the route
/// take the game's task port. Used by the route picker to decide between
/// `.ghost` and `.hotfix`.
+ (BOOL)taskPortAllowed;

@end

NS_ASSUME_NONNULL_END
