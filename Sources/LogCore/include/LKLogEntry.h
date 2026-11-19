// Created by yuxilong on 2026/09/16.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 原始请求等级，不受 Mars 文件等级映射影响。
typedef NS_ENUM(NSInteger, LKSeverity) {
    LKSeverityVerbose = 0,
    LKSeverityDebug,
    LKSeverityInfo,
    LKSeverityWarning,
    LKSeverityError,
    LKSeverityFatal
};

/// 在调用线程创建的不可变事件；跨线程到达顺序不由 identifier 保证。
@interface LKLogEntry : NSObject

/// 进程内唯一标识，不代表订阅回调的到达顺序。
@property(nonatomic, assign, readonly) uint64_t identifier;

/// 事件生成时的墙上时钟时间。
@property(nonatomic, copy, readonly) NSDate *timestamp;

/// 业务请求的原始等级。
@property(nonatomic, assign, readonly) LKSeverity level;

/// 模块名称，空值归一为 LKLogCenter。
@property(nonatomic, copy, readonly) NSString *category;

/// 完整原文的不可变副本。
@property(nonatomic, copy, readonly) NSString *message;

/// 正文和模块名的 UTF-16 字节数，用于接收入口的常数时间预算判断。
@property(nonatomic, assign, readonly) NSUInteger payloadByteCount;

/// 产生日志时是否处于主线程。
@property(nonatomic, assign, readonly, getter=isMainThread) BOOL mainThread;

/// 创建快照，也可用于自定义日志源和测试。
/// @param level 原始请求等级。
/// @param category 模块名称，空值回退 LKLogCenter。
/// @param message 需要复制保存的完整原文。
- (instancetype)initWithLevel:(LKSeverity)level category:(NSString *)category message:(NSString *)message;

/// 从本地历史恢复事件；保留原时间和线程信息，identifier 重新分配为进程内唯一值。
/// @param level 原始请求等级。
/// @param category 原始模块名称。
/// @param message 未截断的日志原文。
/// @param timestamp 日志原始生成时间。
/// @param mainThread 日志原始调用线程是否为主线程。
- (instancetype)initWithLevel:(LKSeverity)level category:(NSString *)category message:(NSString *)message timestamp:(NSDate *)timestamp mainThread:(BOOL)mainThread NS_DESIGNATED_INITIALIZER;

/// 必须通过指定初始化方法提供日志内容。
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
