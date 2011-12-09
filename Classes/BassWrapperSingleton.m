//
//  BassWrapperSingleton.m
//  iSub
//
//  Created by Ben Baron on 11/16/11.
//  Copyright (c) 2011 Ben Baron. All rights reserved.
//

#import "BassWrapperSingleton.h"
#import "Song.h"
#import "SUSCurrentPlaylistDAO.h"
#import "NSString+cStringUTF8.h"
#import "BassParamEqValue.h"
#import "BassEffectHandle.h"
#import "NSNotificationCenter+MainThread.h"
#include <AudioToolbox/AudioToolbox.h>
#include "MusicSingleton.h"
#import "BassEffectDAO.h"

@interface BassWrapperSingleton (Private)
- (void)bassInit;
@end

@implementation BassWrapperSingleton
@synthesize isEqualizerOn, startByteOffset, isTempDownload, currPlaylistDAO;

static BOOL isFilestream1 = YES;

extern void BASSFLACplugin;

static BassWrapperSingleton *selfRef;
static SUSCurrentPlaylistDAO *currPlaylistDAORef;

static HSTREAM fileStream1, fileStream2, outStream;

static NSThread *playbackThread = nil;

static float fftData[1024];

short *lineSpecBuf;
int lineSpecBufSize;

int currentSongRetryAttempt = 0;
int nextSongRetryAttempt = 0;
#define MAX_RETRY_ATTEMPTS 30
#define RETRY_DELAY 1.0

static NSMutableArray *eqValueArray, *eqHandleArray;

- (void)readEqData
{
	// Get the FFT data for visualizer
	BASS_ChannelGetData(outStream, fftData, BASS_DATA_FFT2048);
	
	// Get the data for line spec visualizer
	BASS_ChannelGetData(outStream, lineSpecBuf, lineSpecBufSize);
}

// Stream callback
DWORD CALLBACK MyStreamProc(HSTREAM handle, void *buffer, DWORD length, void *user)
{
	if (!playbackThread)
		playbackThread = [NSThread currentThread];
	
	DWORD r;
	
	if (isFilestream1 && BASS_ChannelIsActive(fileStream1)) 
	{
		// Read data from stream1
		r = BASS_ChannelGetData(fileStream1, buffer, length);
		
		// Check if stream1 is now complete
		if (!BASS_ChannelIsActive(fileStream1))
		{	
			DLog(@"stream1 complete");
			
			// Stream1 is done, free the stream
			BASS_StreamFree(fileStream1);
			
			// Increment current playlist index
			[currPlaylistDAORef performSelectorOnMainThread:@selector(incrementIndex) withObject:nil waitUntilDone:YES];
			
			// Send song end notification
			[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackEnded];
			
			// Check to see if there is another song to play
			if (BASS_ChannelIsActive(fileStream2))
			{
				DLog(@"stream2 exists, starting playback");
				
				// Send song start notification
				[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackStarted];
				
				// Read data from stream2
				[selfRef setStartByteOffset:0];
				[selfRef setIsTempDownload:NO];
				isFilestream1 = NO;
				r = BASS_ChannelGetData(fileStream2, buffer, length);
				DLog(@"error code: %i", BASS_ErrorGetCode());
				
				// Prepare the next song for playback
				[selfRef prepareNextSongStreamInBackground];
			}
		}
	}
	else if (BASS_ChannelIsActive(fileStream2)) 
	{
		// Read data from stream2
		r = BASS_ChannelGetData(fileStream2, buffer, length);
		
		// Check if stream2 is now complete
		if (!BASS_ChannelIsActive(fileStream2))
		{
			DLog(@"stream2 complete");
			
			// Stream2 is done, free the stream
			BASS_StreamFree(fileStream2);
			
			// Increment current playlist index
			[currPlaylistDAORef performSelectorOnMainThread:@selector(incrementIndex) withObject:nil waitUntilDone:YES];
			
			// Send song done notification
			[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackEnded];
			
			if (BASS_ChannelIsActive(fileStream1))
			{
				DLog(@"stream1 exists, starting playback");
				
				// Send song start notification
				[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackStarted];
				
				[selfRef setStartByteOffset:0];
				[selfRef setIsTempDownload:NO];
				isFilestream1 = YES;
				r = BASS_ChannelGetData(fileStream1, buffer, length);
				DLog(@"error code: %i", BASS_ErrorGetCode());
				
				[selfRef prepareNextSongStreamInBackground];
			}
		}
	}
	else
	{
		DLog(@"no more data, ending");
		r = BASS_STREAMPROC_END;
		[selfRef performSelectorOnMainThread:@selector(bassFree) withObject:nil waitUntilDone:NO];
	}
	
	return r;
}

- (void)prepareNextSongStreamInBackground
{
	@autoreleasepool 
	{
		[self performSelectorInBackground:@selector(prepareNextSongStream) withObject:nil];
	}
}

- (void)prepareNextSongStream
{
	@autoreleasepool 
	{
		Song *nextSong = currPlaylistDAO.nextSong;
		if (nextSong.fileExists)
		{
			if (BASS_Init(0, 44100, 0, NULL, NULL))
			{
				NSUInteger silence = [self preSilenceLengthForSong:nextSong];
				[self performSelector:@selector(prepareNextSongStreamInternal:) onThread:playbackThread withObject:[NSNumber numberWithInt:silence] waitUntilDone:NO];
				BASS_Free();
			}
			else
			{
				DLog(@"bass init failed in background thread");
			}
		}
	}
}

// playback thread
- (void)prepareNextSongStreamInternal:(NSNumber *)silence
{
	@autoreleasepool 
	{
		Song *nextSong = currPlaylistDAO.nextSong;
		HSTREAM stream = BASS_StreamCreateFile(FALSE, [nextSong.localPath cStringUTF8], [silence intValue], 0, 
											   BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
		
		if (!stream)
		{
			stream = BASS_StreamCreateFile(FALSE, [nextSong.localPath cStringUTF8], 0, 0, 
										   BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
		}
		
		if (!stream)
		{
			DLog(@"nextSong stream: %llu error: %i", (unsigned long long)stream, BASS_ErrorGetCode());
		}
		
		if (isFilestream1)
		{
			fileStream2 = stream;
		}
		else
		{
			fileStream1 = stream;
		}
		
		DLog(@"nextSong: %llu", (unsigned long long)stream);
	}
}

- (NSUInteger)preSilenceLengthForSong:(Song *)aSong
{
	// Create a decode channel
	const char *file = [aSong.localPath cStringUTF8];
	HSTREAM chan = BASS_StreamCreateFile(FALSE, file, 0, 0, BASS_STREAM_DECODE); // create decoding channel
	if (!chan)
	{
		DLog(@"getsilencelength error: %i", BASS_ErrorGetCode());
	}
	
	// Determine the silence length
	BYTE buf[10000];
	DWORD count=0;
	while (BASS_ChannelIsActive(chan)) 
	{
		int a,b = BASS_ChannelGetData(chan, buf, 10000); // decode some data
		for (a = 0; a < b && !buf[a]; a++) ; // count silent bytes
		count += a; // add number of silent bytes
		if (a < b) break; // sound has begun!
	}
	
	// Free the channel
	BASS_StreamFree(chan);
	
	DLog(@"silence: %i", count);
	return count;
}

- (void)startWithOffsetInBytes:(NSNumber *)byteOffset
{	
	if (currPlaylistDAO.currentIndex >= currPlaylistDAO.count)
		currPlaylistDAO.currentIndex = currPlaylistDAO.count - 1;
	
	Song *currentSong = currPlaylistDAO.currentSong;
	
	if (!currentSong)
		return;
    
    startByteOffset = [byteOffset intValue];
    isTempDownload = NO;
	
	[self bassInit];
	
	if (currentSong.fileExists)
	{
		//fileStream1 = BASS_StreamCreateFile(false, [currentSong.localPath cStringUTF8], startByteOffset, 0, BASS_SAMPLE_FLOAT);
		//BASS_ChannelPlay(fileStream1, FALSE);
		
		BASS_CHANNELINFO info;
		fileStream1 = BASS_StreamCreateFile(false, [currentSong.localPath cStringUTF8], startByteOffset, 0, 
											BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
		if (fileStream1)
		{
			DLog(@"currentSong: %llu", (long long int)fileStream1);
			BASS_ChannelGetInfo(fileStream1, &info);
			
			isFilestream1 = YES;
			
			outStream = BASS_StreamCreate(info.freq, info.chans, 
										  BASS_SAMPLE_FLOAT, &MyStreamProc, 0); // create the output stream
			
			if (isEqualizerOn)
			{
				[self applyEqualizer:eqValueArray];
			}
			
			BASS_ChannelPlay(outStream, FALSE);
			
			[self performSelectorInBackground:@selector(prepareNextSongStream) withObject:nil];
			
			[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackStarted];
		}
		/*else 
		{
			if (currentSongRetryAttempt < MAX_RETRY_ATTEMPTS)
			{
				DLog(@"currentSong error: %i... retry attempt: %i retrying in %f seconds", BASS_ErrorGetCode(), currentSongRetryAttempt, RETRY_DELAY);
				currentSongRetryAttempt++;
				[self performSelector:@selector(startWithOffsetInBytes:) withObject:byteOffset afterDelay:RETRY_DELAY];
			}
			else
			{
				currentSongRetryAttempt = 0;
			}
		}*/
	}
}

- (void)start
{
	[self startWithOffsetInBytes:[NSNumber numberWithInt:0]];
}

- (void)stop
{
    if (self.isPlaying) 
	{
		BASS_Pause();
        [NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackEnded];
	}
    
    [self bassFree];
}

- (void)playPause
{
	if (self.isPlaying) 
	{
		DLog(@"Pausing");
		BASS_Pause();
        [NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackPaused];
	} 
	else 
	{
		if (outStream == 0)
		{
			DLog(@"starting new stream");
			if (currPlaylistDAO.currentIndex >= currPlaylistDAO.count)
				currPlaylistDAO.currentIndex = currPlaylistDAO.count - 1;
			[[MusicSingleton sharedInstance] playSongAtPosition:currPlaylistDAO.currentIndex];
		}
		else
		{
			DLog(@"Playing");
			BASS_Start();
			[NSNotificationCenter postNotificationToMainThreadWithName:ISMSNotification_SongPlaybackStarted];
		}
	}
}

void audioRouteChangeListenerCallback (void *inUserData, AudioSessionPropertyID inPropertyID, UInt32 inPropertyValueSize, const void *inPropertyValue) 
{
    DLog(@"audioRouteChangeListenerCallback called");
	
    // ensure that this callback was invoked for a route change
    if (inPropertyID != kAudioSessionProperty_AudioRouteChange) 
		return;
	
	if ([selfRef isPlaying])
	{
		// Determines the reason for the route change, to ensure that it is not
		// because of a category change.
		CFDictionaryRef routeChangeDictionary = inPropertyValue;
		CFNumberRef routeChangeReasonRef = CFDictionaryGetValue (routeChangeDictionary, CFSTR (kAudioSession_AudioRouteChangeKey_Reason));
		SInt32 routeChangeReason;
		CFNumberGetValue (routeChangeReasonRef, kCFNumberSInt32Type, &routeChangeReason);
		
        // "Old device unavailable" indicates that a headset was unplugged, or that the
        // device was removed from a dock connector that supports audio output. This is
        // the recommended test for when to pause audio.
        if (routeChangeReason == kAudioSessionRouteChangeReason_OldDeviceUnavailable) 
		{
            [selfRef playPause];
			
            NSLog (@"Output device removed, so application audio was paused.");
        }
		else 
		{
            NSLog (@"A route change occurred that does not require pausing of application audio.");
        }
    }
	else 
	{	
        NSLog (@"Audio route change while application audio is stopped.");
        return;
    }
}

void audioInterruptionListenerCallback (void *inUserData, AudioSessionPropertyID inPropertyID, UInt32 inPropertyValueSize, const void *inPropertyValue) 
{
	DLog(@"audio interrupted");
}

- (void)bassInit
{
    isTempDownload = NO;
    
	[self bassFree];
		
	BASS_SetConfig(BASS_CONFIG_IOS_MIXAUDIO, 0); // Disable mixing.	To be called before BASS_Init.
	BASS_SetConfig(BASS_CONFIG_BUFFER, 1500);
	BASS_SetConfig(BASS_CONFIG_FLOATDSP, true);
	
	// Initialize default device.
	if (!BASS_Init(-1, 96000, 0, NULL, NULL)) 
	{
		DLog(@"Can't initialize device");
	}
		
	BASS_PluginLoad(&BASSFLACplugin, 0);
	
	AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, audioRouteChangeListenerCallback, self);
	AudioSessionAddPropertyListener(kAudioSessionProperty_OtherAudioIsPlaying, audioInterruptionListenerCallback, self);
}

- (BOOL)bassFree
{
	playbackThread = nil;
    isTempDownload = NO;
	BOOL success = BASS_Free();
	outStream = 0;
	return success;
}

- (BOOL)isPlaying
{	
	return (BASS_ChannelIsActive(outStream) == BASS_ACTIVE_PLAYING);
}

- (NSUInteger)bitRate
{
	HSTREAM stream = self.currentStream;
	
	QWORD filepos = BASS_StreamGetFilePosition(stream, BASS_FILEPOS_CURRENT); // current file position
	QWORD decpos = BASS_ChannelGetPosition(stream, BASS_POS_BYTE|BASS_POS_DECODE); // decoded PCM position
	double bitrate = filepos * 8 / BASS_ChannelBytes2Seconds(stream, decpos);
	return (NSUInteger)(bitrate / 1000);
}

- (NSUInteger)currentByteOffset
{
	return self.bitRate * 128 * self.progress;
}

- (float)progress
{
	HSTREAM stream = self.currentStream;
    
	NSUInteger bytePosition;
	//if (isStartFromOffset)
	//	bytePosition = BASS_StreamGetFilePosition(stream, BASS_FILEPOS_START) + BASS_StreamGetFilePosition(stream, BASS_FILEPOS_CURRENT);
	//else
	//	bytePosition = BASS_StreamGetFilePosition(stream, BASS_FILEPOS_CURRENT);
    bytePosition = BASS_StreamGetFilePosition(stream, BASS_FILEPOS_CURRENT) + startByteOffset;
	
	float bitRateInBytes = (float)((self.bitRate * 1024) / 8);
	float progress = bytePosition / bitRateInBytes;

	if (isfinite(progress))
		return progress;

	return 0;
}

- (void)seekToPositionInBytes:(NSUInteger)bytes
{
	[self startWithOffsetInBytes:[NSNumber numberWithInt:bytes]];
}

/*- (void)seekToPositionInSeconds:(NSUInteger)seconds
{
	//NSUInteger byteOffset = self.bitRate * 128 * seconds;
	//[self seekToPositionInBytes:byteOffset];

	HSTREAM stream = self.currentStream;
	NSUInteger bytes = BASS_ChannelSeconds2Bytes(stream, seconds);
	[self startWithOffsetInBytes:bytes];
}*/

- (void)clearEqualizer
{
	int i = 0;
	for (BassEffectHandle *handle in eqHandleArray)
	{
		BASS_ChannelRemoveFX(outStream, handle.effectHandle);
		i++;
	}
	
	for (BassParamEqValue *value in eqValueArray)
	{
		value.handle = 0;
	}
	
	DLog(@"removed %i effect channels", i);
	[eqHandleArray removeAllObjects];
	isEqualizerOn = NO;
}

- (void)applyEqualizer:(NSArray *)values
{
	if (values == nil)
		return;
	else if ([values count] == 0)
		return;
	
	int i = 0;
	for (BassParamEqValue *value in eqValueArray)
	{
		HFX handle = BASS_ChannelSetFX(outStream, BASS_FX_DX8_PARAMEQ, 0);
		BASS_DX8_PARAMEQ p = value.parameters;
		BASS_FXSetParameters(handle, &p);
		
		value.handle = handle;
		
		DLog(@"applying eq for handle: %i  new values: center: %f   gain: %f   bandwidth: %f", value.handle, p.fCenter, p.fGain, p.fBandwidth);
		
		[eqHandleArray addObject:[BassEffectHandle handleWithEffectHandle:handle]];
		i++;
	}
	DLog(@"applied %i eq values", i);
	isEqualizerOn = YES;
}

- (void)updateEqParameter:(BassParamEqValue *)value
{
	[eqValueArray replaceObjectAtIndex:value.arrayIndex withObject:value]; 
	
	if (isEqualizerOn)
	{
		//BASS_DX8_PARAMEQ oldP;
		//BASS_FXGetParameters(value.handle, &oldP);
		//DLog(@"old values: handle: %i   center: %f  gain: %f   bandwidth: %f", value.handle, oldP.fCenter, oldP.fGain, oldP.fBandwidth);
		
		BASS_DX8_PARAMEQ p = value.parameters;
		DLog(@"updating eq for handle: %i   new freq: %f   new gain: %f", value.handle, p.fCenter, p.fGain);
		BASS_FXSetParameters(value.handle, &p);
	}
}

- (BassParamEqValue *)addEqualizerValue:(BASS_DX8_PARAMEQ)value
{
	NSUInteger newIndex = [eqValueArray count];
	BassParamEqValue *eqValue = [BassParamEqValue valueWithParams:value arrayIndex:newIndex];
	[eqValueArray addObject:eqValue];
	
	if (isEqualizerOn)
	{
		HFX handle = BASS_ChannelSetFX(outStream, BASS_FX_DX8_PARAMEQ, 0);
		BASS_FXSetParameters(handle, &value);
		eqValue.handle = handle;
	
		[eqHandleArray addObject:[BassEffectHandle handleWithEffectHandle:handle]];
	}
	
	return eqValue;
}

- (NSArray *)removeEqualizerValue:(BassParamEqValue *)value
{
	if (isEqualizerOn)
	{
		// Disable the effect channel
		BASS_ChannelRemoveFX(outStream, value.handle);
	}
	
	// Remove the handle
	[eqHandleArray removeObject:[BassEffectHandle handleWithEffectHandle:value.handle]];
	
	// Remove the value
	[eqValueArray removeObject:value];
	for (int i = value.arrayIndex; i < [eqValueArray count]; i++)
	{
		// Adjust the arrayIndex values for the other objects
		BassParamEqValue *aValue = [eqValueArray objectAtIndex:i];
		aValue.arrayIndex = i;
	}
	
	return self.equalizerValues;
}

- (void)removeAllEqualizerValues
{
	[self clearEqualizer];
	
	[eqValueArray removeAllObjects];
}

- (BOOL)toggleEqualizer
{
	if (isEqualizerOn)
	{
		[self clearEqualizer];
		return NO;
	}
	else
	{
		[self applyEqualizer:eqValueArray];
		return YES;
	}
}

- (NSArray *)equalizerValues
{
	return [NSArray arrayWithArray:eqValueArray];
}

- (float)fftData:(NSUInteger)index
{
	return fftData[index];
}

- (short)lineSpecData:(NSUInteger)index
{
    return lineSpecBuf[index];
}

- (HSTREAM)currentStream
{
	return isFilestream1 ? fileStream1 : fileStream2;
}

- (HSTREAM)nextStream
{
	return isFilestream1 ? fileStream2 : fileStream1;
}

#pragma mark - Singleton methods

static BassWrapperSingleton *sharedInstance = nil;

- (void)setup
{
	selfRef = self;
	isEqualizerOn = NO;
	isTempDownload = NO;
    startByteOffset = 0;
    currPlaylistDAO = [[SUSCurrentPlaylistDAO alloc] init];
	currPlaylistDAORef = currPlaylistDAO;
    
	eqValueArray = [[NSMutableArray alloc] initWithCapacity:4];
	eqHandleArray = [[NSMutableArray alloc] initWithCapacity:4];
	BassEffectDAO *effectDAO = [[BassEffectDAO alloc] initWithType:BassEffectType_ParametricEQ];
	[effectDAO selectPresetId:effectDAO.selectedPresetId];
	
	if (SCREEN_SCALE() == 1.0 && !IS_IPAD())
		lineSpecBufSize = 256 * sizeof(short);
	else
		lineSpecBufSize = 512 * sizeof(short);
	lineSpecBuf = malloc(lineSpecBufSize);
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prepareNextSongStreamInBackground) name:ISMSNotification_RepeatModeChanged object:nil];
}

+ (BassWrapperSingleton *)sharedInstance
{
    @synchronized(self)
    {
		if (sharedInstance == nil)
			[[self alloc] init];
    }
    return sharedInstance;
}

+ (id)allocWithZone:(NSZone *)zone 
{
    @synchronized(self) 
	{
        if (sharedInstance == nil) 
		{
            sharedInstance = [super allocWithZone:zone];
			[sharedInstance setup];
            return sharedInstance;  // assignment and return on first allocation
        }
    }
    return nil; // on subsequent allocation attempts return nil
}

-(id)init 
{
	if ((self = [super init]))
	{
		sharedInstance = self;
		[self setup];
	}
	
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain 
{
    return self;
}

- (unsigned)retainCount 
{
    return UINT_MAX;  // denotes an object that cannot be released
}

- (oneway void)release 
{
    //do nothing
}

- (id)autorelease 
{
    return self;
}

@end






/*DWORD GetSilenceLength(const char *file)
 {
 BYTE buf[10000];
 DWORD count=0;
 HSTREAM chan = BASS_StreamCreateFile(FALSE, file, 0, 0, BASS_STREAM_DECODE); // create decoding channel
 if (!chan)
 DLog(@"getsilencelength error: %i", BASS_ErrorGetCode());
 while (BASS_ChannelIsActive(chan)) 
 {
 int a,b = BASS_ChannelGetData(chan, buf, 10000); // decode some data
 for (a = 0; a < b && !buf[a]; a++) ; // count silent bytes
 count += a; // add number of silent bytes
 if (a < b) break; // sound has begun!
 }
 DLog(@"silence: %i", count);
 BASS_StreamFree(chan);
 return count;
 }*/




/*DWORD DataForStream(void *buffer, DWORD length, void *user)
 {
 DWORD r;
 
 @autoreleasepool 
 {
 HSTREAM stream = self.currentStream;
 HSTREAM otherStream = self.nextStream;
 
 // Read data from stream
 r = BASS_ChannelGetData(stream, buffer, length);
 
 // Check if stream is now complete
 if (!BASS_ChannelIsActive(stream))
 {		
 // Stream is done, free the stream
 BASS_StreamFree(stream);
 
 // Increment current playlist index
 [SUSCurrentPlaylistDAO dataModel].currentIndex++;
 
 // Send song end notification
 [selfRef performSelectorOnMainThread:@selector(sendSongEndNotification) withObject:nil waitUntilDone:NO];
 
 // Check to see if there is another song to play
 if (BASS_ChannelIsActive(otherStream))
 {
 // Send song start notification
 [selfRef performSelectorOnMainThread:@selector(sendSongStartNotification) withObject:nil waitUntilDone:NO];
 
 // Read data from stream2
 isStartFromOffset = NO;
 isFilestream1 = !isFilestream1;
 r = BASS_ChannelGetData(otherStream, buffer, length);
 
 // Prepare the next song for playback
 [selfRef performSelectorInBackground:@selector(prepareNextSongStream) withObject:nil];
 }
 }
 }
 
 return r;
 }
 
 DWORD CALLBACK MyStreamProc(HSTREAM handle, void *buffer, DWORD length, void *user)
 {
 DWORD r;
 
 @autoreleasepool 
 {
 if (isFilestream1 && BASS_ChannelIsActive(fileStream1)) 
 {
 r = DataForStream(&buffer, length, &user);
 }
 else if (BASS_ChannelIsActive(fileStream2)) 
 {
 r = DataForStream(&buffer, length, &user);
 }
 else
 {
 //DLog(@"no more data, ending");
 r = BASS_STREAMPROC_END;
 }
 }
 
 return r;
 }*/
