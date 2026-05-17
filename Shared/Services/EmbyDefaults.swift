//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Foundation
import SwiftUI
import UIKit

enum MediaTrackLanguagePreference: String, CaseIterable, Displayable, Storable {
    case automatic
    case chinese
    case japanese
    case english
    case korean
    case cantonese

    var displayTitle: String {
        switch self {
        case .automatic:
            return "自动"
        case .chinese:
            return "中文"
        case .japanese:
            return "日语"
        case .english:
            return "英语"
        case .korean:
            return "韩语"
        case .cantonese:
            return "粤语"
        }
    }

    var mpvLanguageList: String? {
        guard self != .automatic else { return nil }
        return orderedLanguageCodes.joined(separator: ",")
    }

    static var automaticAudioMPVLanguageList: String {
        orderedLanguageCodes(for: automaticAudioPreferences).joined(separator: ",")
    }

    static var automaticSubtitleMPVLanguageList: String {
        orderedLanguageCodes(for: automaticSubtitlePreferences).joined(separator: ",")
    }

    static func automaticAudioStream(in streams: [MediaStream]) -> MediaStream? {
        preferredStream(in: streams, preferences: automaticAudioPreferences)
    }

    static func automaticSubtitleStream(in streams: [MediaStream]) -> MediaStream? {
        preferredStream(in: streams, preferences: automaticSubtitlePreferences)
    }

    func preferredStream(in streams: [MediaStream]) -> MediaStream? {
        guard self != .automatic else { return nil }

        return Self.preferredStream(in: streams, preferences: [self])
    }

    private static func preferredStream(
        in streams: [MediaStream],
        preferences: [MediaTrackLanguagePreference]
    ) -> MediaStream? {
        for preference in preferences {
            guard let stream = preference.preferredStreamIncludingAutomatic(in: streams) else {
                continue
            }
            return stream
        }

        return nil
    }

    private func preferredStreamIncludingAutomatic(in streams: [MediaStream]) -> MediaStream? {
        let matchingStreams = streams.filter { stream in
            self.matches(stream)
        }
        if let stream = matchingStreams.first(where: { $0.isForced != true && $0.isHearingImpaired != true }) {
            return stream
        }
        if let stream = matchingStreams.first(where: { $0.isForced != true }) {
            return stream
        }
        return matchingStreams.first
    }

    private static var automaticAudioPreferences: [MediaTrackLanguagePreference] {
        [.japanese, .chinese, .cantonese, .korean, .english]
    }

    private static var automaticSubtitlePreferences: [MediaTrackLanguagePreference] {
        [.chinese, .cantonese, .english]
    }

    private static func orderedLanguageCodes(for preferences: [MediaTrackLanguagePreference]) -> [String] {
        var seen: Set<String> = []
        return preferences.flatMap(\.orderedLanguageCodes).filter { seen.insert($0).inserted }
    }

    func matches(_ stream: MediaStream) -> Bool {
        [stream.language, stream.displayTitle, stream.title]
            .compactMap(\.self)
            .contains { matches($0) }
    }

    private func matches(_ value: String) -> Bool {
        let normalized = Self.normalizedLanguageValue(value)
        if languageCodeSet.contains(normalized) {
            return true
        }

        let tokens = Self.languageTokens(in: value)
        if !tokens.isDisjoint(with: languageCodeSet) {
            return true
        }

        let searchText = Self.normalizedSearchText(value)
        return languageKeywords.contains { searchText.contains($0) }
    }

    private var languageCodeSet: Set<String> {
        Set(orderedLanguageCodes)
    }

    private var orderedLanguageCodes: [String] {
        switch self {
        case .automatic:
            return []
        case .chinese:
            return ["zh", "zho", "chi", "chs", "cht", "sc", "tc", "zh-cn", "zh-hans", "zh-tw", "zh-hant", "cmn"]
        case .japanese:
            return ["ja", "jp", "jpn"]
        case .english:
            return ["en", "eng"]
        case .korean:
            return ["ko", "kor"]
        case .cantonese:
            return ["yue", "zh-yue"]
        }
    }

    private var languageKeywords: [String] {
        switch self {
        case .automatic:
            return []
        case .chinese:
            return [
                "中文",
                "简体中文", "簡體中文", "简体", "簡體", "简中", "簡中",
                "繁体中文", "繁體中文", "繁体", "繁體", "繁中", "正体中文", "正體中文",
                "chinese", "mandarin", "simplified chinese", "traditional chinese", "big5",
            ]
        case .japanese:
            return ["日语", "日本語", "japanese"]
        case .english:
            return ["英语", "english"]
        case .korean:
            return ["韩语", "한국어", "korean"]
        case .cantonese:
            return ["粤语", "广东话", "cantonese"]
        }
    }

    private static func normalizedLanguageValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func languageTokens(in value: String) -> Set<String> {
        let normalized = normalizedLanguageValue(value)
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted
        return Set(
            normalized
                .components(separatedBy: separators)
                .filter(\.isNotEmpty)
        )
    }
}

enum MediaTrackDefaults {

    static func preferredAudioStreamIndex(in mediaSource: MediaSourceInfo?) -> Int? {
        guard let mediaSource else { return nil }
        let preference = Defaults[.VideoPlayer.Playback.defaultAudioLanguage]
        let streams = mediaSource.audioStreams ?? []
        if let stream = preference.preferredStream(in: streams) ??
            (preference == .automatic ? MediaTrackLanguagePreference.automaticAudioStream(in: streams) : nil) {
            return stream.index
        }

        return nil
    }

    static func preferredSubtitleStreamIndex(in mediaSource: MediaSourceInfo?) -> Int? {
        guard let mediaSource else { return nil }
        let preference = Defaults[.VideoPlayer.Subtitle.defaultSubtitleLanguage]
        let streams = mediaSource.subtitleStreams ?? []
        if let stream = preference.preferredStream(in: streams) ??
            (preference == .automatic ? MediaTrackLanguagePreference.automaticSubtitleStream(in: streams) : nil) {
            return stream.index
        }

        return nil
    }

    static func selectedAudioStreamIndex(in mediaSource: MediaSourceInfo?) -> Int? {
        guard let mediaSource else { return nil }
        return preferredAudioStreamIndex(in: mediaSource) ??
            mediaSource.defaultAudioStreamIndex ??
            mediaSource.audioStreams?.first?.index
    }

    static func selectedSubtitleStreamIndex(in mediaSource: MediaSourceInfo?) -> Int? {
        guard let mediaSource else { return nil }
        return preferredSubtitleStreamIndex(in: mediaSource) ??
            mediaSource.defaultSubtitleStreamIndex ??
            -1
    }
}

// TODO: organize
// TODO: all user settings could be moved to `StoredValues`?

// Note: Only use Defaults for basic single-value settings.
//       For larger data types and collections, use `StoredValue` instead.

// MARK: Suites

extension UserDefaults {

    // MARK: App

    /// Settings that should apply to the app
    static let appSuite = UserDefaults(suiteName: "embyApp")!

    // MARK: User

    static var currentUserSuite: UserDefaults {
        switch Defaults[.lastSignedInUserID] {
        case .signedOut:
            userSuite(id: "default")
        case let .signedIn(userID):
            userSuite(id: userID)
        }
    }

    static func userSuite(id: String) -> UserDefaults {
        UserDefaults(suiteName: id)!
    }
}

private extension Defaults.Keys {

    static func AppKey<Value: Defaults.Serializable>(_ name: String) -> Key<Value?> {
        Key(name, suite: .appSuite)
    }

    static func AppKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .appSuite)
    }

    static func UserKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .currentUserSuite)
    }
}

// MARK: App

extension Defaults.Keys {

    /// The _real_ accent color key to be used.
    ///
    /// This is set externally whenever the app or user accent colors change,
    /// depending on the current app state.
    static var accentColor: Key<Color> = AppKey("accentColor", default: .embyPurple)

    /// The _real_ appearance key to be used.
    ///
    /// This is set externally whenever the app or user appearances change,
    /// depending on the current app state.
    static let appearance: Key<AppAppearance> = AppKey("appearance", default: .dark)

    /// The appearance default for non-user contexts.
    /// /// Only use for `set`, use `appearance` for `get`.
    static let appAppearance: Key<AppAppearance> = AppKey("appAppearance", default: .dark)

    static let backgroundSignOutInterval: Key<TimeInterval> = AppKey("backgroundSignOutInterval", default: 3600)
    static let backgroundTimeStamp: Key<Date> = AppKey("backgroundTimeStamp", default: Date.now)
    static let lastSignedInUserID: Key<UserSignInState> = AppKey("lastSignedInUserID", default: .signedOut)

    static let selectUserDisplayType: Key<LibraryDisplayType> = AppKey("selectUserDisplayType", default: .grid)
    static let selectUserServerSelection: Key<SelectUserServerSelection> = AppKey("selectUserServerSelection", default: .all)
    static let selectUserAllServersSplashscreen: Key<SelectUserServerSelection> = AppKey("selectUserAllServersSplashscreen", default: .all)
    static let selectUserUseSplashscreen: Key<Bool> = AppKey("selectUserUseSplashscreen", default: true)

    static let signOutOnBackground: Key<Bool> = AppKey("signOutOnBackground", default: true)
    static let signOutOnClose: Key<Bool> = AppKey("signOutOnClose", default: false)

    static func migrateSubtitleAdjustmentSettingsToAppSuiteIfNeeded() {
        let positionKey = "subtitlePosition"
        let scaleKey = "subtitleScale"
        let borderSizeKey = "subtitleBorderSize"
        let userSuite = UserDefaults.currentUserSuite
        let appSuite = UserDefaults.appSuite

        if appSuite.object(forKey: positionKey) == nil,
           let legacyPosition = userSuite.object(forKey: positionKey) as? Double
        {
            appSuite.set(legacyPosition, forKey: positionKey)
        }

        if appSuite.object(forKey: scaleKey) == nil,
           let legacyScale = userSuite.object(forKey: scaleKey) as? Double
        {
            appSuite.set(legacyScale, forKey: scaleKey)
        }

        if appSuite.object(forKey: borderSizeKey) == nil,
           let legacyBorderSize = userSuite.object(forKey: borderSizeKey) as? Double
        {
            appSuite.set(legacyBorderSize, forKey: borderSizeKey)
        }
    }
}

// MARK: User

extension Defaults.Keys {

    /// The accent color default for user contexts.
    /// Only use for `set`, use `accentColor` for `get`.
    static var userAccentColor: Key<Color> {
        UserKey("userAccentColor", default: .embyPurple)
    }

    /// The appearance default for user contexts.
    /// /// Only use for `set`, use `appearance` for `get`.
    static var userAppearance: Key<AppAppearance> {
        UserKey("userAppearance", default: .dark)
    }

    enum Customization {

        static var itemViewType: Key<ItemViewType> {
            UserKey("itemViewType", default: .compactLogo)
        }

        static var showPosterLabels: Key<Bool> {
            UserKey("showPosterLabels", default: true)
        }

        static var nextUpPosterType: Key<PosterDisplayType> {
            UserKey("nextUpPosterType", default: .portrait)
        }

        static var recentlyAddedPosterType: Key<PosterDisplayType> {
            UserKey("recentlyAddedPosterType", default: .portrait)
        }

        static var latestInLibraryPosterType: Key<PosterDisplayType> {
            UserKey("latestInLibraryPosterType", default: .portrait)
        }

        static var shouldShowMissingSeasons: Key<Bool> {
            UserKey("shouldShowMissingSeasons", default: true)
        }

        static var shouldShowMissingEpisodes: Key<Bool> {
            UserKey("shouldShowMissingEpisodes", default: true)
        }

        static var similarPosterType: Key<PosterDisplayType> {
            UserKey("similarPosterType", default: .portrait)
        }

        // TODO: have search poster type by types of items if applicable
        static var searchPosterType: Key<PosterDisplayType> {
            UserKey("searchPosterType", default: .portrait)
        }

        enum CinematicItemViewType {

            static var usePrimaryImage: Key<Bool> {
                UserKey("cinematicItemViewTypeUsePrimaryImage", default: false)
            }
        }

        enum Episodes {

            static var useSeriesLandscapeBackdrop: Key<Bool> {
                UserKey("useSeriesBackdrop", default: true)
            }
        }

        enum Indicators {

            static var showFavorited: Key<Bool> {
                UserKey("showFavoritedIndicator", default: true)
            }

            static var showProgress: Key<Bool> {
                UserKey("showProgressIndicator", default: true)
            }

            static var showUnplayed: Key<UnplayedIndicatorType> {
                UserKey("showUnplayedIndicator", default: .indicator)
            }

            static var showPlayed: Key<Bool> {
                UserKey("showPlayedIndicator", default: true)
            }
        }

        enum Library {

            static var cinematicBackground: Key<Bool> {
                UserKey("libraryCinematicBackground", default: true)
            }

            static var enabledDrawerFilters: Key<[ItemFilterType]> {
                UserKey(
                    "libraryEnabledDrawerFilters",
                    default: ItemFilterType.allCases
                )
            }

            static var letterPickerOrientation: Key<LetterPickerOrientation> {
                UserKey("letterPickerOrientation", default: .disabled)
            }

            static var displayType: Key<LibraryDisplayType> {
                UserKey("libraryViewType", default: .grid)
            }

            static var posterType: Key<PosterDisplayType> {
                UserKey("libraryPosterType", default: .portrait)
            }

            static var listColumnCount: Key<Int> {
                UserKey("listColumnCount", default: 1)
            }

            static var randomImage: Key<Bool> {
                UserKey("libraryRandomImage", default: true)
            }

            static var showFavorites: Key<Bool> {
                UserKey("libraryShowFavorites", default: true)
            }

            static var rememberLayout: Key<Bool> {
                UserKey("libraryRememberLayout", default: false)
            }

            static var rememberSort: Key<Bool> {
                UserKey("libraryRememberSort", default: false)
            }
        }

        enum Home {
            static var sectionOrder: Key<[String]> {
                UserKey("homeSectionOrder", default: [])
            }

            static var hiddenSectionIDs: Key<[String]> {
                UserKey("homeHiddenSectionIDs", default: [])
            }

            static var showRecentlyAdded: Key<Bool> {
                UserKey("showRecentlyAdded", default: true)
            }

            static var resumeNextUp: Key<Bool> {
                UserKey("homeResumeNextUp", default: false)
            }

            static var maxNextUp: Key<TimeInterval> {
                UserKey(
                    "homeMaxNextUp",
                    default: 366 * 86400
                )
            }
        }

        enum Search {

            static var enabledDrawerFilters: Key<[ItemFilterType]> {
                UserKey(
                    "searchEnabledDrawerFilters",
                    default: ItemFilterType.allCases
                )
            }
        }
    }

    enum VideoPlayer {

        static var appMaximumBitrate: Key<PlaybackBitrate> {
            UserKey("appMaximumBitrate", default: .max)
        }

        static var appMaximumBitrateTest: Key<PlaybackBitrateTestSize> {
            UserKey("appMaximumBitrateTest", default: .regular)
        }

        static var autoPlayEnabled: Key<Bool> {
            UserKey("autoPlayEnabled", default: true)
        }

        static var barActionButtons: Key<[VideoPlayerActionButton]> {
            UserKey(
                "barActionButtons",
                default: VideoPlayerActionButton.defaultBarActionButtons
            )
        }

        static var jumpBackwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpBackwardLength", default: .fifteen)
        }

        static var jumpForwardInterval: Key<MediaJumpInterval> {
            UserKey("jumpForwardLength", default: .fifteen)
        }

        static var menuActionButtons: Key<[VideoPlayerActionButton]> {
            UserKey(
                "menuActionButtons",
                default: VideoPlayerActionButton.defaultMenuActionButtons
            )
        }

        static var resumeOffset: Key<Int> {
            UserKey("resumeOffset", default: 0)
        }

        static var supplements: Key<[VideoPlayerSupplement]> {
            UserKey(
                "videoPlayerSupplements",
                default: VideoPlayerSupplement.supportedCases
            )
        }

        static var videoPlayerType: Key<VideoPlayerType> {
            UserKey("videoPlayerType", default: .emby)
        }

        enum Gesture {

            static var horizontalPanAction: Key<PanGestureAction> {
                UserKey("videoPlayerHorizontalPanGesture", default: .none)
            }

            static var horizontalSwipeAction: Key<SwipeGestureAction> {
                UserKey("videoPlayerhorizontalSwipeAction", default: .none)
            }

            static var longPressAction: Key<LongPressGestureAction> {
                UserKey("videoPlayerLongPressGesture", default: .gestureLock)
            }

            static var longPressSpeedMultiplier: Key<PlaybackSpeed> {
                UserKey(
                    "videoPlayerLongPressSpeedMultiplier",
                    default: .two
                )
            }

            static var multiTapGesture: Key<MultiTapGestureAction> {
                UserKey("videoPlayerMultiTapGesture", default: .none)
            }

            static var doubleTouchGesture: Key<DoubleTouchGestureAction> {
                UserKey("videoPlayerDoubleTouchGesture", default: .none)
            }

            static var pinchGesture: Key<PinchGestureAction> {
                UserKey("videoPlayerSwipeGesture", default: .aspectFill)
            }

            static var verticalPanLeftAction: Key<PanGestureAction> {
                UserKey("videoPlayerverticalPanLeftAction", default: .none)
            }

            static var verticalPanRightAction: Key<PanGestureAction> {
                UserKey("videoPlayerverticalPanRightAction", default: .none)
            }
        }

        enum Overlay {

            static var chapterSlider: Key<Bool> {
                UserKey("chapterSlider", default: true)
            }

            // Timestamp
            static var trailingTimestampType: Key<TrailingTimestampType> {
                UserKey("trailingTimestamp", default: .timeLeft)
            }
        }

        enum Playback {
            static var appMaximumBitrate: Key<PlaybackBitrate> {
                UserKey("appMaximumBitrate", default: .auto)
            }

            static var appMaximumBitrateTest: Key<PlaybackBitrateTestSize> {
                UserKey("appMaximumBitrateTest", default: .regular)
            }

            static var compatibilityMode: Key<PlaybackCompatibility> {
                UserKey("compatibilityMode", default: .auto)
            }

            static var customDeviceProfileAction: Key<CustomDeviceProfileAction> {
                UserKey("customDeviceProfileAction", default: .add)
            }

            static var rates: Key<[Float]> {
                UserKey("videoPlayerPlaybackRates", default: [0.5, 1.0, 1.25, 1.5, 2.0])
            }

            static var playbackRate: Key<Float> {
                UserKey("playbackRate", default: Float(1.0))
            }

            static var defaultAudioLanguage: Key<MediaTrackLanguagePreference> {
                UserKey("defaultAudioTrackLanguage", default: .automatic)
            }
        }

        // TODO: transition into a SubtitleConfiguration instead of multiple types
        enum Subtitle {

            static var subtitleColor: Key<Color> {
                UserKey("subtitleColor", default: .white)
            }

            static var subtitleFontName: Key<String> {
                UserKey("subtitleFontName", default: UIFont.systemFont(ofSize: 14).fontName)
            }

            static var subtitleSize: Key<Int> {
                UserKey("subtitleSize", default: 9)
            }

            static var subtitlePosition: Key<Double> {
                AppKey("subtitlePosition", default: 100)
            }

            static var subtitleScale: Key<Double> {
                AppKey("subtitleScale", default: 1)
            }

            static var subtitleBorderSize: Key<Double> {
                AppKey("subtitleBorderSize", default: 3)
            }

            static var convertTraditionalChineseSubtitles: Key<Bool> {
                AppKey("convertTraditionalChineseSubtitles", default: false)
            }

            static var defaultSubtitleLanguage: Key<MediaTrackLanguagePreference> {
                UserKey("defaultSubtitleTrackLanguage", default: .automatic)
            }
        }

        enum Transition {
            static var pauseOnBackground: Key<Bool> {
                UserKey("playInBackground", default: true)
            }
        }
    }

    // Experimental settings
    enum Experimental {

        static var downloads: Key<Bool> {
            UserKey("experimentalDownloads", default: false)
        }
    }

    // tvos specific
    static var downActionShowsMenu: Key<Bool> {
        UserKey("downActionShowsMenu", default: true)
    }

    static var confirmClose: Key<Bool> {
        UserKey("confirmClose", default: false)
    }
}

// MARK: Debug

#if DEBUG

extension UserDefaults {

    static let debugSuite = UserDefaults(suiteName: "embystore-debug-defaults")!
}

extension Defaults.Keys {

    static func DebugKey<Value: Defaults.Serializable>(_ name: String, default: Value) -> Key<Value> {
        Key(name, default: `default`, suite: .appSuite)
    }

    static let isLiquidGlassEnabled: Key<Bool> = DebugKey("experimentalLiquidGlass", default: false)
    static let sendProgressReports: Key<Bool> = DebugKey("sendProgressReports", default: true)
}
#endif
