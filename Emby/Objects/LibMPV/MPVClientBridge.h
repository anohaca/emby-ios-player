#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MPVClientBridgeDelegate <NSObject>
- (void)mpvClientDidUpdateTime:(double)time duration:(double)duration;
- (void)mpvClientDidUpdatePaused:(BOOL)paused;
- (void)mpvClientDidUpdateBuffering:(BOOL)buffering;
- (void)mpvClientDidUpdateVideoRectWithX:(double)x
                                       y:(double)y
                                   width:(double)width
                                  height:(double)height
                                osdWidth:(double)osdWidth
                               osdHeight:(double)osdHeight
                              marginLeft:(double)marginLeft
                             marginRight:(double)marginRight
                               marginTop:(double)marginTop
                            marginBottom:(double)marginBottom;
- (void)mpvClientDidRenderFirstFrame;
- (void)mpvClientDidFinishPlayback;
- (void)mpvClientDidFailWithMessage:(NSString *)message;
- (void)mpvClientDidLog:(NSString *)message;
- (void)mpvClientDidUpdateSubtitleTracks:(NSArray<NSDictionary<NSString *, id> *> *)tracks
                              selectedID:(nullable NSString *)selectedID;
- (void)mpvClientDidUpdateSubtitleText:(nullable NSString *)text;
@end

@interface MPVClientBridge : NSObject

@property (nonatomic, weak, nullable) id<MPVClientBridgeDelegate> delegate;
@property (nonatomic, readonly) BOOL isInitialized;

- (instancetype)initWithLayer:(CALayer *)layer;
- (BOOL)initializePlayer:(NSError **)error;
- (void)loadURL:(NSURL *)url;
- (void)loadURL:(NSURL *)url headers:(NSDictionary<NSString *, NSString *> *)headers;
- (void)loadURL:(NSURL *)url
        headers:(NSDictionary<NSString *, NSString *> *)headers
   startSeconds:(double)startSeconds;
- (void)setPaused:(BOOL)paused;
- (void)setMuted:(BOOL)muted;
- (void)setPlaybackSpeed:(double)speed;
- (void)setPreferredAudioLanguages:(nullable NSString *)languages;
- (void)setPreferredSubtitleLanguages:(nullable NSString *)languages;
- (void)setSubtitlePosition:(double)position;
- (void)setSubtitleScale:(double)scale;
- (void)setSubtitleBorderSize:(double)borderSize;
- (void)seekToSeconds:(double)seconds;
- (void)refreshVideoRect;
- (void)nudgeVideoOutputAfterForeground;
- (void)stop;
- (void)cycleAudioTrack;
- (void)cycleSubtitleTrack;
- (void)addSubtitleURL:(NSURL *)url;
- (void)addSubtitleURL:(NSURL *)url title:(nullable NSString *)title;
- (void)selectAudioTrackID:(NSString *)trackID;
- (void)selectSubtitleTrackID:(NSString *)trackID;
- (void)disableSubtitle;
- (void)logPerformanceSnapshotWithReason:(NSString *)reason;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
