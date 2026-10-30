# Third-party packaged tools

Cross-platform installer builds contain separately executed upstream tools.
They are not committed to this repository; the release workflow downloads and
checksum-verifies them before packaging.

## FFmpeg

- Build provider: <https://github.com/yt-dlp/FFmpeg-Builds>
- Pinned build: `N-128201-g5385979def`
- Pinned release: `autobuild-2026-10-29-23-03`
- FFmpeg source revision: <https://github.com/FFmpeg/FFmpeg/commit/5385979def>
- Build scripts: <https://github.com/yt-dlp/FFmpeg-Builds/tree/58084b7cf4984303a34b610ba3ad8f04059d5d89>

The selected FFmpeg build is distributed under GPL terms. Its complete license
text is extracted from the verified upstream archive and installed as
`licenses/FFmpeg-LICENSE.txt` beside the application resources.

See the upstream archives and source revision above for the corresponding
source and reproducible build configuration.
