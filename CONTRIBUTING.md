# Contributing

Thanks for helping improve this unofficial Emby iOS player.

## Ground Rules

- Preserve MPL-2.0 license headers and upstream attribution.
- Keep product-specific server calls behind the Emby request layer.
- Keep playback UI behavior coordinated through `MediaPlayerManager`.
- Do not commit personal Emby server URLs, tokens, credentials, signing files,
  device identifiers, screenshots with private libraries, or local media paths.
- Do not commit large generated build artifacts such as `DerivedData`, IPAs,
  dSYMs, native static libraries, or `xcframework` outputs.

## Development Setup

Install optional tools:

```bash
brew bundle
```

Open the project:

```bash
open Emby.xcodeproj
```

The project expects a local libmpv iOS build at:

```text
../../build/Libmpv.xcframework
```

Use your own local build of libmpv and related native dependencies. Do not
commit those generated artifacts.

## Build Checks

Simulator build:

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Device build requires your own signing:

```bash
xcodebuild build \
  -project Emby.xcodeproj \
  -scheme Emby \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID> \
  CODE_SIGN_STYLE=Automatic
```

SwiftFormat and SwiftLint are optional local tools. The Xcode scripts may print
messages if they are not installed.

## Playback Changes

For playback work, test more than one file when possible:

- H.264 and HEVC video.
- At least one MKV and one MP4.
- Internal subtitles and external SRT/ASS subtitles.
- Audio/subtitle track switching.
- Pause, seek, resume, next/previous episode, and app backgrounding.
- Physical iPhone behavior for orientation and thermal/performance changes.

Document any device-only behavior in the pull request.

## Pull Request Checklist

- The change is scoped and avoids unrelated formatting churn.
- The app builds locally.
- User-facing text is localized or deliberately left as technical/debug text.
- No secrets or personal data are included.
- License notices are preserved.
- New behavior is described in the PR summary.

## More Notes

Additional porting details live in [Documentation/contributing.md](Documentation/contributing.md)
and [EMBY_PORT.md](EMBY_PORT.md).
