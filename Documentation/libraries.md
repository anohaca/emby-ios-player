# Library Support

This port targets the Emby media workflows needed by an iOS video player first.
The current migration priority is stable browse, detail, queue, and playback for
video-centric libraries.

| Library type | Status | Notes |
| --- | --- | --- |
| Movies | Supported | Browse, detail, playback, images, watched state, and favorite state are routed through Emby calls. |
| TV Shows | Supported | Series, season, episode, next-up, adjacent episode queue, and playback reporting are covered. |
| Collections | Partial | Video items are supported; mixed non-video presentation still needs dedicated UI work. |
| Music Videos | Supported | Uses the same video item and playback path. |
| Home Videos | Supported | Uses the same video item and playback path. |
| Live TV | Partial | Channel and program browse paths are present; release testing should cover stream startup and guide behavior. |
| Music | Not targeted yet | Needs a dedicated audio-first queue, now-playing surface, and background behavior. |
| Photos | Not targeted yet | Needs a dedicated image viewer and cache policy. |
| Books | Not targeted yet | Needs a reader surface and separate progress model. |

The table describes the ported app surface, not the full set of item types an
Emby server can expose.
