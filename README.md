# Emby iOS Player Port

This directory is the working Emby port of the upstream reference codebase. The
goal is to keep the mature SwiftUI navigation and player-control surface while
replacing the server API boundary with Emby endpoints and the playback engine
with the local libmpv path.

The untouched upstream reference remains in `../References/Swiftfin` for
license, diff, and migration checks. Copied source files keep their MPL-2.0
headers and original attribution where required.

Current migration focus:

- Emby authentication, server info, public users, branding, and session headers.
- Emby home, library, search, item-detail, resume, next-up, image, and playback
  reporting endpoints.
- libmpv playback support in the adjacent `PlayerCore` package.
- Removing generated server-client and legacy player dependencies from runtime
  paths while keeping the Xcode project structure under Emby naming.
