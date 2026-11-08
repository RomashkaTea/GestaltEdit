//
//  WorseQueryBridge.h
//  GestaltEdit
//
//  Symlink-based ContainerManager integration derived from forcequitOS/worse_query.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WorseQueryLease : NSObject

@property(nonatomic, copy, readonly) NSString *targetPath;
@property(nonatomic, readonly, getter=isActive) BOOL active;

+ (nullable instancetype)leaseForPath:(NSString *)path
                                error:(NSString * _Nullable * _Nullable)error;
- (void)invalidate;

@end

FOUNDATION_EXPORT BOOL WorseQueryBridgeAvailable(void);

NS_ASSUME_NONNULL_END
