// Created by yuxilong on 2026/09/16.

#import "LKLogObservation.h"

NS_ASSUME_NONNULL_BEGIN

/// 仅供统一日志入口使用，不作为 SDK 公共接口发布。
@interface LKLogObservation (Internal)

/// 注册一个弱持有的订阅。
/// @param level 最低采集等级。
/// @param handler 日志线程上的轻量接收入口。
+ (instancetype)subscribeWithMinimumLevel:(LKSeverity)level handler:(void (^)(LKLogEntry *event))handler;

/// 检查订阅出口是否需要此等级。
/// @param level 原始请求等级。
+ (BOOL)acceptsLevel:(LKSeverity)level;

/// 复制原文后向当前订阅快照投递一次。
/// @param level 原始请求等级。
/// @param moduleName 调用期间有效的模块名称。
/// @param message 完整原文。
+ (void)publishLevel:(LKSeverity)level moduleName:(nullable const char *)moduleName message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
