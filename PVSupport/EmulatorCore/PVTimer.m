//
//  PVTimer.m
//  PVSupport
//
//  Created by Rico Wang on 2021/8/17.
//  Copyright © 2021 Provenance Emu. All rights reserved.
//

#import "PVTimer.h"

@interface _PVWeakTimer : NSObject

@property (nonatomic, weak) PVTimer *p;

@end

@implementation _PVWeakTimer

- (instancetype)initWithTimer:(PVTimer *)timer
{
    self = [super init];
    if (self) {
        _p = timer;
    }
    return self;
}

@end

@interface PVTimer()

@property (nonatomic, assign) NSTimeInterval time;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) BOOL repeat;
@property (nonatomic, copy) PVTimerBlock block;

@end

@implementation PVTimer

static NSMutableArray<_PVWeakTimer *> *GlobalTimers;

static void compactGlobalTimers() {
    for (NSInteger i = GlobalTimers.count - 1; i >= 0; i--) {
        _PVWeakTimer *wt = GlobalTimers[i];
        if (!wt.p) {
            [GlobalTimers removeObject:wt];
        }
    }
}

+ (void)tickTimers:(NSTimeInterval)time {
    for (_PVWeakTimer *timer in GlobalTimers) {
        [timer.p tick:time];
    }
}

+ (void)resetTick {
    for (_PVWeakTimer *timer in GlobalTimers) {
        [timer.p resetTick];
    }
}

+ (PVTimer *)scheduledTimerWithInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(PVTimerBlock)block {
    PVTimer *timer = [[self alloc] initWithInterval:interval repeats:repeats block:block];
    if (!GlobalTimers) {
        GlobalTimers = [NSMutableArray array];
    }
    [GlobalTimers addObject:[[_PVWeakTimer alloc] initWithTimer:timer]];
    return timer;
}

- (void)dealloc {
    [self invalidate];
}

- (instancetype)initWithInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(PVTimerBlock)block {
    self = [super init];
    if (self) {
        _interval = interval;
        _repeat = repeats;
        _block = block;
        _time = 0;
    }
    return self;
}

- (void)tick:(NSTimeInterval)time {
    _time += time;
    if (_time > _interval) {
        _time -= _interval;
        if (_block) {
            _block(self);
        }
        if (!_repeat) {
            [self invalidate];
        }
    }
}

- (void)resetTick {
    _time = 0;
}

- (void)invalidate {
    _time = 0;
    for (NSInteger i = GlobalTimers.count - 1; i >= 0; i--) {
        _PVWeakTimer *wt = GlobalTimers[i];
        if (wt.p == self) {
            [GlobalTimers removeObject:wt];
            return;
        }
    }
}

@end
