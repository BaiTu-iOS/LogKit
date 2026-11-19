// Created by yuxilong on 2026/09/16.

#import <Foundation/Foundation.h>
#import "LKLogEntry.h"

NS_ASSUME_NONNULL_BEGIN

/// 持有期间接收事件；释放或 cancel 后停止订阅。
/// 回调同步运行于日志调用线程，可能并发，必须快速返回且不执行 UI、磁盘或格式化工作。
/// cancel 不等待在途回调；调用者应使自己的接收会话失效，阻止旧事件发布。
@interface LKLogObservation : NSObject

/// 幂等取消，不影响文件日志或其他订阅者。
- (void)cancel;

/// 请通过 LKLogCenter 的 observe 接口创建订阅。
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
