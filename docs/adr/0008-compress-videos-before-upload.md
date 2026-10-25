# Compress videos on the Mac before uploading

Screen recordings often go over the Free plan's 100 MB video Size Limit. A 5-minute Retina recording is about 230 MB. Cloudinary can't help: uploads are capped at 100 MB, and it only transforms videos up to 40 MB. So, reversing [ADR 0003](0003-direct-signed-uploads-no-server.md)'s "refused rather than shrunk", each video is compressed on the Mac before it's uploaded, and the Size Limit is checked on the compressed file. The compressed file is an H.264/AAC MP4 with faststart, so it plays in any browser, and its Share Link ends in `.mp4`. Images are never compressed, and the original file is never changed.

The encoder is the user's Homebrew ffmpeg with libx264. It isn't bundled, and the app never installs it. Without ffmpeg, or with Compression turned off in the menu, videos are handled exactly as before. The settings are tuned for the fanless 8 GB M1 Air, the main Mac:
- hardware decoding, and scaling on the GPU (`scale_vt`) only when a recording doesn't fit within 1920×1920, rounded down to even sizes
- a phone video's rotation turned on the GPU too (`transpose_vt`), so the output is upright with no rotation metadata. ffmpeg's own autorotation needs CPU frames, so it's off (`-noautorotate`); with ffmpeg 8 that alone drops the rotation, and a portrait video played sideways
- preset `veryfast`, `-threads 2`, at most 30 fps, and 96 kbps AAC audio
- the CRF comes from the menu's Quality Level: 22 by default, or 24 or 26

That takes about 20–30% of the recording's length, about one core and about 330 MB of memory. A compressed file still over the limit is refused (saved to Downloads, both versions for a Capture) and never compressed again at a lower level. If ffmpeg fails, the original is uploaded when it fits the limit. Compression ignores the Mac's thermal state.

The menu's Compress Videos toggle and its three Quality Levels (now in the Settings submenu, see ADR 0004) were the first exception to ADR 0004's "no settings UI beyond the one field". The levels trade sharpness for size, and only the user can judge that, recording by recording.

## Considered Options

- **Apple's VideoToolbox H.264 encoder**: files about 3× bigger, so a 10-minute recording stays over 100 MB.
- **x264 `medium`**: 57% more CPU for about 10% smaller files.
- **Full Retina resolution**: about 1.1 GB of memory. **1440×900**: 30% less CPU, but small text gets softer.
- **More than 2 threads**: no faster on the Air. **Efficiency cores only**: 4× slower.
- **Retrying at a lower quality, or pausing when the Mac is hot**: rejected to keep the queue predictable.
- **A second storage service for large videos**: still out of scope.
