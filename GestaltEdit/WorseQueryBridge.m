//
//  WorseQueryBridge.m
//  GestaltEdit
//
//  worse_query integration for iOS 27.3.
//

#import "WorseQueryBridge.h"

#import <dlfcn.h>
#import <stdlib.h>
#import <xpc/xpc.h>
#import <sys/stat.h>

static NSString * const kWorseQueryGroup = @"group.com.romashka.worsequery";

typedef void *(*WQCreate)(void);
typedef void (*WQSetU64)(void *, uint64_t);
typedef void (*WQSetXPC)(void *, xpc_object_t);
typedef void *(*WQGetSingleResult)(void *);
typedef void (*WQFree)(void *);
typedef char *(*WQCopyToken)(void *);
typedef int64_t (*WQConsume)(const char *);
typedef int (*WQRelease)(int64_t);

static void WQCleanSymlink(NSString *group)
{
    if (group == NULL) return;
    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *groupRoot = [files containerURLForSecurityApplicationGroupIdentifier:group];
    if (groupRoot) {
        NSURL *caches = [groupRoot URLByAppendingPathComponent:@"Library/Caches"];
        [files removeItemAtURL:caches error:nil];
        [files createDirectoryAtURL:caches withIntermediateDirectories:false attributes:nil error:nil];
    }
}

static int64_t WQRun(NSString *target, NSString *group, bool createDir)
{
    if (!createDir) {
        struct stat st;
        if (lstat(target.fileSystemRepresentation, &st) != 0) return -255;
    }

    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *groupRoot = [files containerURLForSecurityApplicationGroupIdentifier:group];
    if (!groupRoot) return -1;
    NSString *caches = [[groupRoot URLByAppendingPathComponent:@"Library/Caches"] path];

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return -2;

    WQCreate create = (WQCreate)dlsym(mgr, "container_query_create");
    WQSetU64 setClass = (WQSetU64)dlsym(mgr, "container_query_set_class");
    WQSetXPC setGroups = (WQSetXPC)dlsym(mgr, "container_query_set_group_identifiers");
    WQSetU64 setFlags = (WQSetU64)dlsym(mgr, "container_query_operation_set_flags");
    WQSetU64 setPart = (WQSetU64)dlsym(mgr, "container_query_operation_set_part");
    WQGetSingleResult getOne = (WQGetSingleResult)dlsym(mgr, "container_query_get_single_result");
    WQFree freeQuery = (WQFree)dlsym(mgr, "container_query_free");
    WQCopyToken copyToken = (WQCopyToken)dlsym(mgr, "container_copy_sandbox_token");
    WQConsume consume = (WQConsume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");

    if (!create || !setClass || !setGroups || !setFlags || !setPart || !getOne || !freeQuery || !copyToken || !consume) {
        dlclose(mgr);
        return -2;
    }

    void *query = create();
    if (!query) { dlclose(mgr); return -3; }

    setClass(query, 7);
    xpc_object_t identifier = xpc_string_create(group.UTF8String);
    setGroups(query, identifier);
    setPart(query, 3);
    setFlags(query, 0x0000008000000000ULL);

    [files removeItemAtPath:caches error:nil];
    if (![files createSymbolicLinkAtPath:caches withDestinationPath:target error:nil]) {
        freeQuery(query);
        dlclose(mgr);
        return -4;
    }

    void *result = getOne(query);
    if (!result) {
        freeQuery(query);
        dlclose(mgr);
        WQCleanSymlink(group);
        return -5;
    }

    char *token = copyToken(result);
    if (!token) {
        freeQuery(query);
        dlclose(mgr);
        WQCleanSymlink(group);
        return -6;
    }

    int64_t handle = consume(token);
    free(token);
    freeQuery(query);
    dlclose(mgr);
    WQCleanSymlink(group);
    return handle;
}

BOOL WorseQueryBridgeAvailable(void)
{
    return [[NSFileManager defaultManager]
        containerURLForSecurityApplicationGroupIdentifier:kWorseQueryGroup] != nil;
}

@interface WorseQueryLease ()
@property(nonatomic, copy, readwrite) NSString *targetPath;
@property(nonatomic, readwrite, getter=isActive) BOOL active;
@end

@implementation WorseQueryLease
{
    int64_t _sandboxHandle;
}

+ (instancetype)leaseForPath:(NSString *)path error:(NSString **)error
{
    if (!path.isAbsolutePath) {
        if (error) *error = @"worse_query requires an absolute target path";
        return nil;
    }

    NSString *directory = [path stringByDeletingLastPathComponent];
    int64_t handle = WQRun(directory, kWorseQueryGroup, true);
    if (handle <= 0) {
        if (error) *error = [NSString stringWithFormat:@"worse_query failed with code %lld", handle];
        return nil;
    }

    WorseQueryLease *lease = [WorseQueryLease new];
    lease->_sandboxHandle = handle;
    lease.targetPath = path;
    lease.active = YES;
    if (error) *error = nil;
    return lease;
}

- (void)invalidate
{
    if (!self.active) return;
    WQRelease release = (WQRelease)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (release) release(_sandboxHandle);
    _sandboxHandle = -1;
    self.active = NO;
}

- (void)dealloc
{
    [self invalidate];
}

@end
