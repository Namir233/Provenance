//
//  PVTimer.h
//  PVSupport
//
//  Created by Rico Wang on 2021/8/17.
//  Copyright © 2021 Provenance Emu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@interface PVTimer : NSObject

typedef void(^PVTimerBlock)(PVTimer *);

+ (void)tickTimers:(NSTimeInterval)time;
+ (instancetype)scheduledTimerWithInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(PVTimerBlock)block;
+ (void)resetTick;
- (instancetype)initWithInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(PVTimerBlock)block;
- (void)resetTick;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
