# Contributing

This directory is a working Emby port. Keep upstream reference material in
`../References/Swiftfin` unchanged and make product changes inside
`EmbyPort` or the adjacent Emby packages.

## Setup

Use Xcode for the app target and SwiftPM for the local support packages.

```bash
swift test
xcodebuild build -project EmbyPort/Emby.xcodeproj -scheme Emby -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project EmbyPort/Emby.xcodeproj -scheme Emby -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

SwiftFormat and SwiftLint are optional local tools in this workspace. The Xcode
scripts report when they are missing, but the current build validation does not
depend on them being installed.

## Development Rules

- Preserve MPL-2.0 notices in copied source files.
- Keep provenance in `NOTICE.md`.
- Route new server calls through the Emby request layer.
- Keep player UI behavior wired to the shared manager and libmpv bridge.
- Add SwiftPM tests for new DTO decoding, request construction, and playback
  coordination behavior where practical.
- Validate significant playback changes on a physical iPhone, not only in the
  simulator.

## Signing

Local device installation requires a valid Apple developer team and provisioning
profile for the bundle identifier used by the port. Generic iOS builds can pass
with `CODE_SIGNING_ALLOWED=NO`, but installation to hardware cannot.
