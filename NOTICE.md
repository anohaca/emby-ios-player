# Notices

This project is an unofficial Emby-compatible iOS client. It is not
affiliated with, sponsored by, or endorsed by Emby, Jellyfin, Swiftfin, or their
respective owners.

## Swiftfin

Parts of this repository are derived from Swiftfin.

- Upstream: `https://github.com/jellyfin/Swiftfin`
- License: Mozilla Public License 2.0
- Imported reference commit: `5613a770e6090f7cbd09f01bd120917f61a514af`

Files copied from Swiftfin keep their original MPL-2.0 header and copyright
notice where required. Modified copies remain MPL-2.0 at file level.

## Emby Compatibility

The project implements client-side compatibility with Emby server APIs. Emby is
a trademark of its respective owner. This repository does not include Emby
server code.

## Native Playback Dependencies

The local player path is built around libmpv and native multimedia libraries.
Those build artifacts are not committed to this repository. Their use is
subject to their own licenses and to the configuration used when building them.

Common native dependencies may include:

- libmpv
- FFmpeg libraries
- MoltenVK
- libplacebo
- libass
- FreeType
- HarfBuzz
- FriBidi

Review the licenses of the exact dependency builds you distribute.

## Generated and Local Files

Generated build products, signing configuration, provisioning profiles, and
local media/test data are intentionally excluded from git.
