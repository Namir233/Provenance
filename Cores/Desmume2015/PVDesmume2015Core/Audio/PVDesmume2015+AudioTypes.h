//
//  PVDesmume2015+Audio.h
//  PVDesmume2015
//
//  Created by Joseph Mattiello on 11/1/18.
//  Copyright © 2018 Provenance. All rights reserved.
//

#import <PVDesmume2015/PVDesmume2015.h>

#import <Foundation/Foundation.h>
#import <PVSupport/PVSupport.h>
#import <PVSupport/CARingBuffer.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>

    // Desmume2015 imports
#include "types.h"
#include "profiler/profiler.h"
#include "cfg/cfg.h"
#include "rend/rend.h"
#include "rend/TexCache.h"
#include "hw/maple/maple_devs.h"
#include "hw/maple/maple_if.h"
#include "hw/maple/maple_cfg.h"

static volatile Float64 write_ptr = 0;
static volatile Float64 read_ptr = 0;
static volatile Float64 samples_ptr = 0;
