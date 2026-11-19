//
//  LKLogCenter.h
//  LKLogCenter
//
//  Created by yuxilong on 2022/7/8.
//  Copyright © 2022 BaiTu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "LKLogObservation.h"

NS_ASSUME_NONNULL_BEGIN

#define LK_LOG_ERROR(module, frmt, ...)  \
do { \
NSString *aMessage = [NSString stringWithFormat:@"%@%@", @"", [NSString stringWithFormat:frmt, ##__VA_ARGS__, nil]]; \
[LKLogCenter.shared logErrorWithModuleName:module message:aMessage]; \
} while(0)

#define LK_LOG_WARNING(module, frmt, ...) \
do { \
NSString *aMessage = [NSString stringWithFormat:@"%@%@", @"", [NSString stringWithFormat:frmt, ##__VA_ARGS__, nil]]; \
[LKLogCenter.shared logWarningWithModuleName:module message:aMessage]; \
} while(0)

#define LK_LOG_INFO(module, frmt, ...) \
do { \
NSString *aMessage = [NSString stringWithFormat:@"%@%@", @"", [NSString stringWithFormat:frmt, ##__VA_ARGS__, nil]]; \
[LKLogCenter.shared logInfoWithModuleName:module message:aMessage]; \
} while(0)

#define LK_LOG_DEBUG(module, frmt, ...) \
do { \
NSString *aMessage = [NSString stringWithFormat:@"%@%@", @"", [NSString stringWithFormat:frmt, ##__VA_ARGS__, nil]]; \
[LKLogCenter.shared logDebugWithModuleName:module message:aMessage]; \
} while(0)

/// 日志输出的模块名称
typedef const char * LKLogTag;

/// Implement a destination to forward enabled log entries to file storage or telemetry.
/// Methods run on the logging thread and may be called concurrently.
@protocol LKLogDestination <NSObject>
- (BOOL)acceptsSeverity:(LKSeverity)severity;
- (void)recordSeverity:(LKSeverity)severity tag:(const char *)tag text:(NSString *)text
                  file:(const char *)file function:(const char *)function line:(int)line;
@end

/// 进程共享的日志后端。业务日志可从任意线程调用；生命周期配置由宿主串行管理。
/// Swift 业务优先使用 LogChannel，ObjC 业务可继续使用 LK_LOG_* 宏和原有方法。
@interface LKLogCenter : NSObject

/// 获取共享后端；默认使用系统日志。
/// 创建 LogChannel 值不会访问此单例，首次记录日志时才按需访问。
+ (instancetype)shared;

/// A nil destination uses Apple unified logging at Info and above.
@property(atomic, strong, nullable) id<LKLogDestination> destination;

/// 订阅原始事件。采集等级独立于 Mars 文件等级；调用者必须持有返回的 token。
/// 取消或释放 token 后停止后续回调，已开始的回调允许完成；回调内日志不递归通知订阅者。
/// - Parameters:
///   - level: 最低采集等级，须为 LKSeverity 的有效枚举值。
///   - handler: 在日志调用线程同步执行，可能并发；自行同步状态并将 UI、磁盘工作转交适当队列。
/// - Returns: 需要由调用方持续持有的订阅 token；闭包捕获 token 所有者时避免循环持有。
- (LKLogObservation *)observeWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler NS_SWIFT_NAME(observe(minimumLevel:handler:));

/// 输出 Debug 信息，保留旧入口的等级过滤与来源行为。
/// - Parameters:
///   - moduleName: 调用期间有效的固定 UTF-8 模块名。
///   - message: 已计算的原文，不自动脱敏；不会延迟调用方的字符串构造。
- (void)logDebugWithModuleName:(LKLogTag)moduleName message:(NSString *)message;

/// 输出 Warning 信息，保留旧入口的等级过滤与来源行为。
/// - Parameters:
///   - moduleName: 调用期间有效的固定 UTF-8 模块名。
///   - message: 已计算的原文，不自动脱敏；不会延迟调用方的字符串构造。
- (void)logWarningWithModuleName:(LKLogTag)moduleName message:(NSString *)message;

/// 输出 Info 信息，保留旧入口的等级过滤与来源行为。
/// - Parameters:
///   - moduleName: 调用期间有效的固定 UTF-8 模块名。
///   - message: 已计算的原文，不自动脱敏；不会延迟调用方的字符串构造。
- (void)logInfoWithModuleName:(LKLogTag)moduleName message:(NSString *)message;

/// 输出 Verbose 信息：文件按历史规则映射为 Info，订阅保留 Verbose。
/// - Parameters:
///   - moduleName: 调用期间有效的固定 UTF-8 模块名。
///   - message: 已计算的原文，不自动脱敏；不会延迟调用方的字符串构造。
- (void)logVerboseWithModuleName:(LKLogTag)moduleName message:(NSString *)message;

/// 输出 Error 信息，保留旧入口的等级过滤与来源行为。
/// - Parameters:
///   - moduleName: 调用期间有效的固定 UTF-8 模块名。
///   - message: 已计算的原文，不自动脱敏；不会延迟调用方的字符串构造。
- (void)logErrorWithModuleName:(LKLogTag)moduleName message:(NSString *)message;

/// 判断文件或订阅是否接收此等级，供 Swift 在构造消息前调用；无效等级返回 NO。
/// 可从任意线程调用，结果只是当前阈值快照，不保证后续写入、持久化或回调交付。
/// - Parameters:
///   - level: 原始日志等级；Verbose 按 Info 检查文件阈值，订阅按原始等级检查。
/// - Returns: 文件阈值或至少一个有效订阅接受该等级时为 YES。
- (BOOL)shouldLogWithLevel:(LKSeverity)level NS_SWIFT_NAME(shouldLog(level:));

/// 写入带调用来源的日志，保留 Debug 构建中的来源；文件与订阅仍独立过滤。
/// Swift 桥接入口；业务优先调用 LogChannel 以获得惰性消息和自动来源。
/// 可从任意线程调用；文件异步写入，订阅回调在当前线程同步执行。再次检查当前接收状态，
/// 调用返回不保证持久化或交付；LKLogEntry 当前不包含来源字段，来源只传给文件/系统控制台。
/// - Parameters:
///   - level: 原始日志等级，无效值忽略；Verbose 的文件出口沿用 Info 映射。
///   - moduleName: 固定的业务模块名称。
///   - message: 已计算的日志原文，不作格式串解释，不自动脱敏。
///   - file: 调用处的文件标识。
///   - function: 调用处的函数名。
///   - line: 调用处的行号，超过 INT_MAX 时按 INT_MAX 记录。
- (void)logWithLevel:(LKSeverity)level moduleName:(NSString *)moduleName message:(NSString *)message
                file:(NSString *)file
            function:(NSString *)function
                line:(NSUInteger)line
NS_SWIFT_NAME(log(level:module:message:file:function:line:));

@end

NS_ASSUME_NONNULL_END
