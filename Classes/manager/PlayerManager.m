//
//  PlayerManager.m
//  OggSpeex
//
//  Created by Jiang Chuncheng on 6/25/13.
//  Copyright (c) 2013 Sense Force. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PlayerManager.h"

@interface PlayerManager ()

- (void)startProximityMonitering;  //开启距离感应器监听(开始播放时)
- (void)stopProximityMonitering;   //关闭距离感应器监听(播放完成时)

@end

@implementation PlayerManager
{
    NSString *_playingFileName;
    NSString *_playingTag;
}
@synthesize decapsulator;
@synthesize avAudioPlayer;

static PlayerManager *mPlayerManager = nil;

+ (PlayerManager *)sharedManager {
    static PlayerManager *g_playerManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_playerManager = [[PlayerManager alloc] init];
    });
    return g_playerManager;
}

+ (id)allocWithZone:(NSZone *)zone
{
    @synchronized(self)
    {
        if(mPlayerManager == nil)
        {
            mPlayerManager = [super allocWithZone:zone];
            return mPlayerManager;
        }
    }
    
    return nil;
}

- (id)init {
    if (self = [super init]) {

        [[NSNotificationCenter defaultCenter] addObserver:mPlayerManager
                                                 selector:@selector(sensorStateChange:)
                                                     name:UIDeviceProximityStateDidChangeNotification
                                                   object:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

        //初始化播放器的时候如下设置
        UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
        AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
        UInt32 audioRouteOverride = kAudioSessionOverrideAudioRoute_Speaker;
        AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute, sizeof(audioRouteOverride), &audioRouteOverride);
#pragma clang diagnostic pop

        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        //默认情况下扬声器播放
        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        [audioSession setActive:YES error:nil];
    }
    return self;
}

- (void)playAudioWithFileName:(NSString *)filename delegate:(id<PlayingDelegate>)newDelegate tag:(NSString *)tag {
    if (!filename) {
        [newDelegate playingStoped:tag];
        return;
    }
    if ([filename rangeOfString:@".spx"].location != NSNotFound) {
        
        [self stopPlaying];
        
        self.delegate = newDelegate;
        
        self.decapsulator = [[Decapsulator alloc] initWithFileName:filename];
        self.decapsulator.delegate = self;
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];

        [self startProximityMonitering];
        _playingFileName = [filename copy];
        _playingTag = [tag copy];
        [self.decapsulator play];
        
    }
    else if ([filename rangeOfString:@".mp3"].location != NSNotFound) {
        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:filename]) {
            NSLog(@"1 Voice PlayerManager 要播放的文件不存在:%@", filename);
            _playingFileName = nil;
            _playingTag = nil ;
            [self.delegate playingStoped:_playingTag];
            [newDelegate playingStoped:tag];
            return;
        }
        
        [self.delegate playingStoped:_playingTag];
        self.delegate = newDelegate;
        
        NSError *error;
        self.avAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL URLWithString:filename] error:&error];
        if (self.avAudioPlayer) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            self.avAudioPlayer.delegate = self;
            _playingFileName = [filename copy];
            _playingTag = [tag copy];
            [self.avAudioPlayer play];
            [self startProximityMonitering];
        } else {
            _playingFileName = nil ;
            _playingTag = nil ;
            [self.delegate playingStoped:_playingTag];
        }
    }
    else if([filename rangeOfString:@".caf"].location != NSNotFound)
    {
        [self.delegate playingStoped:_playingTag];
        self.delegate = newDelegate;
     
        _playingFileName = nil;
        _playingTag = nil ;
        
        NSError *error;
        NSArray *array  =[filename componentsSeparatedByString:@"."];
        NSString *bundlePath=[[NSBundle mainBundle]pathForResource:@"Resource" ofType:@"bundle"];
        NSBundle *bundle=[NSBundle bundleWithPath:bundlePath];
        NSString *soundPath=[bundle pathForResource:array[0] ofType:@"caf"inDirectory:nil];
        if (soundPath ==nil) {
            NSLog(@"3 Voice PlayerManager 要播放的文件不存在:%@", filename);
            [newDelegate playingStoped:tag];
            return;
        }
        NSURL *soundUrl=[[NSURL alloc] initFileURLWithPath:soundPath];
        self.avAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:soundUrl error:&error];
        if (self.avAudioPlayer) {
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            _playingFileName = [soundPath copy];
            _playingTag = [tag copy];
            self.avAudioPlayer.delegate = self;
            [self.avAudioPlayer play];
            [self startProximityMonitering];
        } else {
            [self.delegate playingStoped:tag];
            _playingTag = nil ;
            _playingFileName = nil;
        }
    }
    else {
        [newDelegate playingStoped:tag];
    }
}

-(BOOL)isPlaying{
    return  [self.decapsulator isPlaying] || self.avAudioPlayer.isPlaying;
}

- (void)stopPlaying {
    if (self.decapsulator) {
        [self.decapsulator stopPlaying];
//        self.decapsulator.delegate = nil;   //此行如果放在上一行之前会导致回调问题
        self.decapsulator = nil;
    } else if (self.avAudioPlayer) {
        [self.avAudioPlayer stop];
        self.avAudioPlayer = nil;
    } else {
        [self handlePlayedDone];
    }
    [self stopProximityMonitering];

}

- (NSString *)playingFileName
{
    return _playingFileName;
}
-(NSString *)playingTag{
    return _playingTag;
}

- (void)decapsulatingAndPlayingOver {
    [self handlePlayedDone];
}


-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    [self handlePlayedDone];
}

-(void)handlePlayedDone{
    [[NSNotificationCenter defaultCenter]postNotificationName:DDStopPlayedNotification object:@{@"file":_playingFileName ? : @"",@"tag":_playingTag ? : @""}];
    [self.delegate playingStoped:_playingTag];
    _playingFileName = nil;
    _playingTag = nil ;
    
    [self stopProximityMonitering];
}

- (void)sensorStateChange:(NSNotification *)notification {
    //如果此时手机靠近面部放在耳朵旁，那么声音将通过听筒输出，并将屏幕变暗
    if ([[UIDevice currentDevice] proximityState] == YES) {
//        NSLog(@"Device is close to user");
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    }
    else {
//        NSLog(@"Device is not close to user");
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    }
}

- (void)startProximityMonitering {
    [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
//    NSLog(@"开启距离监听");
}

- (void)stopProximityMonitering {

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
//        NSLog(@"关闭距离监听");

}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
