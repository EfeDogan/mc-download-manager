# Third-party packaged tools

Cross-platform installer builds contain separately executed upstream tools.
They are not committed to this repository; the release workflow downloads and
checksum-verifies them before packaging.

## FFmpeg

- Build provider: <https://github.com/yt-dlp/FFmpeg-Builds>
- Pinned build: `N-127371-gd9242028a6`
- Pinned release: `autobuild-2026-10-11-18-51`
- FFmpeg source revision: <https://github.com/FFmpeg/FFmpeg/commit/d9242028a6>
- Build scripts: <https://github.com/yt-dlp/FFmpeg-Builds/tree/8fc3fe09d1d84a10cecc2b08706e303e27e64834>

The selected FFmpeg build is distributed under GPL terms. Its complete license
text is extracted from the verified upstream archive and installed as
`licenses/FFmpeg-LICENSE.txt` beside the application resources.

See the upstream archives and source revision above for the corresponding
source and reproducible build configuration.
