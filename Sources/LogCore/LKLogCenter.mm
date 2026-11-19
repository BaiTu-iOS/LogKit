// Created by yuxilong.
#import "LKLogCenter.h"
#import "LKLogObservation+Internal.h"
#import <os/log.h>
#include <limits.h>

@implementation LKLogCenter

+ (instancetype)shared {
    static LKLogCenter *center;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ center = [[self alloc] init]; });
    return center;
}

- (LKLogObservation *)observeWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler
{
    return [LKLogObservation subscribeWithMinimumLevel:level handler:handler];
}

- (void)logDebugWithModuleName:(LKLogTag)tag message:(NSString *)text {
    [self writeLegacy:LKSeverityDebug tag:tag text:text line:__LINE__ function:__FUNCTION__];
}

- (void)logWarningWithModuleName:(LKLogTag)tag message:(NSString *)text {
    [self writeLegacy:LKSeverityWarning tag:tag text:text line:__LINE__ function:__FUNCTION__];
}

- (void)logInfoWithModuleName:(LKLogTag)tag message:(NSString *)text {
    [self writeLegacy:LKSeverityInfo tag:tag text:text line:__LINE__ function:__FUNCTION__];
}

- (void)logVerboseWithModuleName:(LKLogTag)tag message:(NSString *)text {
    [self writeLegacy:LKSeverityVerbose tag:tag text:text line:__LINE__ function:__FUNCTION__];
}

- (void)logErrorWithModuleName:(LKLogTag)tag message:(NSString *)text {
    [self writeLegacy:LKSeverityError tag:tag text:text line:__LINE__ function:__FUNCTION__];
}

- (void)writeLegacy:(LKSeverity)severity tag:(LKLogTag)tag text:(NSString *)text line:(int)line function:(const char *)function {
#ifdef DEBUG
    [self dispatchSeverity:severity tag:tag text:text file:"" function:"" line:line];
#else
    [self dispatchSeverity:severity tag:tag text:text file:__FILE_NAME__ function:function line:line];
#endif
}

- (BOOL)shouldLogWithLevel:(LKSeverity)severity {
    if (severity < LKSeverityVerbose || severity > LKSeverityFatal) return NO;
    id<LKLogDestination> destination = self.destination;
    return (destination ? [destination acceptsSeverity:severity] : severity >= LKSeverityInfo)
        || [LKLogObservation acceptsLevel:severity];
}

- (void)dispatchSeverity:(LKSeverity)severity tag:(LKLogTag)tag text:(NSString *)text
                    file:(const char *)file function:(const char *)function line:(int)line {
    if (severity < LKSeverityVerbose || severity > LKSeverityFatal) return;
    id<LKLogDestination> destination = self.destination;
    if (destination) {
        if ([destination acceptsSeverity:severity]) {
            [destination recordSeverity:severity tag:tag text:text file:file function:function line:line];
        }
    } else if (severity >= LKSeverityInfo) {
        os_log_type_t type = severity >= LKSeverityError ? OS_LOG_TYPE_ERROR : OS_LOG_TYPE_DEFAULT;
        os_log_with_type(OS_LOG_DEFAULT, type, "[%{public}s] %{public}@", tag, text);
    }
    [LKLogObservation publishLevel:severity moduleName:tag message:text];
}

- (void)logWithLevel:(LKSeverity)severity moduleName:(NSString *)tag message:(NSString *)text
                file:(NSString *)file function:(NSString *)function line:(NSUInteger)line {
    [self dispatchSeverity:severity tag:tag.UTF8String text:text file:file.UTF8String function:function.UTF8String
                      line:(int)MIN(line, (NSUInteger)INT_MAX)];
}

@end
