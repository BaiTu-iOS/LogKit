// Created by yuxilong on 2026/09/16.

#import "LKLogEntry.h"
#include <atomic>

@implementation LKLogEntry

- (instancetype)initWithLevel:(LKSeverity)level category:(NSString *)category message:(NSString *)message
{
    return [self initWithLevel:level category:category message:message timestamp:[NSDate date] mainThread:NSThread.isMainThread];
}

- (instancetype)initWithLevel:(LKSeverity)level category:(NSString *)category message:(NSString *)message timestamp:(NSDate *)timestamp mainThread:(BOOL)mainThread
{
    self = [super init];
    if (self) {
        static std::atomic<uint64_t> nextIdentifier{0};
        _identifier = nextIdentifier.fetch_add(1, std::memory_order_relaxed) + 1;
        _timestamp = [timestamp copy];
        _level = level;
        _category = category.length > 0 ? [category copy] : @"LogKit";
        _message = [message copy];
        _payloadByteCount = (_message.length + _category.length) * sizeof(unichar);
        _mainThread = mainThread;
    }
    return self;
}

@end
