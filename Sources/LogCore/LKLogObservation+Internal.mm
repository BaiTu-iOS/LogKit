// Created by yuxilong on 2026/09/16.

#import "LKLogObservation+Internal.h"
#include <atomic>

static NSLock *g_subscriptionLock;
static NSHashTable<LKLogObservation *> *g_subscriptions;
static std::atomic<unsigned int> g_interestedLevels{0};
static thread_local BOOL g_delivering = NO;

@interface LKLogObservation ()
{
    std::atomic<bool> _cancelled;
    LKSeverity _minimumLevel;
    void (^_handler)(LKLogEntry *event);
}

- (instancetype)initWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler;

@end

@implementation LKLogObservation

- (instancetype)initWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler
{
    self = [super init];
    if (self) {
        _minimumLevel = level;
        _handler = [handler copy];
        _cancelled.store(false);
    }
    return self;
}

- (void)cancel
{
    [g_subscriptionLock lock];
    // 在目录锁内完成幂等取消；回调内取消不等待自己完成。
    if (_cancelled.load()) {
        [g_subscriptionLock unlock];
        return;
    }
    _cancelled.store(true);
    [g_subscriptions removeObject:self];
    unsigned int levels = 0;
    __attribute__((objc_precise_lifetime)) NSArray<LKLogObservation *> *subscriptions = g_subscriptions.allObjects;
    for (LKLogObservation *subscription in subscriptions) {
        // 在途取消的订阅不再贡献采集等级。
        if (!subscription->_cancelled.load()) levels |= (0x3FU << subscription->_minimumLevel) & 0x3FU;
    }
    g_interestedLevels.store(levels, std::memory_order_release);
    [g_subscriptionLock unlock];
}

- (void)dealloc
{
    [self cancel];
}

@end

@implementation LKLogObservation (Internal)

+ (instancetype)subscribeWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_subscriptionLock = [[NSLock alloc] init];
        g_subscriptions = [NSHashTable weakObjectsHashTable];
    });
    // 无效等级回退到 Error，避免移位越界；公开调用仍通过断言暴露契约错误。
    NSParameterAssert(level >= LKSeverityVerbose && level <= LKSeverityFatal);
    level = level >= LKSeverityVerbose && level <= LKSeverityFatal ? level : LKSeverityError;
    LKLogObservation *subscription = [[self alloc] initWithMinimumLevel:level handler:handler];
    [g_subscriptionLock lock];
    [g_subscriptions addObject:subscription];
    g_interestedLevels.fetch_or((0x3FU << level) & 0x3FU, std::memory_order_release);
    [g_subscriptionLock unlock];
    return subscription;
}

+ (BOOL)acceptsLevel:(LKSeverity)level
{
    // 无订阅和回调内重入均不构造事件；文件出口仍独立处理。
    if (g_delivering || level < LKSeverityVerbose || level > LKSeverityFatal) return NO;
    return (g_interestedLevels.load(std::memory_order_acquire) & (1U << level)) != 0;
}

+ (void)publishLevel:(LKSeverity)level moduleName:(const char *)moduleName message:(NSString *)message
{
    // 先检查原始等级，防止仅文件需要时支付事件构造开销。
    if (![self acceptsLevel:level]) return;
    [g_subscriptionLock lock];
    NSArray<LKLogObservation *> *subscriptions = g_subscriptions.allObjects;
    [g_subscriptionLock unlock];
    NSString *category = moduleName ? [NSString stringWithUTF8String:moduleName] : nil;
    LKLogEntry *event = [[LKLogEntry alloc] initWithLevel:level category:category ?: @"LogKit" message:message];
    g_delivering = YES;
    @try {
        for (LKLogObservation *subscription in subscriptions) {
            // 快照取得后可能取消；已开始的回调允许完成。
            if (subscription->_cancelled.load() || level < subscription->_minimumLevel) continue;
            subscription->_handler(event);
        }
    } @finally {
        g_delivering = NO;
    }
}

@end
