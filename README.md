# Emby iOS Player

[简体中文](README.zh-CN.md)

An unofficial Emby-compatible iOS client focused on a native SwiftUI interface
and a libmpv-backed playback experience.

This project is a community port derived from Swiftfin UI and navigation code,
with the server boundary adapted for Emby APIs and the iOS playback path wired
to a local libmpv integration. It is not affiliated with or endorsed by Emby,
Jellyfin, or Swiftfin.

## Status

This repository is under active development. The iOS app can authenticate
against an Emby server, browse libraries, search items, show item details,
continue playback, report playback progress, and play media through the local
libmpv path.

Current focus areas:

- Emby authentication, session storage, public users, server info, and branding.
- Home, libraries, favorites, search, item details, seasons, episodes, and
  continue-watching flows.
- libmpv video playback with custom iOS controls, subtitles, audio/subtitle
  track selection, resume, seek, speed, brightness, volume, and episode
  navigation.
- Playback reporting back to Emby.
- iPhone-first UI behavior, including landscape playback.

## Repository Layout

- `Emby/` - app-specific views, app entry points, libmpv bridge, and player UI.
- `Shared/` - shared models, coordinators, view models, Emby API layer, and
  reusable UI.
- `Translations/` - localized strings.
- `Documentation/` - porting notes, player notes, and contributor guidance.
- `PreferencesView/` - local Swift package used by the app.
- `XcodeConfig/` - Xcode configuration files. Local signing settings are ignored.

## Prerequisites

- macOS with a recent Xcode version.
- iOS SDK matching your local Xcode installation.
- Homebrew, if you want the optional formatting and linting tools.
- A valid Apple developer team for physical device installation.
- A locally built libmpv iOS dependency bundle.

The Xcode project currently expects the libmpv artifact at:

```text
../../build/Libmpv.xcframework
```

That path is intentionally not committed. Build or place your own
`Libmpv.xcframework` there, or adjust the Xcode header and linker search paths
for your environment.

## Setup

Install optional developer tools:

```bash
brew bundle
```

Open the project:

```bash
open Emby.xcodeproj
```

Build for simulator without signing:

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Build for a physical device with your own signing settings:

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_STYLE=Automatic
```

For local device installation, use Xcode or `xcrun devicectl` after building a
signed app.

## libmpv Notes

The player code is designed around a local libmpv bridge. Format support and
hardware decoding behavior depend on the libmpv, FFmpeg, MoltenVK, and related
native libraries you build.

The repository does not vendor those native build products. Keep large binary
artifacts out of git and document any local changes needed to reproduce your
build.

## Privacy and Secrets

Do not commit:

- Emby server URLs that are private to your network.
- Usernames, passwords, API keys, access tokens, or session tokens.
- Apple development team configuration.
- Provisioning profiles, signing certificates, device IDs, or generated IPAs.
- Local media paths or screenshots containing personal library data.

Local signing overrides should go in ignored local config files such as
`XcodeConfig/DevelopmentTeam.xcconfig`.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[Documentation/contributing.md](Documentation/contributing.md).

Before opening a pull request:

- Keep MPL-2.0 headers and upstream attribution intact.
- Route new server calls through the Emby request layer.
- Keep playback changes tested on a real iPhone when practical.
- Run a local Xcode build for the affected target.
- Avoid committing generated build output or personal data.

## Attribution

This project includes code derived from Swiftfin. Copied files keep their
original MPL-2.0 headers where applicable. See [NOTICE.md](NOTICE.md) for
upstream attribution details.

Emby, Jellyfin, Swiftfin, libmpv, FFmpeg, MoltenVK, and other names belong to
their respective owners.

## License

This repository is licensed under the Mozilla Public License 2.0. See
[LICENSE.md](LICENSE.md).
