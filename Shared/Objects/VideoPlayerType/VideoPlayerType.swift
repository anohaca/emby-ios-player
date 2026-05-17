//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// TODO: remove after the libmpv-backed player is the only runtime path.

enum VideoPlayerType: String, CaseIterable, Displayable, Storable {

    case native
    case emby

    var displayTitle: String {
        switch self {
        case .native:
            L10n.native
        case .emby:
            "Emby"
        }
    }

    var directPlayProfiles: [DirectPlayProfile] {
        switch self {
        case .native:
            Self._nativeDirectPlayProfiles
        case .emby:
            Self._embyDirectPlayProfiles
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        case .native:
            Self._nativeTranscodingProfiles
        case .emby:
            Self._embyTranscodingProfiles
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        case .native:
            Self._nativeSubtitleProfiles
        case .emby:
            Self._embySubtitleProfiles
        }
    }
}
