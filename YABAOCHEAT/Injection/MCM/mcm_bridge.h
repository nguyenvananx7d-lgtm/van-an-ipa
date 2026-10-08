#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSArray<NSString *> *MCMEnumerateIdentifiersForClass(
    uint64_t cls,
    NSUInteger limit,
    NSString * _Nullable * _Nullable error
);
NSString * _Nullable MCMContainerPathForIdentifier(
    uint64_t cls,
    NSString *identifier,
    BOOL group,
    NSString * _Nullable * _Nullable error
);
NSString * _Nullable MCMActivateContainerPath(
    uint64_t cls,
    NSString *identifier,
    BOOL group,
    NSString * _Nullable * _Nullable error
);
BOOL MCMBridgeAvailable(void);
int64_t MCMActivateContainer(
    uint64_t cls,
    NSString *identifier,
    BOOL group,
    NSString * _Nullable * _Nullable error
);
/// True when the running code signature grants `entitlement` (e.g.
/// `com.apple.private.security.no-sandbox`). Kept in ObjC because the
/// SecTask SPI in the SDK is ObjC-gated and not exposed to Swift.
BOOL MCMHasEntitlement(const char *entitlement);

NS_ASSUME_NONNULL_END