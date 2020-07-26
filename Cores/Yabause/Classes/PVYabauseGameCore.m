/*
 Copyright (c) 2009, OpenEmu Team
 

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "PVYabauseGameCore.h"

@import OpenGLES.ES2;
@import PVSupport;

#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include "vdp1.h"
#include "vdp2.h"
//#include "scsp.h"
#include "peripheral.h"
#include "cdbase.h"
#include "yabause.h"
#include "yui.h"
//#include "m68kc68k.h"
#include "cs0.h"
#include "m68kcore.h"
//#include "permacjoy.h"
#include "vidogl.h"
#include "vidsoft.h"

#define USE_THREADS 0

// ToDo: Fix
#define SAMPLERATE 44100
#define SAMPLEFRAME SAMPLERATE / 60

#define HIRES_WIDTH     356
#define HIRES_HEIGHT    256

u32 *videoBuffer = NULL;

int width;
int height;

yabauseinit_struct yinit;
static PerPad_struct *c1, *c2 = NULL;
BOOL firstRun = YES;

// Global variables because the callbacks need to access them...
static OERingBuffer *ringBuffer;

#pragma mark -
#pragma mark OpenEmu SNDCORE for Yabause

#ifndef SNDOE_H
#define SNDOE_H
#define SNDCORE_OE   11
#endif

#define BUFFER_LEN 65536

static int SNDOEInit(void)
{
    return 0;
}

static void SNDOEDeInit(void)
{
}

static int SNDOEReset(void)
{
    return 0;
}

static int SNDOEChangeVideoFormat(UNUSED int vertfreq)
{
    return 0;
}

static void sdlConvert32uto16s(s32 *srcL, s32 *srcR, s16 *dst, u32 len) {
    u32 i;
    
    for (i = 0; i < len; i++)
    {
        // Left Channel
        if (*srcL > 0x7FFF)
            *dst = 0x7FFF;
        else if (*srcL < -0x8000)
            *dst = -0x8000;
        else
            *dst = *srcL;
        srcL++;
        dst++;
        
        // Right Channel
        if (*srcR > 0x7FFF)
            *dst = 0x7FFF;
        else if (*srcR < -0x8000)
            *dst = -0x8000;
        else
            *dst = *srcR;
        srcR++;
        dst++;
    }
}

static void SNDOEUpdateAudio(u32 *leftchanbuffer, u32 *rightchanbuffer, u32 num_samples)
{
    static unsigned char buffer[BUFFER_LEN];
    sdlConvert32uto16s((s32*)leftchanbuffer, (s32*)rightchanbuffer, (s16*)buffer, num_samples);
    
    [ringBuffer write:buffer maxLength:num_samples << 2];
}

static u32 SNDOEGetAudioSpace(void)
{
    return ([ringBuffer usedBytes] >> 2);
}

void SNDOEMuteAudio()
{
}

void SNDOEUnMuteAudio()
{
}

void SNDOESetVolume(UNUSED int volume)
{
}

SoundInterface_struct SNDOE = {
    SNDCORE_OE,
    "Provenance Sound Interface",
    SNDOEInit,
    SNDOEDeInit,
    SNDOEReset,
    SNDOEChangeVideoFormat,
    SNDOEUpdateAudio,
    SNDOEGetAudioSpace,
    SNDOEMuteAudio,
    SNDOEUnMuteAudio,
    SNDOESetVolume
};

#pragma mark -
#pragma mark Yabause Structs

M68K_struct *M68KCoreList[] = {
    &M68KDummy,
    &M68KC68K,
    NULL
};

SH2Interface_struct *SH2CoreList[] = {
    &SH2Interpreter,
    &SH2DebugInterpreter,
    NULL
};

PerInterface_struct *PERCoreList[] = {
    &PERDummy,
//    &PERMacJoy,
    NULL
};

CDInterface *CDCoreList[] = {
    &DummyCD,
    &ISOCD,
    NULL
};

SoundInterface_struct *SNDCoreList[] = {
    &SNDDummy,
    //&SNDMac,
    &SNDOE,
    NULL
};

VideoInterface_struct *VIDCoreList[] = {
    //&VIDDummy,
#ifdef HAVE_LIBGL
    &VIDOGL,
#endif
    &VIDSoft,
    NULL
};

#pragma mark -
#pragma mark OE Core Implementation

@interface PVYabauseGameCore ()
{
    NSLock  *videoLock;
    
    BOOL    paused;
    NSString *filename;
}

@end

@implementation PVYabauseGameCore

- (id)init
{
    DLOG(@"Yabause init /debug");
    self = [super init];
    if(self != nil)
    {
        filename = [[NSString alloc] init];
        videoLock = [[NSLock alloc] init];
        videoBuffer = (u32 *)calloc(sizeof(u32), HIRES_WIDTH * HIRES_HEIGHT);
        ringBuffer = [self ringBufferAtIndex:0];
    }
    return self;
}

- (void)setupEmulation
{
    width = HIRES_WIDTH;
    height = HIRES_HEIGHT;
    
    PerPortReset();
    c1 = PerPadAdd(&PORTDATA1);
    c2 = PerPadAdd(&PORTDATA2);
}

- (void)resetEmulation
{
    firstRun = YES;
    YabauseResetButton();
}

- (void)stopEmulation
{
    firstRun = YES;
    [super stopEmulation];
}

- (void)dealloc
{
    YabauseDeInit();
    free(videoBuffer);
}

- (void)initYabauseWithCDCore:(int)cdcore
{
	NSString *extension = filename.pathExtension;
	NSArray <NSString*>* romExtensions = @[@"cue", @"ccd", @"mds", @"iso"];
    if ([romExtensions containsObject:extension]) {
		yinit.cdcoretype = CDCORE_ISO;
        yinit.cdpath = [filename UTF8String];
        
        // Get a BIOS
		// sega_101.bin mpr-17933.bin saturn_bios.bin
		NSString *bios = [[self BIOSPath] stringByAppendingPathComponent:@"saturn_bios.bin"];

		ILOG(@"Loading ROM. Will try to setup Saturn BIOS at path: %@", bios);

        // If a "Saturn EU.bin" BIOS exists, use it otherwise emulate BIOS
		if ([[NSFileManager defaultManager] fileExistsAtPath:bios]) {
			ILOG(@"BIOS found : %@", bios);
            yinit.biospath = [bios UTF8String];
		} else {
			WLOG(@"No BIOS found");
			yinit.biospath = NULL;
		}
    } else
    {
        // Assume we've a BIOS file and we want to run it
        yinit.cdcoretype = CDCORE_DUMMY;
        yinit.biospath = [filename UTF8String];
    }
    
    yinit.percoretype = PERCORE_DEFAULT;
    yinit.sh2coretype = SH2CORE_INTERPRETER;
    
#ifdef HAVE_LIBGL
    yinit.vidcoretype = VIDCORE_OGL;
#else
    yinit.vidcoretype = VIDCORE_SOFT;
#endif

	yinit.sndcoretype = SNDCORE_OE;
//	yinit.m68kcoretype = M68KCORE_MUSASHI;
	yinit.m68kcoretype = M68KCORE_C68K;
#if 1
	yinit.carttype = CART_DRAM32MBIT; //4MB RAM Expansion Cart
#else
	yinit.carttype = CART_NONE;
#endif
	yinit.regionid = REGION_AUTODETECT;
	yinit.buppath = NULL;
	yinit.mpegpath = NULL;
	yinit.videoformattype = VIDEOFORMATTYPE_NTSC;
	yinit.frameskip = true;
	yinit.clocksync = 0;
	yinit.basetime = 0;
#if USE_THREADS
    yinit.usethreads      = 1;
    yinit.numthreads      = 2;
#else
    yinit.usethreads = 0;
#endif

	// Take care of the Battery Save file to make Save State happy
	NSString *path = filename;
	NSString *extensionlessFilename = [[path lastPathComponent] stringByDeletingPathExtension];

	NSString *batterySavesDirectory = [self batterySavesPath];

	if([batterySavesDirectory length] != 0)
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
		NSString *filePath = [batterySavesDirectory stringByAppendingPathComponent:[extensionlessFilename stringByAppendingPathExtension:@"sav"]];

		if([filePath length] > 0) {
			DLOG(@"BRAM: %@", filePath);
			char *_bramFile;
			const char *tmp = [filePath UTF8String];

			_bramFile = (char *)malloc(strlen(tmp) + 1);
			strcpy(_bramFile, tmp);
			yinit.buppath = _bramFile;
		}
	}
}

- (void)startYabauseEmulation
{
    YabauseInit(&yinit);
    YabauseSetDecilineMode(1);
    OSDChangeCore(OSDCORE_DUMMY);
}

- (CGSize)bufferSize
{
    return CGSizeMake(HIRES_WIDTH, HIRES_HEIGHT);
}

- (CGSize)aspectSize
{
    return CGSizeMake(width, height);
}

- (CGRect)screenRect
{
    return CGRectMake(0, 0, width, height);
}

- (const void *)videoBuffer
{
    return videoBuffer;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    filename = [path copy];
	DLOG(@"Saturn - %@", filename);
    [self setupEmulation];
//    [self executeFrame];
    return YES;
}

- (BOOL)saveStateToFileAtPath: (NSString *) path error:(NSError**)error {
    int saveError = 0;
    @synchronized(self) {
        ScspMuteAudio(SCSP_MUTE_SYSTEM);
        saveError = YabSaveState([path UTF8String]);
        ScspUnMuteAudio(SCSP_MUTE_SYSTEM);
    }

//    NSDictionary *userInfo = @{
//                               NSLocalizedDescriptionKey: @"Failed to save state.",
//                               NSLocalizedFailureReasonErrorKey: @"Stella does not support save states.",
//                               NSLocalizedRecoverySuggestionErrorKey: @"Check for future updates on ticket #753."
//                               };
//
//    NSError *newError = [NSError errorWithDomain:PVEmulatorCoreErrorDomain
//                                            code:PVEmulatorCoreErrorCodeCouldNotSaveState
//                                        userInfo:userInfo];
//
//    *error = newError;

	return saveError;
}

- (BOOL)loadStateFromFileAtPath:(NSString *)path error:(NSError**)error {
	ScspMuteAudio(SCSP_MUTE_SYSTEM);
	int loadError = YabLoadState([path UTF8String]);
	ScspUnMuteAudio(SCSP_MUTE_SYSTEM);

	return loadError;
}

- (BOOL)supportsSaveStates {
    return YES;
}

#pragma mark -
#pragma mark Inputs

- (oneway void)didPushSaturnButton:(PVSaturnButton)button forPlayer:(NSUInteger)player
{
	PerPad_struct *c = player == 0 ? c1 : c2;
    switch (button)
    {
        case PVSaturnButtonUp:
            PerPadUpPressed(c);
            break;
        case PVSaturnButtonDown:
            PerPadDownPressed(c);
            break;
        case PVSaturnButtonLeft:
            PerPadLeftPressed(c);
            break;
        case PVSaturnButtonRight:
            PerPadRightPressed(c);
            break;
        case PVSaturnButtonStart:
            PerPadStartPressed(c);
            break;
        case PVSaturnButtonL:
            PerPadLTriggerPressed(c);
            break;
        case PVSaturnButtonR:
            PerPadRTriggerPressed(c);
            break;
        case PVSaturnButtonA:
            PerPadAPressed(c);
            break;
        case PVSaturnButtonB:
            PerPadBPressed(c);
            break;
        case PVSaturnButtonC:
            PerPadCPressed(c);
            break;
        case PVSaturnButtonX:
            PerPadXPressed(c);
            break;
        case PVSaturnButtonY:
            PerPadYPressed(c);
            break;
        case PVSaturnButtonZ:
            PerPadZPressed(c);
            break;
        default:
            break;
    }
}

- (oneway void)didReleaseSaturnButton:(PVSaturnButton)button forPlayer:(NSUInteger)player
{
	PerPad_struct *c = player == 0 ? c1 : c2;
    switch (button)
    {
        case PVSaturnButtonUp:
            PerPadUpReleased(c);
            break;
        case PVSaturnButtonDown:
            PerPadDownReleased(c);
            break;
        case PVSaturnButtonLeft:
            PerPadLeftReleased(c);
            break;
        case PVSaturnButtonRight:
            PerPadRightReleased(c);
            break;
        case PVSaturnButtonStart:
            PerPadStartReleased(c);
            break;
        case PVSaturnButtonL:
            PerPadLTriggerReleased(c);
            break;
        case PVSaturnButtonR:
            PerPadRTriggerReleased(c);
            break;
        case PVSaturnButtonA:
            PerPadAReleased(c);
            break;
        case PVSaturnButtonB:
            PerPadBReleased(c);
            break;
        case PVSaturnButtonC:
            PerPadCReleased(c);
            break;
        case PVSaturnButtonX:
            PerPadXReleased(c);
            break;
        case PVSaturnButtonY:
            PerPadYReleased(c);
            break;
        case PVSaturnButtonZ:
            PerPadZReleased(c);
            break;
        default:
            break;
    }
}

#ifdef HAVE_LIBGL
-(BOOL)rendersToOpenGL
{
    return YES;
}
#endif

- (void)executeFrame
{
    if(firstRun) {
        DLOG(@"Yabause executeFrame firstRun, lazy init");
        [self initYabauseWithCDCore:CDCORE_DUMMY];
        [self startYabauseEmulation];
        firstRun = NO;
    }
    else {
        [videoLock lock];
        ScspUnMuteAudio(SCSP_MUTE_SYSTEM);
        YabauseExec();
        ScspMuteAudio(SCSP_MUTE_SYSTEM);
        [videoLock unlock];
    }
}

//- (BOOL)isDoubleBuffered {
//	return YES;
//}

- (GLenum)pixelFormat
{
    return GL_RGBA;
}

- (GLenum)internalPixelFormat
{
    return GL_RGBA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_BYTE;
}

- (double)audioSampleRate
{
    return SAMPLERATE;
}

- (NSUInteger)channelCount
{
    return 2;
}

#pragma mark -
#pragma mark Yabause Callbacks

void YuiErrorMsg(const char *string)
{
    DLOG(@"Yabause Error %@", [NSString stringWithUTF8String:string]);
}

void YuiSwapBuffers(void)
{
    updateCurrentResolution();
    for (int i = 0; i < height; i++) {
        memcpy(videoBuffer + i*HIRES_WIDTH, dispbuffer + i*width, sizeof(u32) * width);
    }
}

#pragma mark -
#pragma mark Helpers

void updateCurrentResolution(void)
{
    int current_width = HIRES_WIDTH;
    int current_height = HIRES_HEIGHT;
    
    // Avoid calling GetGlSize if Dummy/id=0 is selected
    if (VIDCore && VIDCore->id)
    {
        VIDCore->GetGlSize(&current_width,&current_height);
    }
	
    width = current_width;
    height = current_height;
}

@end
