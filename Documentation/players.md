# Player Notes

The Emby iOS port uses the local libmpv path as the primary playback engine.
The copied SwiftUI player shell is retained for navigation, overlays, gestures,
track menus, queue controls, and reporting, while product-specific network and
playback boundaries are adapted to Emby.

## Runtime Path

| Area | Current implementation |
| --- | --- |
| Stream loading | Emby authenticated stream URLs with session headers |
| Video rendering | libmpv bridge in the iOS target |
| Audio output | libmpv audio path |
| Playback controls | Ported SwiftUI controls with Emby labels and defaults |
| Progress reporting | Emby playback start, progress, and stop endpoints |
| Subtitles | Embedded tracks and external subtitle metadata passed through the player item |

## Compatibility

Format support follows the libmpv and bundled FFmpeg build used by this project.
Server-side remuxing or transcoding is still expected when a file exceeds the
device, network, or local dependency capabilities.

The iOS app should validate at least these playback cases before release:

- H.264 and HEVC MP4 direct play.
- MKV with embedded audio and subtitle tracks.
- External SRT and ASS subtitle selection.
- Seek, pause, stop, next item, previous item, and speed changes.
- Hardware decode policy on real devices.
- Thermal and frame pacing behavior during long playback sessions.

## Known Boundaries

AirPlay casting, Picture in Picture, and HDR behavior depend on the concrete
libmpv build and iOS integration. Treat those as release gates only after the
device test matrix confirms them.
