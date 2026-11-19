// Created by JackYu on 07/08/2022.

@import XCTest;
@import LogCore;

@interface LogObservationTests : XCTestCase

@end

@implementation LogObservationTests

- (void)testObservationPreservesRequestedLevelsAndMessageSnapshot
{
    NSMutableArray<LKLogEntry *> *events = [NSMutableArray array];
    LKLogObservation *subscription = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityVerbose handler:^(LKLogEntry *event) {
        [events addObject:event];
    }];
    NSMutableString *message = [NSMutableString stringWithString:@"before"];
    [LKLogCenter.shared logDebugWithModuleName:"" message:message];
    [message appendString:@" after"];
    [LKLogCenter.shared logVerboseWithModuleName:"Network" message:@"verbose"];
    XCTAssertEqual(events.count, 2);
    XCTAssertEqual(events.firstObject.level, LKSeverityDebug);
    XCTAssertEqualObjects(events.firstObject.message, @"before");
    XCTAssertEqualObjects(events.firstObject.category, @"LogKit");
    XCTAssertEqual(events.lastObject.level, LKSeverityVerbose);
    [subscription cancel];
    [subscription cancel];
    [LKLogCenter.shared logErrorWithModuleName:"Network" message:@"ignored"];
    XCTAssertEqual(events.count, 2);
}

- (void)testSubscriberMayCancelAndLogWithoutRecursiveDelivery
{
    __block NSInteger received = 0;
    __block LKLogObservation *subscription;
    subscription = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityWarning handler:^(LKLogEntry *event) {
        received += 1;
        [LKLogCenter.shared logErrorWithModuleName:"Observer" message:@"nested"];
        [subscription cancel];
    }];
    [LKLogCenter.shared logInfoWithModuleName:"Test" message:@"below threshold"];
    [LKLogCenter.shared logWarningWithModuleName:"Test" message:@"accepted"];
    [LKLogCenter.shared logErrorWithModuleName:"Test" message:@"after cancel"];
    XCTAssertEqual(received, 1);
    subscription = nil;
}

- (void)testReleasingTokenCancelsOnlyItsSubscription
{
    __block NSInteger firstCount = 0;
    __block NSInteger secondCount = 0;
    LKLogObservation *second = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityError handler:^(LKLogEntry *event) {
        secondCount += 1;
    }];
    @autoreleasepool {
        LKLogObservation *first = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityDebug handler:^(LKLogEntry *event) {
            firstCount += 1;
        }];
        [LKLogCenter.shared logErrorWithModuleName:"Test" message:@"both"];
        XCTAssertNotNil(first);
    }
    [LKLogCenter.shared logErrorWithModuleName:"Test" message:@"second only"];
    XCTAssertEqual(firstCount, 1);
    XCTAssertEqual(secondCount, 2);
    [second cancel];
}

- (void)testConcurrentCancellationDoesNotDeadlockOrAffectOtherSubscriber
{
    __block NSInteger stableCount = 0;
    NSLock *lock = [[NSLock alloc] init];
    LKLogObservation *stable = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityDebug handler:^(LKLogEntry *event) {
        [lock lock];
        stableCount += 1;
        [lock unlock];
    }];
    dispatch_apply(200, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
        @autoreleasepool {
            LKLogObservation *temporary = [LKLogCenter.shared observeWithMinimumLevel:LKSeverityError handler:^(LKLogEntry *event){
            }];
            [LKLogCenter.shared logDebugWithModuleName:"Concurrent" message:@"test"];
            [temporary cancel];
        }
    });
    [stable cancel];
    XCTAssertEqual(stableCount, 200);
}

@end
