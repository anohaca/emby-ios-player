# Minimum Supported OS

The Emby iOS player currently targets modern iOS releases so the project can use
the local libmpv integration, SwiftUI player controls, file-provider access, and
device diagnostics without carrying old compatibility branches.

## Policy

- Keep the deployment target aligned with the player engine and dependency
  build requirements.
- Validate playback on physical hardware before lowering or raising the target.
- Prefer removing version-specific branches over supporting old OS releases
  that cannot run the current playback stack reliably.

## Current Device Gate

iPhone 12 remains part of the manual validation set for real-device playback,
rotation, subtitles, gestures, thermal observation, and long-session behavior.

Simulator builds are useful for compile and navigation checks, but player
performance and hardware decode decisions must be confirmed on device.
