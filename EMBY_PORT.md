# Emby Port

This directory is the full working-copy port area. The unchanged upstream
reference remains at `../References/Swiftfin`; provenance is recorded in
`../NOTICE.md`.

Copied source files keep their original MPL-2.0 headers. Modified files in this
port directory remain MPL-2.0 at file level.

## Porting Direction

The port keeps the mature SwiftUI app, navigation, player controls, settings,
poster shelves, item pages, queue UI, gestures, and reporting structure while
replacing product-specific boundaries:

1. Route server calls through the Emby request layer.
2. Use the local libmpv-backed player path for the default video experience.
3. Keep account and session storage compatible with Emby authentication.
4. Preserve reusable SwiftUI components unless they depend on unsupported server
   behavior.
5. Preserve license notices in copied or modified source files.

## Boundary Replacement Targets

Primary network boundaries:

- `Shared/ViewModels/ConnectToServerViewModel.swift`
- `Shared/ViewModels/UserSignInViewModel.swift`
- `Shared/Services/UserSession.swift`
- `Shared/Extensions/EmbyAPI`
- `Shared/ViewModels/HomeViewModel.swift`
- `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem+Build.swift`
- `Shared/Objects/MediaPlayerManager/MediaProgressObserver.swift`

Primary playback boundaries:

- `Shared/Components/VideoPlayer.swift`
- `Shared/Objects/MediaPlayerManager/MediaPlayerProxy/MediaPlayerProxy.swift`
- `Emby/Objects/LibMPV`
- `Emby/Views/VideoPlayerContainerView`

## Current Local Emby Replacements

The SPM package one level up contains reusable replacement pieces:

- `../EmbyCore/Sources/API/HTTP/EmbyAuthenticationClient.swift`
- `../EmbyCore/Sources/API/HTTP/EmbyHTTPClient.swift`
- `../PlayerCore/Sources/Playback/LibMPVPlayerEngine.swift`
- `../PlayerCore/Sources/Bridge/LibMPVBridgeProtocol.swift`

The full-copy port also has an in-tree compatibility layer:

- `Shared/Emby/EmbyPortAPI.swift`
  - public server info
  - username/password login
  - public users
  - branding configuration
  - authenticated request helpers
  - image URL helpers
  - video stream URL helpers
  - playback info and progress reporting
  - browse, admin, metadata, task, device, activity, and log endpoints

First replaced call sites:

- `Shared/ViewModels/ConnectToServerViewModel.swift` discovers Emby servers
  through `EmbyPortAuthenticationClient`.
- `Shared/ViewModels/UserSignInViewModel.swift` signs in through Emby username
  and password authentication.
- `Shared/EmbyStore/EmbyStore+ServerState.swift` refreshes public server
  info through the Emby client.
- `Shared/Services/UserSession.swift` exposes `embyClient` for authenticated
  follow-up work.
- `Shared/Emby/EmbyPortPlayback.swift` defines the playback request and engine
  boundary used by the player manager.
- `Shared/ViewModels/HomeViewModel.swift` loads resume items, library views,
  current-user excluded libraries, and played/unplayed state through
  `UserSession.embyClient`.
- `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem+Build.swift`
  requests playback information and stream URLs through the Emby client.
- `Shared/Objects/MediaPlayerManager/MediaProgressObserver.swift` reports
  playback start, progress, and stop through Emby session endpoints.
- `Shared/Extensions/EmbyAPI/BaseItemDto/BaseItemDto+Images.swift` creates item
  image URLs through `UserSession.embyClient`.
- `Shared/Objects/MediaPlayerManager/MediaPlayerItem/MediaPlayerItem.swift`
  carries HTTP headers so libmpv can load authenticated Emby streams.
- `Shared/Emby/EmbyPortLocalizationModels.swift` and
  `Shared/Emby/EmbyPortAdminModels.swift` provide generated-package-free Emby
  models for localization lists, API keys, server logs, devices, activity logs,
  scheduled tasks, and triggers.
