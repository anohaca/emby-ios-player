#import "MPVClientBridge.h"

#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <mpv/client.h>

static void *MPVClientBridgeQueueKey = &MPVClientBridgeQueueKey;
static const NSUInteger MPVClientBridgeMaxDiagnosticLength = 4000;
static const NSUInteger MPVClientBridgeMaxNodeStringLength = 2000;
static const NSUInteger MPVClientBridgeMaxNodeDepth = 4;
static const int MPVClientBridgeMaxNodeEntries = 32;
static const double MPVClientBridgeSubtitleBaseFontSize = 38.0;

static const uint64_t MPVObservedTimePos = 1001;
static const uint64_t MPVObservedDuration = 1002;
static const uint64_t MPVObservedPause = 1003;
static const uint64_t MPVObservedOSDDimensions = 1004;
static const uint64_t MPVObservedCurrentVO = 1005;
static const uint64_t MPVObservedCurrentGPUContext = 1006;
static const uint64_t MPVObservedHWDecCurrent = 1007;
static const uint64_t MPVObservedHWDecInterop = 1008;
static const uint64_t MPVObservedVideoOutParams = 1009;
static const uint64_t MPVObservedVideoParams = 1010;
static const uint64_t MPVObservedAudioOutParams = 1011;
static const uint64_t MPVObservedTrackList = 1012;
static const uint64_t MPVObservedVOConfigured = 1013;
static const uint64_t MPVObservedSID = 1014;
static const uint64_t MPVObservedSubVisibility = 1015;
static const uint64_t MPVObservedCurrentSubTrack = 1016;
static const uint64_t MPVObservedSubText = 1017;
static const uint64_t MPVObservedSubStart = 1018;
static const uint64_t MPVObservedSubEnd = 1019;
static const uint64_t MPVObservedPausedForCache = 1020;

static NSString *MPVXMLTextEscapedString(NSString *string)
{
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"&"
                             withString:@"&amp;"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<"
                             withString:@"&lt;"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">"
                             withString:@"&gt;"
                                options:0
                                  range:NSMakeRange(0, escaped.length)];
    return escaped;
}

@interface MPVClientBridge () {
    atomic_bool _running;
    atomic_uint_fast64_t _nextCommandUserData;
}
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic) mpv_handle *mpv;
@property (nonatomic) dispatch_queue_t mpvQueue;
@property (nonatomic) BOOL isInitialized;
@property (nonatomic) BOOL diagnosticLoggingEnabled;
@property (nonatomic) BOOL rawLogMessagesEnabled;
@property (nonatomic) BOOL subtitleDiagnosticsEnabled;
@property (nonatomic) double currentTime;
@property (nonatomic) double duration;
@property (nonatomic) double pendingStartSeconds;
@property (nonatomic) BOOL pendingStartSeekIssued;
@property (nonatomic) BOOL fileLoaded;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *pendingSubtitleRequests;
@end

@implementation MPVClientBridge

- (instancetype)initWithLayer:(CALayer *)layer
{
    self = [super init];
    if (!self)
        return nil;

    _layer = layer;
    _mpvQueue = dispatch_queue_create("local.codex.libmpv.events", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(_mpvQueue, MPVClientBridgeQueueKey, MPVClientBridgeQueueKey, NULL);
    atomic_init(&self->_running, false);
    atomic_init(&self->_nextCommandUserData, 1);
    _diagnosticLoggingEnabled = [self environmentFlagEnabled:"LIBMPVPLAYER_SMOKE_LOG"] ||
                                [self environmentFlagEnabled:"LIBMPVPLAYER_TRACE_LOG"] ||
                                [self environmentFlagEnabled:"LIBMPVPLAYER_DIAGNOSTICS"];
    _rawLogMessagesEnabled = [self environmentFlagEnabled:"LIBMPVPLAYER_TRACE_LOG"] ||
                             [self environmentFlagEnabled:"LIBMPVPLAYER_RAW_LOG_MESSAGES"];
    _subtitleDiagnosticsEnabled = [self environmentFlagEnabled:"LIBMPVPLAYER_TRACE_LOG"] ||
                                  [self environmentFlagEnabled:"LIBMPVPLAYER_SUBTITLE_DIAGNOSTICS"];
    _pendingSubtitleRequests = [NSMutableArray array];
    return self;
}

- (void)dealloc
{
    [self shutdown];
}

- (BOOL)initializePlayer:(NSError **)error
{
    if (self.isInitialized)
        return YES;

    setenv("MVK_CONFIG_LOG_LEVEL", "1", 0);

    self.mpv = mpv_create();
    if (!self.mpv) {
        [self fillError:error code:-1 message:@"mpv_create failed"];
        return NO;
    }

    int64_t wid = (int64_t)(intptr_t)self.layer;
    if (![self setOption:"wid" format:MPV_FORMAT_INT64 value:&wid error:error])
        return NO;

    const char *options[][2] = {
        {"config", "no"},
        {"terminal", "no"},
        {"msg-level", "all=warn"},
        {"idle", "yes"},
        {"vo", "gpu-next"},
        {"ao", "audiounit"},
        {"gpu-api", "vulkan"},
        {"gpu-context", "iosvk"},
        {"hwdec", "videotoolbox"},
        {"network-timeout", "60"},
        {"stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5"},
        {"force-window", "no"},
        {"keep-open", "no"},
        {"sub-auto", "no"},
        {"sub-visibility", "yes"},
        {"sub-ass", "yes"},
        {"sub-ass-override", "force"},
        {"sub-font-provider", "none"},
        {"sub-font", "Noto Sans CJK SC"},
        {"sub-border-style", "outline-and-shadow"},
        {"sub-ass-style-overrides", "FontName=Noto Sans CJK SC"},
        {"sub-color", "#FFFFFFFF"},
        {"sub-outline-color", "#FF000000"},
        {"sub-back-color", "#AF000000"},
        {"sub-margin-y-offset", "0"},
        {"osd-font-provider", "none"},
        {"osd-font", "Noto Sans CJK SC"},
        {"blend-subtitles", "video"},
        {"audio-client-name", "LibMPVPlayer"},
    };

    for (size_t i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
        int rc = mpv_set_option_string(self.mpv, options[i][0], options[i][1]);
        if (rc < 0) {
            NSString *message = [NSString stringWithFormat:@"mpv_set_option_string(%s) failed: %s",
                                                           options[i][0], mpv_error_string(rc)];
            [self fillError:error code:rc message:message];
            return NO;
        }
    }

    [self configureBundledSubtitleFonts];

    const char *requestedLogLevel = "no";
    if (self.rawLogMessagesEnabled) {
        const char *envLogLevel = getenv("LIBMPVPLAYER_MPV_LOG_LEVEL");
        requestedLogLevel = envLogLevel && envLogLevel[0] ? envLogLevel : (getenv("LIBMPVPLAYER_TRACE_LOG") ? "trace" : "v");
        NSString *messageLevel = [NSString stringWithFormat:@"all=%s", requestedLogLevel];
        mpv_set_option_string(self.mpv, "msg-level", messageLevel.UTF8String);
    }

    mpv_request_log_messages(self.mpv, requestedLogLevel);
    atomic_store(&self->_running, true);
    [self startEventLoop];

    int rc = mpv_initialize(self.mpv);
    if (rc < 0) {
        atomic_store(&self->_running, false);
        mpv_wakeup(self.mpv);
        NSString *message = [NSString stringWithFormat:@"mpv_initialize failed: %s", mpv_error_string(rc)];
        [self fillError:error code:rc message:message];
        return NO;
    }

    if (self.diagnosticLoggingEnabled) {
        [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-log-level=%s", requestedLogLevel]];
    }
    [self requestInterestingEvents];
    [self observeInterestingProperties];

    self.isInitialized = YES;
    return YES;
}

- (void)configureBundledSubtitleFonts
{
    NSBundle *bundle = NSBundle.mainBundle;
    NSURL *bundledFontsURL = [bundle URLForResource:@"Fonts" withExtension:nil];
    NSURL *bundledFontURL = [bundle URLForResource:@"NotoSansCJKsc-Regular" withExtension:@"otf"];
    if (!bundledFontsURL && bundledFontURL)
        bundledFontsURL = bundledFontURL.URLByDeletingLastPathComponent;
    if (!bundledFontsURL)
        return;

    const char *bundledFontsPath = bundledFontsURL.path.fileSystemRepresentation;
    if (!bundledFontsPath || bundledFontsPath[0] == '\0')
        return;

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *applicationSupportURL = [fileManager URLsForDirectory:NSApplicationSupportDirectory
                                                       inDomains:NSUserDomainMask].firstObject;
    NSURL *cachesURL = [fileManager URLsForDirectory:NSCachesDirectory
                                           inDomains:NSUserDomainMask].firstObject;
    if (!applicationSupportURL || !cachesURL) {
        int subRC = mpv_set_option_string(self.mpv, "sub-fonts-dir", bundledFontsPath);
        int osdRC = mpv_set_option_string(self.mpv, "osd-fonts-dir", bundledFontsPath);
        [self notifyDiagnosticLine:[NSString stringWithFormat:@"subtitle-fonts-dir path=%@ sub=%s osd=%s config=skip reason=no-app-directories",
                                                               bundledFontsURL.path,
                                                               subRC < 0 ? mpv_error_string(subRC) : "ok",
                                                               osdRC < 0 ? mpv_error_string(osdRC) : "ok"]];
        return;
    }

    NSURL *configURL = [applicationSupportURL URLByAppendingPathComponent:@"mpv" isDirectory:YES];
    NSURL *fontsURL = [configURL URLByAppendingPathComponent:@"fonts" isDirectory:YES];
    NSURL *fontconfigCacheURL = [cachesURL URLByAppendingPathComponent:@"fontconfig" isDirectory:YES];
    NSURL *fontsConfURL = [configURL URLByAppendingPathComponent:@"fonts.conf"];

    NSError *directoryError = nil;
    [fileManager createDirectoryAtURL:configURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&directoryError];
    [fileManager createDirectoryAtURL:fontsURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
    [fileManager createDirectoryAtURL:fontconfigCacheURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];

    NSArray<NSURL *> *bundledFontFiles = [fileManager contentsOfDirectoryAtURL:bundledFontsURL
                                                    includingPropertiesForKeys:nil
                                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                         error:nil] ?: @[];
    NSSet<NSString *> *fontExtensions = [NSSet setWithArray:@[@"otf", @"ttf", @"ttc"]];
    for (NSURL *sourceURL in bundledFontFiles) {
        if (![fontExtensions containsObject:sourceURL.pathExtension.lowercaseString])
            continue;

        NSURL *destinationURL = [fontsURL URLByAppendingPathComponent:sourceURL.lastPathComponent];
        if (![fileManager fileExistsAtPath:destinationURL.path])
            [fileManager copyItemAtURL:sourceURL toURL:destinationURL error:nil];
    }

    NSError *writeError = nil;
    if (!directoryError) {
        NSString *escapedFontsPath = MPVXMLTextEscapedString(fontsURL.path);
        NSString *escapedCachePath = MPVXMLTextEscapedString(fontconfigCacheURL.path);
        NSArray<NSString *> *families = @[@"simhei", @"SimHei", @"黑体", @"黑體", @"Heiti SC", @"sans-serif"];
        NSMutableString *familyRules = [NSMutableString string];
        for (NSString *family in families) {
            NSString *escapedFamily = MPVXMLTextEscapedString(family);
            [familyRules appendFormat:
                @"  <alias>\n"
                 "    <family>%@</family>\n"
                 "    <prefer><family>Noto Sans CJK SC</family></prefer>\n"
                 "  </alias>\n"
                 "  <match target=\"pattern\">\n"
                 "    <test qual=\"any\" name=\"family\"><string>%@</string></test>\n"
                 "    <edit name=\"family\" mode=\"prepend\" binding=\"strong\"><string>Noto Sans CJK SC</string></edit>\n"
                 "  </match>\n",
                 escapedFamily,
                 escapedFamily];
        }

        NSString *fontsConf = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?>\n"
             "<fontconfig>\n"
             "  <dir>%@</dir>\n"
             "  <cachedir>%@</cachedir>\n"
             "%@"
             "</fontconfig>\n",
             escapedFontsPath,
             escapedCachePath,
             familyRules];

        [fontsConf writeToURL:fontsConfURL
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:&writeError];
    }

    int configDirRC = 0;
    int configRC = 0;
    if (!directoryError && !writeError) {
        const char *configPath = configURL.path.fileSystemRepresentation;
        const char *fontsConfPath = fontsConfURL.path.fileSystemRepresentation;
        const char *cachePath = fontconfigCacheURL.path.fileSystemRepresentation;
        if (configPath && configPath[0] != '\0')
            setenv("FONTCONFIG_PATH", configPath, 1);
        if (fontsConfPath && fontsConfPath[0] != '\0')
            setenv("FONTCONFIG_FILE", fontsConfPath, 1);
        if (cachePath && cachePath[0] != '\0')
            setenv("FONTCONFIG_CACHE", cachePath, 1);

        configDirRC = mpv_set_option_string(self.mpv, "config-dir", configPath);
        configRC = mpv_set_option_string(self.mpv, "config", "yes");
    }

    const char *fontsPath = fontsURL.path.fileSystemRepresentation;
    int subRC = mpv_set_option_string(self.mpv, "sub-fonts-dir", fontsPath);
    int osdRC = mpv_set_option_string(self.mpv, "osd-fonts-dir", fontsPath);

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"subtitle-fonts-dir path=%@ sub=%s osd=%s configDir=%s config=%s fontsConf=%@ dirError=%@ writeError=%@",
                                                           fontsURL.path,
                                                           subRC < 0 ? mpv_error_string(subRC) : "ok",
                                                           osdRC < 0 ? mpv_error_string(osdRC) : "ok",
                                                           configDirRC < 0 ? mpv_error_string(configDirRC) : "ok",
                                                           configRC < 0 ? mpv_error_string(configRC) : "ok",
                                                           fontsConfURL.path,
                                                           directoryError.localizedDescription ?: @"",
                                                           writeError.localizedDescription ?: @""]];
}

- (void)requestInterestingEvents
{
    const mpv_event_id events[] = {
        MPV_EVENT_END_FILE,
        MPV_EVENT_FILE_LOADED,
        MPV_EVENT_VIDEO_RECONFIG,
        MPV_EVENT_PLAYBACK_RESTART,
        MPV_EVENT_PROPERTY_CHANGE,
        MPV_EVENT_SHUTDOWN,
    };

    for (size_t index = 0; index < sizeof(events) / sizeof(events[0]); index++) {
        int rc = mpv_request_event(self.mpv, events[index], 1);
        if (rc < 0) {
            const char *name = mpv_event_name(events[index]) ?: "unknown";
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-event-request name=%s error=%s",
                                                                   name,
                                                                   mpv_error_string(rc)]];
        }
    }

    if (!self.diagnosticLoggingEnabled)
        return;

    const mpv_event_id diagnosticEvents[] = {
        MPV_EVENT_GET_PROPERTY_REPLY,
        MPV_EVENT_SET_PROPERTY_REPLY,
        MPV_EVENT_COMMAND_REPLY,
        MPV_EVENT_START_FILE,
        MPV_EVENT_CLIENT_MESSAGE,
        MPV_EVENT_AUDIO_RECONFIG,
        MPV_EVENT_SEEK,
        MPV_EVENT_QUEUE_OVERFLOW,
        MPV_EVENT_HOOK,
    };

    for (size_t index = 0; index < sizeof(diagnosticEvents) / sizeof(diagnosticEvents[0]); index++) {
        int rc = mpv_request_event(self.mpv, diagnosticEvents[index], 1);
        if (rc < 0) {
            const char *name = mpv_event_name(diagnosticEvents[index]) ?: "unknown";
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-event-request name=%s error=%s",
                                                                   name,
                                                                   mpv_error_string(rc)]];
        }
    }

    if (!self.rawLogMessagesEnabled)
        return;

    int rc = mpv_request_event(self.mpv, MPV_EVENT_LOG_MESSAGE, 1);
    if (rc < 0) {
        [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-event-request name=%s error=%s",
                                                               mpv_event_name(MPV_EVENT_LOG_MESSAGE) ?: "log-message",
                                                               mpv_error_string(rc)]];
    }
}

- (void)observeInterestingProperties
{
    const struct {
        const char *name;
        mpv_format format;
        uint64_t userdata;
    } properties[] = {
        {"time-pos", MPV_FORMAT_DOUBLE, MPVObservedTimePos},
        {"duration", MPV_FORMAT_DOUBLE, MPVObservedDuration},
        {"pause", MPV_FORMAT_FLAG, MPVObservedPause},
        {"osd-dimensions", MPV_FORMAT_NODE, MPVObservedOSDDimensions},
        {"track-list", MPV_FORMAT_NODE, MPVObservedTrackList},
        {"sid", MPV_FORMAT_STRING, MPVObservedSID},
        {"sub-text", MPV_FORMAT_STRING, MPVObservedSubText},
        {"sub-visibility", MPV_FORMAT_FLAG, MPVObservedSubVisibility},
        {"paused-for-cache", MPV_FORMAT_FLAG, MPVObservedPausedForCache},
    };

    for (size_t index = 0; index < sizeof(properties) / sizeof(properties[0]); index++) {
        int rc = mpv_observe_property(self.mpv,
                                      properties[index].userdata,
                                      properties[index].name,
                                      properties[index].format);
        if (rc < 0) {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-property-observe name=%s error=%s",
                                                                   properties[index].name,
                                                                   mpv_error_string(rc)]];
        }
    }

    if (!self.diagnosticLoggingEnabled)
        return;

    const struct {
        const char *name;
        mpv_format format;
        uint64_t userdata;
    } diagnosticProperties[] = {
        {"current-vo", MPV_FORMAT_STRING, MPVObservedCurrentVO},
        {"current-gpu-context", MPV_FORMAT_STRING, MPVObservedCurrentGPUContext},
        {"hwdec-current", MPV_FORMAT_STRING, MPVObservedHWDecCurrent},
        {"hwdec-interop", MPV_FORMAT_STRING, MPVObservedHWDecInterop},
        {"video-out-params", MPV_FORMAT_NODE, MPVObservedVideoOutParams},
        {"video-params", MPV_FORMAT_NODE, MPVObservedVideoParams},
        {"audio-out-params", MPV_FORMAT_NODE, MPVObservedAudioOutParams},
        {"vo-configured", MPV_FORMAT_FLAG, MPVObservedVOConfigured},
    };

    for (size_t index = 0; index < sizeof(diagnosticProperties) / sizeof(diagnosticProperties[0]); index++) {
        int rc = mpv_observe_property(self.mpv,
                                      diagnosticProperties[index].userdata,
                                      diagnosticProperties[index].name,
                                      diagnosticProperties[index].format);
        if (rc < 0) {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-property-observe name=%s error=%s",
                                                                   diagnosticProperties[index].name,
                                                                   mpv_error_string(rc)]];
        }
    }

    if (!self.subtitleDiagnosticsEnabled)
        return;

    const struct {
        const char *name;
        mpv_format format;
        uint64_t userdata;
    } subtitleDiagnosticProperties[] = {
        {"current-tracks/sub", MPV_FORMAT_NODE, MPVObservedCurrentSubTrack},
        {"sub-start", MPV_FORMAT_DOUBLE, MPVObservedSubStart},
        {"sub-end", MPV_FORMAT_DOUBLE, MPVObservedSubEnd},
    };

    for (size_t index = 0; index < sizeof(subtitleDiagnosticProperties) / sizeof(subtitleDiagnosticProperties[0]); index++) {
        int rc = mpv_observe_property(self.mpv,
                                      subtitleDiagnosticProperties[index].userdata,
                                      subtitleDiagnosticProperties[index].name,
                                      subtitleDiagnosticProperties[index].format);
        if (rc < 0) {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-property-observe name=%s error=%s",
                                                                   subtitleDiagnosticProperties[index].name,
                                                                   mpv_error_string(rc)]];
        }
    }
}

- (void)loadURL:(NSURL *)url
{
    [self loadURL:url headers:@{}];
}

- (void)loadURL:(NSURL *)url headers:(NSDictionary<NSString *, NSString *> *)headers
{
    [self loadURL:url headers:headers startSeconds:0.0];
}

- (void)loadURL:(NSURL *)url
        headers:(NSDictionary<NSString *, NSString *> *)headers
   startSeconds:(double)startSeconds
{
    if (!self.mpv || !url)
        return;

    [self applyHTTPHeaders:headers ?: @{}];

    NSString *location = url.isFileURL ? url.path : url.absoluteString;
    if (location.length == 0)
        return;

    self.currentTime = 0.0;
    self.duration = 0.0;
    self.pendingStartSeconds = (isfinite(startSeconds) && startSeconds > 0) ? startSeconds : 0.0;
    self.pendingStartSeekIssued = NO;
    [self notifySubtitleText:nil];
    @synchronized (self) {
        self.fileLoaded = NO;
        [self.pendingSubtitleRequests removeAllObjects];
    }

    const char *path = url.isFileURL ? url.path.fileSystemRepresentation : location.UTF8String;
    NSString *startOption = nil;
    const char *cmdWithoutStart[] = {"loadfile", path, "replace", NULL};
    const char *cmdWithStart[6] = {"loadfile", path, "replace", "-1", NULL, NULL};
    if (isfinite(startSeconds) && startSeconds > 0) {
        startOption = [NSString stringWithFormat:@"start=%.3f", startSeconds];
        cmdWithStart[4] = startOption.UTF8String;
    }
    [self commandAsync:startOption ? cmdWithStart : cmdWithoutStart];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-loadfile url=%@ isFile=%@ headerCount=%lu startSeconds=%.3f",
                                                           url.isFileURL ? url.path : url.absoluteString,
                                                           url.isFileURL ? @"true" : @"false",
                                                           (unsigned long)headers.count,
                                                           startSeconds]];
}

- (void)applyHTTPHeaders:(NSDictionary<NSString *, NSString *> *)headers
{
    if (!self.mpv)
        return;

    NSArray<NSString *> *keys = [headers.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithCapacity:keys.count];
    NSMutableArray<NSString *> *fieldNames = [NSMutableArray arrayWithCapacity:keys.count];
    NSString *userAgent = nil;

    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *rawKey in keys) {
        if (![rawKey isKindOfClass:NSString.class])
            continue;
        NSString *key = [rawKey stringByTrimmingCharactersInSet:whitespace];
        NSString *rawValue = headers[rawKey];
        if (![rawValue isKindOfClass:NSString.class])
            continue;
        NSString *value = [rawValue stringByTrimmingCharactersInSet:whitespace];
        if (key.length == 0 || value.length == 0)
            continue;

        [fields addObject:[NSString stringWithFormat:@"%@: %@", key, value]];
        [fieldNames addObject:key];
        if ([key caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame)
            userAgent = value;
    }

    mpv_node node = {0};
    mpv_node_list list = {0};
    mpv_node *values = NULL;
    node.format = MPV_FORMAT_NODE_ARRAY;
    node.u.list = &list;
    list.num = (int)fields.count;

    if (fields.count > 0) {
        values = calloc(fields.count, sizeof(mpv_node));
        if (!values) {
            [self notifyDiagnosticLine:@"mpv-http-headers result=alloc-failed"];
            return;
        }

        list.values = values;
        for (NSUInteger index = 0; index < fields.count; index++) {
            values[index].format = MPV_FORMAT_STRING;
            values[index].u.string = (char *)fields[index].UTF8String;
        }
    }

    int rc = mpv_set_option(self.mpv, "http-header-fields", MPV_FORMAT_NODE, &node);
    free(values);

    if (userAgent.length > 0)
        mpv_set_option_string(self.mpv, "user-agent", userAgent.UTF8String);

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-http-headers count=%lu names=%@ rc=%s",
                                                           (unsigned long)fields.count,
                                                           [self singleLineString:[fieldNames componentsJoinedByString:@","]
                                                                         maxLength:MPVClientBridgeMaxDiagnosticLength],
                                                           mpv_error_string(rc)]];
}

- (void)setPaused:(BOOL)paused
{
    int flag = paused ? 1 : 0;
    [self setProperty:"pause" format:MPV_FORMAT_FLAG value:&flag];
}

- (void)setMuted:(BOOL)muted
{
    int flag = muted ? 1 : 0;
    [self setProperty:"mute" format:MPV_FORMAT_FLAG value:&flag];
}

- (void)setPlaybackSpeed:(double)speed
{
    double value = MAX(0.25, MIN(speed, 4.0));
    [self setProperty:"speed" format:MPV_FORMAT_DOUBLE value:&value];
}

- (void)setPreferredAudioLanguages:(NSString *)languages
{
    [self setPreferredTrackLanguages:languages option:"alang" diagnosticName:@"audio"];
}

- (void)setPreferredSubtitleLanguages:(NSString *)languages
{
    [self setPreferredTrackLanguages:languages option:"slang" diagnosticName:@"subtitle"];
}

- (void)setPreferredTrackLanguages:(NSString *)languages option:(const char *)option diagnosticName:(NSString *)diagnosticName
{
    NSString *normalized = [languages stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    const char *value = normalized.length > 0 ? normalized.UTF8String : "";
    [self setProperty:option format:MPV_FORMAT_STRING value:&value];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-%@-language-default value=%@",
                                                           diagnosticName ?: @"track",
                                                           normalized.length > 0 ? normalized : @"<auto>"]];
}

- (void)setSubtitlePosition:(double)position
{
    double value = MAX(0.0, MIN(position, 100.0));
    [self setProperty:"sub-pos" format:MPV_FORMAT_DOUBLE value:&value];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-position value=%.2f", value]];
}

- (void)setSubtitleScale:(double)scale
{
    double value = MAX(0.5, MIN(scale, 2.5));
    double fontSize = MPVClientBridgeSubtitleBaseFontSize * value;
    double neutralScale = 1.0;
    int64_t marginYOffset = 0;
    int marginRC = [self setProperty:"sub-margin-y-offset" format:MPV_FORMAT_INT64 value:&marginYOffset];
    int scaleRC = [self setProperty:"sub-scale" format:MPV_FORMAT_DOUBLE value:&neutralScale];
    int fontRC = [self setProperty:"sub-font-size" format:MPV_FORMAT_DOUBLE value:&fontSize];
    NSString *line = [NSString stringWithFormat:@"mpv-subtitle-scale value=%.2f fontSize=%.2f fontRC=%s scaleRC=%s marginRC=%s",
                                                value,
                                                fontSize,
                                                mpv_error_string(fontRC),
                                                mpv_error_string(scaleRC),
                                                mpv_error_string(marginRC)];
    [self notifyDiagnosticLine:line];
    if ([[NSProcessInfo processInfo].arguments containsObject:@"-EmbyPlaybackSmokeExerciseSubtitleScale"]) {
        NSLog(@"%@", line);
    }
}

- (void)setSubtitleBorderSize:(double)borderSize
{
    double value = MAX(0.0, MIN(borderSize, 8.0));
    int borderRC = [self setProperty:"sub-border-size" format:MPV_FORMAT_DOUBLE value:&value];
    NSString *line = [NSString stringWithFormat:@"mpv-subtitle-border-size value=%.2f borderRC=%s assOverride=force",
                                                value,
                                                mpv_error_string(borderRC)];
    [self notifyDiagnosticLine:line];
    if ([[NSProcessInfo processInfo].arguments containsObject:@"-EmbyPlaybackSmokeExerciseSubtitleBorder"]) {
        NSLog(@"%@", line);
    }
}

- (void)seekToSeconds:(double)seconds
{
    if (!self.mpv)
        return;

    NSString *target = [NSString stringWithFormat:@"%.3f", seconds];
    const char *cmd[] = {"seek", target.UTF8String, "absolute", "exact", NULL};
    mpv_command_async(self.mpv, 0, cmd);
}

- (void)refreshVideoRect
{
    if (!self.mpv)
        return;

    [self queueVideoRectRefreshAfterDelay:0.0];
    [self queueVideoRectRefreshAfterDelay:0.25];
}

- (void)queueVideoRectRefreshAfterDelay:(NSTimeInterval)delay
{
    dispatch_block_t block = ^{
        mpv_handle *handle = self.mpv;
        if (!handle)
            return;

        mpv_node node = {0};
        int rc = mpv_get_property(handle, "osd-dimensions", MPV_FORMAT_NODE, &node);
        if (rc >= 0) {
            [self handleOSDDimensions:&node];
            mpv_free_node_contents(&node);
        }
    };

    if (delay <= 0.0) {
        dispatch_async(self.mpvQueue, block);
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       self.mpvQueue,
                       block);
    }
}

- (void)stop
{
    if (!self.mpv)
        return;

    @synchronized (self) {
        self.fileLoaded = NO;
        [self.pendingSubtitleRequests removeAllObjects];
    }
    [self notifySubtitleText:nil];

    const char *cmd[] = {"stop", NULL};
    mpv_command_async(self.mpv, 0, cmd);
}

- (void)cycleAudioTrack
{
    const char *cmd[] = {"cycle", "aid", NULL};
    [self commandAsync:cmd];
}

- (void)cycleSubtitleTrack
{
    const char *cmd[] = {"cycle", "sid", NULL};
    [self commandAsync:cmd];
}

- (void)addSubtitleURL:(NSURL *)url
{
    [self addSubtitleURL:url title:nil];
}

- (void)addSubtitleURL:(NSURL *)url title:(NSString *)title
{
    if (!self.mpv)
        return;

    NSURL *subtitleURL = [url copy];
    NSString *subtitleTitle = [title copy] ?: @"";
    @synchronized (self) {
        if (!self.fileLoaded) {
            [self.pendingSubtitleRequests addObject:@{
                @"url": subtitleURL,
                @"title": subtitleTitle
            }];
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-queue path=%@ title=%@",
                                                                   subtitleURL.isFileURL ? subtitleURL.path : subtitleURL.absoluteString,
                                                                   subtitleTitle]];
            return;
        }
    }

    [self submitSubtitleURL:subtitleURL title:subtitleTitle reason:@"direct"];
}

- (void)submitSubtitleURL:(NSURL *)url title:(NSString *)title reason:(NSString *)reason
{
    if (!self.mpv || !url)
        return;

    NSString *pathString = url.isFileURL ? url.path : url.absoluteString;
    const char *path = url.isFileURL ? url.path.fileSystemRepresentation : pathString.UTF8String;
    NSString *displayTitle = title.length > 0 ? title : (url.lastPathComponent.length > 0 ? url.lastPathComponent : pathString);
    const char *titleValue = displayTitle.UTF8String;
    const char *cmd[] = {"sub-add", path, "auto", titleValue, NULL};
    [self commandAsync:cmd];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-add reason=%@ path=%@ title=%@",
                                                           reason ?: @"unknown",
                                                           pathString,
                                                           displayTitle]];
}

- (void)flushPendingSubtitleURLsWithReason:(NSString *)reason
{
    NSArray<NSDictionary<NSString *, id> *> *requests = nil;
    @synchronized (self) {
        self.fileLoaded = YES;
        requests = [self.pendingSubtitleRequests copy];
        [self.pendingSubtitleRequests removeAllObjects];
    }

    if (requests.count == 0)
        return;

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-flush reason=%@ count=%lu",
                                                           reason ?: @"unknown",
                                                           (unsigned long)requests.count]];
    for (NSDictionary<NSString *, id> *request in requests) {
        NSURL *url = [request[@"url"] isKindOfClass:NSURL.class] ? request[@"url"] : nil;
        NSString *title = [request[@"title"] isKindOfClass:NSString.class] ? request[@"title"] : nil;
        [self submitSubtitleURL:url title:title reason:reason ?: @"flush"];
    }
}

- (void)selectAudioTrackID:(NSString *)trackID
{
    if (trackID.length == 0)
        return;

    const char *value = trackID.UTF8String;
    [self setProperty:"aid" format:MPV_FORMAT_STRING value:&value];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-audio-select id=%@", trackID]];
}

- (void)selectSubtitleTrackID:(NSString *)trackID
{
    if (trackID.length == 0)
        return;

    const char *value = trackID.UTF8String;
    [self setProperty:"sid" format:MPV_FORMAT_STRING value:&value];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-select id=%@", trackID]];
}

- (void)disableSubtitle
{
    const char *value = "no";
    [self setProperty:"sid" format:MPV_FORMAT_STRING value:&value];
    [self notifyDiagnosticLine:@"mpv-subtitle-select id=no"];
}

- (void)shutdown
{
    mpv_handle *handle = self.mpv;
    if (!handle)
        return;

    atomic_store(&self->_running, false);
    mpv_wakeup(handle);
    if (dispatch_get_specific(MPVClientBridgeQueueKey) != MPVClientBridgeQueueKey)
        dispatch_sync(self.mpvQueue, ^{});
    self.mpv = NULL;
    self.isInitialized = NO;
    mpv_terminate_destroy(handle);
}

- (BOOL)setOption:(const char *)name format:(mpv_format)format value:(void *)value error:(NSError **)error
{
    int rc = mpv_set_option(self.mpv, name, format, value);
    if (rc >= 0)
        return YES;

    NSString *message = [NSString stringWithFormat:@"mpv_set_option(%s) failed: %s", name, mpv_error_string(rc)];
    [self fillError:error code:rc message:message];
    return NO;
}

- (int)setProperty:(const char *)name format:(mpv_format)format value:(void *)value
{
    if (!self.mpv)
        return MPV_ERROR_UNINITIALIZED;
    return mpv_set_property(self.mpv, name, format, value);
}

- (void)commandAsync:(const char **)command
{
    if (!self.mpv)
        return;

    uint64_t userdata = atomic_fetch_add(&self->_nextCommandUserData, 1);
    int rc = mpv_command_async(self.mpv, userdata, command);
    if (self.diagnosticLoggingEnabled) {
        [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-command-submit userdata=%llu rc=%s argv=%@",
                                                               (unsigned long long)userdata,
                                                               mpv_error_string(rc),
                                                               [self stringFromCommand:command]]];
    }
}

- (void)startEventLoop
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.mpvQueue, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self)
            return;

        while (atomic_load(&self->_running)) {
            mpv_handle *handle = self.mpv;
            if (!handle)
                break;

            mpv_event *event = mpv_wait_event(handle, 0.1);
            [self handleEvent:event];
        }
    });
}

- (void)handleEvent:(mpv_event *)event
{
    if (!event || event->event_id == MPV_EVENT_NONE)
        return;

    switch (event->event_id) {
    case MPV_EVENT_PROPERTY_CHANGE:
        [self handlePropertyChange:(mpv_event_property *)event->data
                              error:event->error
                           userdata:event->reply_userdata];
        break;
    case MPV_EVENT_GET_PROPERTY_REPLY:
        [self handlePropertyReply:(mpv_event_property *)event->data
                             event:event];
        break;
    case MPV_EVENT_SET_PROPERTY_REPLY:
        [self logEvent:event extra:nil];
        break;
    case MPV_EVENT_COMMAND_REPLY:
        [self handleCommandReply:(mpv_event_command *)event->data event:event];
        break;
    case MPV_EVENT_START_FILE:
        [self handleStartFile:(mpv_event_start_file *)event->data event:event];
        break;
    case MPV_EVENT_END_FILE:
        [self handleEndFile:(mpv_event_end_file *)event->data event:event];
        [self notifySubtitleText:nil];
        [self notifyFinish];
        break;
    case MPV_EVENT_FILE_LOADED:
        [self logEvent:event extra:nil];
        [self flushPendingSubtitleURLsWithReason:@"file-loaded"];
        [self applyPendingStartSeekIfNeeded:@"file-loaded"];
        [self logStateSnapshotForReason:@"file-loaded"];
        break;
    case MPV_EVENT_LOG_MESSAGE:
        [self handleLogMessage:(mpv_event_log_message *)event->data];
        break;
    case MPV_EVENT_CLIENT_MESSAGE:
        [self handleClientMessage:(mpv_event_client_message *)event->data event:event];
        break;
    case MPV_EVENT_VIDEO_RECONFIG:
        [self logEvent:event extra:nil];
        [self logStateSnapshotForReason:@"video-reconfig"];
        [self queueVideoRectRefreshAfterDelay:0.0];
        [self queueVideoRectRefreshAfterDelay:0.25];
        break;
    case MPV_EVENT_AUDIO_RECONFIG:
        [self logEvent:event extra:nil];
        [self logStateSnapshotForReason:@"audio-reconfig"];
        break;
    case MPV_EVENT_SEEK:
        [self logEvent:event extra:nil];
        [self logStateSnapshotForReason:[self eventName:event->event_id]];
        break;
    case MPV_EVENT_PLAYBACK_RESTART:
        [self logEvent:event extra:nil];
        [self logStateSnapshotForReason:[self eventName:event->event_id]];
        [self notifyFirstFrame];
        break;
    case MPV_EVENT_QUEUE_OVERFLOW:
        [self logEvent:event extra:@"overflow=true"];
        break;
    case MPV_EVENT_HOOK:
        [self handleHook:(mpv_event_hook *)event->data event:event];
        break;
    case MPV_EVENT_SHUTDOWN:
        [self logEvent:event extra:nil];
        atomic_store(&self->_running, false);
        break;
    default:
        [self logEvent:event extra:nil];
        break;
    }
}

- (void)handlePropertyChange:(mpv_event_property *)property error:(int)error userdata:(uint64_t)userdata
{
    if (!property)
        return;

    const char *name = property->name ?: "";

    if (strcmp(name, "time-pos") == 0 && property->data && property->format == MPV_FORMAT_DOUBLE) {
        self.currentTime = *(double *)property->data;
        [self notifyTime];
        return;
    } else if (strcmp(name, "duration") == 0 && property->data && property->format == MPV_FORMAT_DOUBLE) {
        self.duration = *(double *)property->data;
        [self notifyTime];
    } else if (strcmp(name, "pause") == 0 && property->data && property->format == MPV_FORMAT_FLAG) {
        BOOL paused = *(int *)property->data != 0;
        [self notifyPaused:paused];
    } else if (strcmp(name, "paused-for-cache") == 0 && property->data && property->format == MPV_FORMAT_FLAG) {
        BOOL buffering = *(int *)property->data != 0;
        [self notifyBuffering:buffering];
    } else if (strcmp(name, "osd-dimensions") == 0 && property->data && property->format == MPV_FORMAT_NODE) {
        [self handleOSDDimensions:(mpv_node *)property->data];
    } else if (strcmp(name, "track-list") == 0 && property->data && property->format == MPV_FORMAT_NODE) {
        [self handleTrackList:(mpv_node *)property->data];
    } else if (strcmp(name, "sid") == 0) {
        [self queueSubtitleTrackRefresh];
        if (!property->data || property->format != MPV_FORMAT_STRING) {
            [self notifySubtitleText:nil];
        } else {
            NSString *sid = [self safeStringFromCString:*(char **)property->data];
            if (sid.length == 0 || [sid isEqualToString:@"no"])
                [self notifySubtitleText:nil];
        }
    } else if (strcmp(name, "sub-visibility") == 0) {
        if (property->data && property->format == MPV_FORMAT_FLAG && *(int *)property->data == 0)
            [self notifySubtitleText:nil];
    } else if (strcmp(name, "sub-text") == 0) {
        NSString *text = nil;
        if (property->data && property->format == MPV_FORMAT_STRING)
            text = [self safeStringFromCString:*(char **)property->data];
        [self notifySubtitleText:text.length > 0 ? text : nil];
    } else if ([self isSubtitleDisplayProperty:name]) {
        [self logSubtitleDisplaySnapshotForReason:[self safeStringFromCString:name]];
    }

    if (!self.diagnosticLoggingEnabled)
        return;

    NSString *value = [self stringFromPropertyData:property->data format:property->format];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-property name=%s format=%@ error=%s userdata=%llu value=%@",
                                                           name,
                                                           [self stringFromFormat:property->format],
                                                           mpv_error_string(error),
                                                           (unsigned long long)userdata,
                                                           value]];
}

- (void)notifyFirstFrame
{
    id<MPVClientBridgeDelegate> delegate = self.delegate;
    if (!delegate)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate mpvClientDidRenderFirstFrame];
    });
}

- (void)notifyBuffering:(BOOL)buffering
{
    id<MPVClientBridgeDelegate> delegate = self.delegate;
    if (!delegate)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate mpvClientDidUpdateBuffering:buffering];
    });
}

- (void)applyPendingStartSeekIfNeeded:(NSString *)reason
{
    if (!self.mpv || self.pendingStartSeekIssued || self.pendingStartSeconds <= 0)
        return;

    self.pendingStartSeekIssued = YES;
    NSString *target = [NSString stringWithFormat:@"%.3f", self.pendingStartSeconds];
    const char *cmd[] = {"seek", target.UTF8String, "absolute", NULL};
    [self commandAsync:cmd];
    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-resume-seek reason=%@ seconds=%.3f",
                                                           reason ?: @"unknown",
                                                           self.pendingStartSeconds]];
}

- (void)handlePropertyReply:(mpv_event_property *)property event:(mpv_event *)event
{
    if (!property) {
        [self logEvent:event extra:@"property=<nil>"];
        return;
    }

    const char *name = property->name ?: "";
    NSString *value = [self stringFromPropertyData:property->data format:property->format];
    NSString *extra = [NSString stringWithFormat:@"property=%s format=%@ value=%@",
                                                 name,
                                                 [self stringFromFormat:property->format],
                                                 value];
    [self logEvent:event extra:extra];
}

- (void)handleCommandReply:(mpv_event_command *)command event:(mpv_event *)event
{
    NSString *extra = command ? [NSString stringWithFormat:@"result=%@",
                                                           [self stringFromNode:&command->result depth:0]]
                              : @"result=<nil>";
    [self logEvent:event extra:extra];
}

- (void)handleStartFile:(mpv_event_start_file *)startFile event:(mpv_event *)event
{
    NSString *extra = startFile ? [NSString stringWithFormat:@"playlist_entry_id=%lld",
                                                             (long long)startFile->playlist_entry_id]
                                : @"playlist_entry_id=<nil>";
    [self logEvent:event extra:extra];
    [self logStateSnapshotForReason:@"start-file"];
}

- (void)handleEndFile:(mpv_event_end_file *)endFile event:(mpv_event *)event
{
    NSString *extra = @"end_file=<nil>";
    if (endFile) {
        extra = [NSString stringWithFormat:@"reason=%@ reason_code=%d file_error=%s file_error_code=%d playlist_entry_id=%lld playlist_insert_id=%lld playlist_insert_num_entries=%d",
                                           [self stringFromEndFileReason:endFile->reason],
                                           (int)endFile->reason,
                                           mpv_error_string(endFile->error),
                                           endFile->error,
                                           (long long)endFile->playlist_entry_id,
                                           (long long)endFile->playlist_insert_id,
                                           endFile->playlist_insert_num_entries];
    }
    [self logEvent:event extra:extra];
}

- (void)handleClientMessage:(mpv_event_client_message *)message event:(mpv_event *)event
{
    NSString *extra = @"args=[]";
    if (message) {
        NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(message->num_args, 0)];
        for (int index = 0; index < message->num_args; index++) {
            NSString *arg = [self singleLineString:[self safeStringFromCString:message->args[index]]
                                         maxLength:256];
            [args addObject:arg];
        }
        extra = [NSString stringWithFormat:@"args=[%@]", [args componentsJoinedByString:@", "]];
    }
    [self logEvent:event extra:extra];
}

- (void)handleHook:(mpv_event_hook *)hook event:(mpv_event *)event
{
    NSString *extra = hook ? [NSString stringWithFormat:@"hook=%s hook_id=%llu",
                                                        hook->name ?: "",
                                                        (unsigned long long)hook->id]
                           : @"hook=<nil>";
    [self logEvent:event extra:extra];
}

- (void)logEvent:(mpv_event *)event extra:(NSString *)extra
{
    if (!event || !self.diagnosticLoggingEnabled)
        return;

    NSMutableString *line = [NSMutableString stringWithFormat:@"mpv-event name=%@ id=%d error=%s error_code=%d userdata=%llu",
                                                               [self eventName:event->event_id],
                                                               (int)event->event_id,
                                                               mpv_error_string(event->error),
                                                               event->error,
                                                               (unsigned long long)event->reply_userdata];
    if (extra.length > 0)
        [line appendFormat:@" %@", extra];

    [self notifyDiagnosticLine:line];
}

- (void)logStateSnapshotForReason:(NSString *)reason
{
    if (!self.mpv || !self.subtitleDiagnosticsEnabled)
        return;

    const char *properties[] = {
        "current-vo",
        "current-gpu-context",
        "hwdec-current",
        "hwdec-interop",
        "video-out-params",
        "video-params",
        "audio-out-params",
        "track-list",
        "vo-configured",
    };

    for (size_t index = 0; index < sizeof(properties) / sizeof(properties[0]); index++) {
        mpv_node node = {0};
        int rc = mpv_get_property(self.mpv, properties[index], MPV_FORMAT_NODE, &node);
        if (rc >= 0) {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-snapshot reason=%@ name=%s value=%@",
                                                                   reason,
                                                                   properties[index],
                                                                   [self stringFromNode:&node depth:0]]];
            mpv_free_node_contents(&node);
        } else {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-snapshot reason=%@ name=%s error=%s error_code=%d",
                                                                   reason,
                                                                   properties[index],
                                                                   mpv_error_string(rc),
                                                                   rc]];
        }
    }
}

- (void)logPerformanceSnapshotWithReason:(NSString *)reason
{
    if (!self.mpv || !self.diagnosticLoggingEnabled)
        return;

    NSString *reasonCopy = reason.length > 0 ? reason : @"unknown";

    const char *properties[] = {
        "time-pos",
        "duration",
        "speed",
        "estimated-vf-fps",
        "container-fps",
        "display-fps",
        "frame-drop-count",
        "decoder-frame-drop-count",
        "mistimed-frame-count",
        "vo-delayed-frame-count",
        "avsync",
        "total-avsync-change",
        "demuxer-cache-duration",
        "cache-used",
        "cache-speed",
        "cache-buffering-state",
        "video-bitrate",
        "audio-bitrate",
        "hwdec-current",
        "current-vo",
        "current-gpu-context",
        "vo-configured",
    };

    NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"reason=%@", reasonCopy]];
    for (size_t index = 0; index < sizeof(properties) / sizeof(properties[0]); index++) {
        NSString *value = [self stringProperty:properties[index] defaultValue:@"<none>"];
        [fields addObject:[NSString stringWithFormat:@"%s=%@", properties[index], [self singleLineString:value maxLength:160]]];
    }

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-performance %@", [fields componentsJoinedByString:@" "]]];
}

- (void)handleTrackList:(mpv_node *)node
{
    if (!node || node->format != MPV_FORMAT_NODE_ARRAY || !node->u.list)
        return;

    NSMutableArray<NSDictionary<NSString *, id> *> *tracks = [NSMutableArray array];
    NSString *selectedID = nil;
    mpv_node_list *list = node->u.list;

    for (int index = 0; index < list->num; index++) {
        mpv_node *entry = &list->values[index];
        NSString *type = [self stringValueForKey:"type" inNode:entry];
        if (![type isEqualToString:@"sub"])
            continue;

        NSString *trackID = [self trackIDForNode:entry];
        if (trackID.length == 0)
            continue;

        NSString *title = [self cleanSubtitleTrackTitle:[self stringValueForKey:"title" inNode:entry]];
        NSString *lang = [self stringValueForKey:"lang" inNode:entry];
        NSString *codec = [self stringValueForKey:"codec" inNode:entry];
        BOOL selected = [self flagValueForKey:"selected" inNode:entry defaultValue:NO];
        BOOL external = [self flagValueForKey:"external" inNode:entry defaultValue:NO];

        NSMutableArray<NSString *> *displayParts = [NSMutableArray array];
        if (title.length > 0) {
            [displayParts addObject:title];
        } else if (lang.length > 0) {
            [displayParts addObject:lang.uppercaseString];
        } else {
            [displayParts addObject:[NSString stringWithFormat:@"Subtitle %@", trackID]];
        }

        if (lang.length > 0 && title.length > 0 && ![self subtitleDisplayParts:displayParts containString:lang])
            [displayParts addObject:lang.uppercaseString];
        if (external && ![self subtitleDisplayParts:displayParts containString:@"external"])
            [displayParts addObject:@"External"];
        if (codec.length > 0 && ![self subtitleDisplayParts:displayParts containString:codec])
            [displayParts addObject:codec.uppercaseString];

        NSString *displayTitle = [displayParts componentsJoinedByString:@" · "];

        NSMutableDictionary<NSString *, id> *track = [NSMutableDictionary dictionary];
        track[@"id"] = trackID;
        track[@"title"] = [self singleLineString:displayTitle maxLength:160];
        track[@"selected"] = @(selected);
        track[@"external"] = @(external);
        if (lang.length > 0)
            track[@"lang"] = lang;
        if (codec.length > 0)
            track[@"codec"] = codec;

        [tracks addObject:track];
        if (selected)
            selectedID = trackID;
    }

    if (self.diagnosticLoggingEnabled) {
        NSMutableArray<NSString *> *summary = [NSMutableArray arrayWithCapacity:tracks.count];
        for (NSDictionary<NSString *, id> *track in tracks) {
            [summary addObject:[NSString stringWithFormat:@"%@:%@%@",
                                                          track[@"id"] ?: @"<nil>",
                                                          [track[@"selected"] boolValue] ? @"*" : @"-",
                                                          track[@"title"] ?: @"<untitled>"]];
        }
        [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-subtitle-tracks count=%lu selected=%@ tracks=%@",
                                                               (unsigned long)tracks.count,
                                                               selectedID ?: @"<nil>",
                                                               [summary componentsJoinedByString:@" | "]]];
    }

    [self notifySubtitleTracks:tracks selectedID:selectedID];
}

- (NSString *)cleanSubtitleTrackTitle:(NSString *)title
{
    NSString *trimmed = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0)
        return nil;

    NSString *stem = trimmed.stringByDeletingPathExtension.lowercaseString;
    NSSet<NSString *> *genericNames = [NSSet setWithArray:@[
        @"stream",
        @"subtitle",
        @"subtitles",
        @"external",
        @"external subtitle",
    ]];
    if ([genericNames containsObject:trimmed.lowercaseString] || [genericNames containsObject:stem])
        return nil;

    return trimmed;
}

- (BOOL)subtitleDisplayParts:(NSArray<NSString *> *)parts containString:(NSString *)string
{
    if (string.length == 0)
        return YES;

    NSString *joined = [parts componentsJoinedByString:@" "];
    return [joined rangeOfString:string options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (BOOL)isSubtitleDisplayProperty:(const char *)name
{
    return strcmp(name, "sid") == 0 ||
           strcmp(name, "sub-visibility") == 0 ||
           strcmp(name, "current-tracks/sub") == 0 ||
           strcmp(name, "sub-text") == 0 ||
           strcmp(name, "sub-start") == 0 ||
           strcmp(name, "sub-end") == 0;
}

- (void)logSubtitleDisplaySnapshotForReason:(NSString *)reason
{
    if (!self.mpv || !self.diagnosticLoggingEnabled)
        return;

    NSString *sid = [self stringProperty:"sid" defaultValue:@"<unavailable>"];
    BOOL visible = [self flagProperty:"sub-visibility" defaultValue:NO];
    NSString *text = [self stringProperty:"sub-text" defaultValue:@""];
    NSString *start = [self doubleProperty:"sub-start"];
    NSString *end = [self doubleProperty:"sub-end"];
    NSString *track = [self nodeProperty:"current-tracks/sub"];
    BOOL selected = sid.length > 0 && ![sid isEqualToString:@"no"] && ![sid isEqualToString:@"<unavailable>"];
    BOOL showing = visible && selected && text.length > 0;

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"subtitle-display reason=%@ showing=%@ visible=%@ sid=%@ start=%@ end=%@ text=%@ track=%@",
                                                           reason ?: @"unknown",
                                                           showing ? @"true" : @"false",
                                                           visible ? @"true" : @"false",
                                                           sid,
                                                           start,
                                                           end,
                                                           [self singleLineString:text maxLength:512],
                                                           track]];
}

- (NSString *)stringProperty:(const char *)name defaultValue:(NSString *)defaultValue
{
    char *value = NULL;
    int rc = mpv_get_property(self.mpv, name, MPV_FORMAT_STRING, &value);
    if (rc < 0 || !value)
        return defaultValue;

    NSString *string = [self safeStringFromCString:value];
    mpv_free(value);
    return string ?: defaultValue;
}

- (BOOL)flagProperty:(const char *)name defaultValue:(BOOL)defaultValue
{
    int flag = 0;
    int rc = mpv_get_property(self.mpv, name, MPV_FORMAT_FLAG, &flag);
    if (rc < 0)
        return defaultValue;
    return flag != 0;
}

- (NSString *)doubleProperty:(const char *)name
{
    double value = 0.0;
    int rc = mpv_get_property(self.mpv, name, MPV_FORMAT_DOUBLE, &value);
    if (rc < 0 || !isfinite(value))
        return @"<none>";
    return [NSString stringWithFormat:@"%.3f", value];
}

- (NSString *)nodeProperty:(const char *)name
{
    mpv_node node = {0};
    int rc = mpv_get_property(self.mpv, name, MPV_FORMAT_NODE, &node);
    if (rc < 0)
        return @"<unavailable>";

    NSString *value = [self stringFromNode:&node depth:0];
    mpv_free_node_contents(&node);
    return value;
}

- (NSString *)trackIDForNode:(mpv_node *)node
{
    mpv_node *field = [self nodeMapValueForKey:"id" inNode:node];
    if (!field)
        return nil;

    switch (field->format) {
    case MPV_FORMAT_INT64:
        return [NSString stringWithFormat:@"%lld", (long long)field->u.int64];
    case MPV_FORMAT_STRING:
        return [self safeStringFromCString:field->u.string];
    default:
        return nil;
    }
}

- (NSString *)stringValueForKey:(const char *)key inNode:(mpv_node *)node
{
    mpv_node *field = [self nodeMapValueForKey:key inNode:node];
    if (!field)
        return nil;

    switch (field->format) {
    case MPV_FORMAT_STRING:
        return [self safeStringFromCString:field->u.string];
    case MPV_FORMAT_INT64:
        return [NSString stringWithFormat:@"%lld", (long long)field->u.int64];
    case MPV_FORMAT_DOUBLE:
        return [NSString stringWithFormat:@"%.6f", field->u.double_];
    case MPV_FORMAT_FLAG:
        return field->u.flag ? @"yes" : @"no";
    default:
        return nil;
    }
}

- (BOOL)flagValueForKey:(const char *)key inNode:(mpv_node *)node defaultValue:(BOOL)defaultValue
{
    mpv_node *field = [self nodeMapValueForKey:key inNode:node];
    if (!field)
        return defaultValue;

    switch (field->format) {
    case MPV_FORMAT_FLAG:
        return field->u.flag != 0;
    case MPV_FORMAT_INT64:
        return field->u.int64 != 0;
    case MPV_FORMAT_STRING: {
        const char *value = field->u.string ? field->u.string : "";
        return strcmp(value, "yes") == 0 || strcmp(value, "true") == 0;
    }
    default:
        return defaultValue;
    }
}

- (void)handleOSDDimensions:(mpv_node *)node
{
    double osdWidth = 0;
    double osdHeight = 0;
    double marginLeft = 0;
    double marginRight = 0;
    double marginTop = 0;
    double marginBottom = 0;

    if (![self readDouble:&osdWidth forKey:"w" inNode:node] ||
        ![self readDouble:&osdHeight forKey:"h" inNode:node] ||
        ![self readDouble:&marginLeft forKey:"ml" inNode:node] ||
        ![self readDouble:&marginRight forKey:"mr" inNode:node] ||
        ![self readDouble:&marginTop forKey:"mt" inNode:node] ||
        ![self readDouble:&marginBottom forKey:"mb" inNode:node]) {
        return;
    }

    double width = osdWidth - marginLeft - marginRight;
    double height = osdHeight - marginTop - marginBottom;
    if (osdWidth <= 0 || osdHeight <= 0 || width < 0 || height < 0)
        return;

    [self notifyVideoRectWithX:marginLeft
                             y:marginTop
                         width:width
                        height:height
                      osdWidth:osdWidth
                     osdHeight:osdHeight
                    marginLeft:marginLeft
                   marginRight:marginRight
                     marginTop:marginTop
                  marginBottom:marginBottom];
}

- (BOOL)readDouble:(double *)value forKey:(const char *)key inNode:(mpv_node *)node
{
    mpv_node *field = [self nodeMapValueForKey:key inNode:node];
    if (!field)
        return NO;

    switch (field->format) {
    case MPV_FORMAT_INT64:
        *value = (double)field->u.int64;
        return YES;
    case MPV_FORMAT_DOUBLE:
        *value = field->u.double_;
        return YES;
    case MPV_FORMAT_FLAG:
        *value = field->u.flag ? 1.0 : 0.0;
        return YES;
    default:
        return NO;
    }
}

- (mpv_node *)nodeMapValueForKey:(const char *)key inNode:(mpv_node *)node
{
    if (!node || node->format != MPV_FORMAT_NODE_MAP || !node->u.list)
        return NULL;

    mpv_node_list *list = node->u.list;
    if (list->num <= 0 || !list->values || !list->keys)
        return NULL;

    for (int index = 0; index < list->num; index++) {
        if (list->keys[index] && strcmp(list->keys[index], key) == 0)
            return &list->values[index];
    }

    return NULL;
}

- (NSString *)stringFromCommand:(const char **)command
{
    if (!command)
        return @"[]";

    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (int index = 0; command[index]; index++) {
        NSString *arg = [self singleLineString:[self safeStringFromCString:command[index]]
                                     maxLength:512];
        [items addObject:arg];
    }
    return [NSString stringWithFormat:@"[%@]", [items componentsJoinedByString:@", "]];
}

- (NSString *)stringFromPropertyData:(void *)data format:(mpv_format)format
{
    if (!data || format == MPV_FORMAT_NONE)
        return @"<unavailable>";

    switch (format) {
    case MPV_FORMAT_STRING:
    case MPV_FORMAT_OSD_STRING:
        return [self singleLineString:[self safeStringFromCString:*(char **)data]
                            maxLength:MPVClientBridgeMaxNodeStringLength];
    case MPV_FORMAT_FLAG:
        return *(int *)data ? @"true" : @"false";
    case MPV_FORMAT_INT64:
        return [NSString stringWithFormat:@"%lld", (long long)*(int64_t *)data];
    case MPV_FORMAT_DOUBLE:
        return [NSString stringWithFormat:@"%.6f", *(double *)data];
    case MPV_FORMAT_NODE:
        return [self stringFromNode:(mpv_node *)data depth:0];
    default:
        return [NSString stringWithFormat:@"<unsupported format=%d>", (int)format];
    }
}

- (NSString *)stringFromNode:(mpv_node *)node depth:(NSUInteger)depth
{
    if (!node)
        return @"<nil>";
    if (depth >= MPVClientBridgeMaxNodeDepth)
        return @"<max-depth>";

    switch (node->format) {
    case MPV_FORMAT_NONE:
        return @"nil";
    case MPV_FORMAT_STRING:
        return [self singleLineString:[self safeStringFromCString:node->u.string]
                            maxLength:MPVClientBridgeMaxNodeStringLength];
    case MPV_FORMAT_FLAG:
        return node->u.flag ? @"true" : @"false";
    case MPV_FORMAT_INT64:
        return [NSString stringWithFormat:@"%lld", (long long)node->u.int64];
    case MPV_FORMAT_DOUBLE:
        return [NSString stringWithFormat:@"%.6f", node->u.double_];
    case MPV_FORMAT_NODE_ARRAY:
        return [self stringFromNodeList:node->u.list map:NO depth:depth + 1];
    case MPV_FORMAT_NODE_MAP:
        return [self stringFromNodeList:node->u.list map:YES depth:depth + 1];
    case MPV_FORMAT_BYTE_ARRAY:
        return [NSString stringWithFormat:@"<byte-array size=%zu>", node->u.ba ? node->u.ba->size : 0];
    default:
        return [NSString stringWithFormat:@"<unknown format=%d>", (int)node->format];
    }
}

- (NSString *)stringFromNodeList:(mpv_node_list *)list map:(BOOL)map depth:(NSUInteger)depth
{
    if (!list)
        return map ? @"{}" : @"[]";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    int count = list->num;
    int limit = MIN(count, MPVClientBridgeMaxNodeEntries);
    for (int index = 0; index < limit; index++) {
        NSString *value = [self stringFromNode:&list->values[index] depth:depth];
        if (map) {
            const char *key = list->keys ? list->keys[index] : "";
            [parts addObject:[NSString stringWithFormat:@"%s=%@", key ?: "", value]];
        } else {
            [parts addObject:value];
        }
    }
    if (count > limit)
        [parts addObject:[NSString stringWithFormat:@"... +%d", count - limit]];

    NSString *open = map ? @"{" : @"[";
    NSString *close = map ? @"}" : @"]";
    NSString *joined = [NSString stringWithFormat:@"%@%@%@",
                                                  open,
                                                  [parts componentsJoinedByString:@", "],
                                                  close];
    return [self singleLineString:joined maxLength:MPVClientBridgeMaxNodeStringLength];
}

- (void)queueSubtitleTrackRefresh
{
    if (!self.mpv)
        return;

    dispatch_async(self.mpvQueue, ^{
        mpv_handle *handle = self.mpv;
        if (!handle)
            return;

        mpv_node node = {0};
        int rc = mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node);
        if (rc >= 0) {
            [self handleTrackList:&node];
            mpv_free_node_contents(&node);
        } else if (self.diagnosticLoggingEnabled) {
            [self notifyDiagnosticLine:[NSString stringWithFormat:@"mpv-track-list-refresh error=%s error_code=%d",
                                                                   mpv_error_string(rc),
                                                                   rc]];
        }
    });
}

- (NSString *)safeStringFromCString:(const char *)cString
{
    if (!cString)
        return @"";

    NSString *string = [NSString stringWithUTF8String:cString];
    if (string)
        return string;

    string = [[NSString alloc] initWithBytes:cString
                                      length:strlen(cString)
                                    encoding:NSISOLatin1StringEncoding];
    return string ?: @"<invalid-utf8>";
}

- (NSString *)singleLineString:(NSString *)string maxLength:(NSUInteger)maxLength
{
    if (!string)
        return @"";

    NSMutableString *line = [string mutableCopy];
    [line replaceOccurrencesOfString:@"\r"
                           withString:@"\\r"
                              options:0
                                range:NSMakeRange(0, line.length)];
    [line replaceOccurrencesOfString:@"\n"
                           withString:@"\\n"
                              options:0
                                range:NSMakeRange(0, line.length)];
    [line replaceOccurrencesOfString:@"\t"
                           withString:@"\\t"
                              options:0
                                range:NSMakeRange(0, line.length)];

    if (line.length <= maxLength)
        return line;

    NSString *head = [line substringToIndex:maxLength];
    return [head stringByAppendingString:@"...<truncated>"];
}

- (NSString *)stringFromFormat:(mpv_format)format
{
    switch (format) {
    case MPV_FORMAT_NONE:
        return @"none";
    case MPV_FORMAT_STRING:
        return @"string";
    case MPV_FORMAT_OSD_STRING:
        return @"osd-string";
    case MPV_FORMAT_FLAG:
        return @"flag";
    case MPV_FORMAT_INT64:
        return @"int64";
    case MPV_FORMAT_DOUBLE:
        return @"double";
    case MPV_FORMAT_NODE:
        return @"node";
    case MPV_FORMAT_NODE_ARRAY:
        return @"node-array";
    case MPV_FORMAT_NODE_MAP:
        return @"node-map";
    case MPV_FORMAT_BYTE_ARRAY:
        return @"byte-array";
    default:
        return [NSString stringWithFormat:@"unknown-%d", (int)format];
    }
}

- (NSString *)stringFromEndFileReason:(mpv_end_file_reason)reason
{
    switch (reason) {
    case MPV_END_FILE_REASON_EOF:
        return @"eof";
    case MPV_END_FILE_REASON_STOP:
        return @"stop";
    case MPV_END_FILE_REASON_QUIT:
        return @"quit";
    case MPV_END_FILE_REASON_ERROR:
        return @"error";
    case MPV_END_FILE_REASON_REDIRECT:
        return @"redirect";
    default:
        return @"unknown";
    }
}

- (NSString *)eventName:(mpv_event_id)eventID
{
    const char *name = mpv_event_name(eventID);
    return [self safeStringFromCString:name ?: "unknown"];
}

- (void)handleLogMessage:(mpv_event_log_message *)message
{
    if (!self.rawLogMessagesEnabled || !message || !message->text)
        return;

    NSString *level = [self safeStringFromCString:message->level];
    NSString *prefix = [self safeStringFromCString:message->prefix];
    NSString *text = [self safeStringFromCString:message->text];
    text = [self singleLineString:[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                         maxLength:MPVClientBridgeMaxDiagnosticLength];
    if (text.length == 0)
        return;

    [self notifyDiagnosticLine:[NSString stringWithFormat:@"libmpv level=%@ log_level=%d prefix=%@ text=%@",
                                                           level,
                                                           (int)message->log_level,
                                                           prefix,
                                                           text]];
}

- (void)notifyDiagnosticLine:(NSString *)line
{
    if (!self.diagnosticLoggingEnabled || line.length == 0)
        return;

    NSString *bounded = [self singleLineString:line maxLength:MPVClientBridgeMaxDiagnosticLength];
    [self.delegate mpvClientDidLog:bounded];
}

- (BOOL)environmentFlagEnabled:(const char *)name
{
    const char *value = getenv(name);
    if (!value || value[0] == '\0')
        return NO;

    return strcmp(value, "0") != 0;
}

- (void)notifySubtitleTracks:(NSArray<NSDictionary<NSString *, id> *> *)tracks selectedID:(NSString *)selectedID
{
    NSArray<NSDictionary<NSString *, id> *> *tracksCopy = [tracks copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidUpdateSubtitleTracks:tracksCopy selectedID:selectedID];
    });
}

- (void)notifySubtitleText:(NSString *)text
{
    NSString *textCopy = [text copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidUpdateSubtitleText:textCopy];
    });
}

- (void)notifyTime
{
    double time = self.currentTime;
    double duration = self.duration;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidUpdateTime:time duration:duration];
    });
}

- (void)notifyPaused:(BOOL)paused
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidUpdatePaused:paused];
    });
}

- (void)notifyVideoRectWithX:(double)x
                           y:(double)y
                       width:(double)width
                      height:(double)height
                    osdWidth:(double)osdWidth
                   osdHeight:(double)osdHeight
                  marginLeft:(double)marginLeft
                 marginRight:(double)marginRight
                   marginTop:(double)marginTop
                marginBottom:(double)marginBottom
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidUpdateVideoRectWithX:x
                                                      y:y
                                                  width:width
                                                 height:height
                                               osdWidth:osdWidth
                                              osdHeight:osdHeight
                                             marginLeft:marginLeft
                                            marginRight:marginRight
                                              marginTop:marginTop
                                           marginBottom:marginBottom];
    });
}

- (void)notifyFinish
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidFinishPlayback];
    });
}

- (void)fillError:(NSError **)error code:(NSInteger)code message:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate mpvClientDidFailWithMessage:message];
    });

    if (!error)
        return;

    *error = [NSError errorWithDomain:@"LibMPVPlayer.MPVClientBridge"
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
