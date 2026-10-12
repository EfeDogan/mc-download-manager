# MC Download Manager cross-platform implementation

This workspace contains the Linux and Windows implementation selected in
`docs/adr/0001-cross-platform-desktop-architecture.md`.

The first runnable desktop slice is a Tauri 2 application backed by the shared
Rust download engine. The same in-memory manager serves the desktop UI and the
existing WebExtension bridge, so both entry points operate on one queue.

It implements the existing WebExtension endpoints, validates loopback requests,
supports progress plus pause/resume/cancel/remove actions, writes to a private
`.part` file, and atomically renames completed files. Closing the window hides
it while the bridge continues to run from the system tray.

## Install a packaged build

End users should download installers from the fork's
[Releases page](https://github.com/EfeDogan/mc-download-manager/releases), not
from repository paths or build logs. Expand **Assets** under the newest
**Cross-platform preview** release:

- Windows: choose `MC.Download.Manager_0.1.0_x64-setup.exe`;
- Ubuntu/Debian/Linux Mint: choose the file ending in `amd64.deb`;
- portable Linux: choose the file ending in `amd64.AppImage`.

Paths such as `CrossPlatform/target/release/bundle/nsis/*-setup.exe` in the
workflow are internal build paths for GitHub Actions. Users do not create or
navigate to those paths.

The packages are currently unsigned experimental builds. Linux AppImage,
Chromium, and Firefox flows have been manually exercised on Ubuntu. Windows
packages compile in CI but have not yet been run on a real Windows installation.

On Linux, either run the AppImage directly or install the Debian package:

```sh
chmod +x "MC Download Manager_"*.AppImage
./"MC Download Manager_"*.AppImage

# Or, on Debian/Ubuntu:
sudo apt install ./"MC Download Manager_"*.deb
```

On Windows, download and start the Release asset ending in `x64-setup.exe`.
The `.msi` is an alternative installer. SmartScreen may warn because the
packages are not code-signed yet.

## Build from source

Install the [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for
your operating system, then:

```sh
./scripts/fetch-cross-platform-tools.sh
cd CrossPlatform/app
npm install
npm run tauri dev
```

The fetch script downloads the pinned official `yt-dlp` executable for the host
target and verifies its published SHA-256 checksum. The binary is ignored by
Git and embedded into native packages as a platform resource.

Release installers are produced with `npm run tauri build`. The CI workflow
builds `.deb` and AppImage artifacts on Linux plus MSI and NSIS installers on
Windows.

After fetching the host's yt-dlp binary as shown above, run the package command
from `CrossPlatform/app`:

```sh
# Linux
npm run tauri -- build --bundles deb,appimage

# Windows (PowerShell or Command Prompt)
npm run tauri -- build --bundles msi,nsis
```

The tool-fetch script requires Bash. A complete Windows build from the repository
root is:

```sh
bash scripts/fetch-cross-platform-tools.sh x86_64-pc-windows-msvc
cd CrossPlatform/app
npm ci
npm run tauri -- build --bundles msi,nsis
```

## Use the desktop app

- Paste a direct HTTP(S) URL into the main window, or select **Video from page**
  for a site supported by yt-dlp. Known sites such as YouTube and X/Twitter are
  classified automatically.
- Open **Settings** to choose the color mode, palette, and maximum video
  resolution. The quality setting also applies to video requests sent by the
  browser extensions.
- Use **Open download folder** to open the destination in the platform file
  manager.
- Closing the main window leaves the bridge running in the system tray. Use
  **Quit** from the tray menu to stop the process.

The package includes yt-dlp and its recommended Deno JavaScript runtime for
reliable YouTube extraction. Install `ffmpeg` separately and expose it on
`PATH` to merge separate video and audio streams, which is required for many
high-resolution formats.

## Run the core tests

```sh
cd CrossPlatform
cargo test --workspace
cd app
npm ci
npm run build
```

## Run the headless bridge

```sh
cd CrossPlatform
MCDM_DOWNLOAD_DIR="$PWD/downloads" cargo run -p mcdm-core --bin mcdm-headless
```

The process listens on `127.0.0.1:48213`. Requests must follow
`contract/bridge/v1/spec.json`; an ordinary web page is rejected.

## Current scope

Implemented:

- v1 `/ping`, `/download`, `/downloads`, and `/action` routes;
- loopback `Host`, extension `Origin`, and marker-header checks;
- single-stream HTTP(S) downloads with resumable partial files;
- cross-platform filename sanitization and collision-safe destinations;
- progress and pause/resume/cancel/remove state transitions;
- end-to-end bridge-to-file integration test;
- Tauri desktop UI for adding and controlling downloads;
- page-video downloads through bundled, checksum-verified `yt-dlp` and Deno
  binaries;
- scoped browser cookies passed to `yt-dlp` through a temporary mode-0600 jar;
- HTML page detection that prevents a page URL being reported as a completed file;
- one shared queue for desktop and browser-extension requests;
- bundled Chromium extension with an in-app extraction button;
- Firefox-specific Manifest V3 preparation with a temporary `about:debugging`
  installation flow;
- selectable video quality from 360p through 2160p or best available, shared by
  desktop and extension-initiated downloads;
- selectable light/dark mode and three non-neon color palettes;
- system-tray lifecycle on Linux and Windows;
- Linux and Windows installer jobs in GitHub Actions.

Not implemented yet:

- persisted restart recovery and segmented range workers;
- packaged `ffmpeg` and authenticated-site testing;
- desktop notifications, clipboard capture, and autostart;
- Mozilla signing and permanent Firefox add-on distribution for cross-platform releases;
- signing and release publication for native packages.

## Browser extensions

Use **Chromium extension** in the desktop app for Chrome, Chromium, Brave, or
Edge. Load the resulting `ChromiumExtension` directory from the browser's
extensions page with developer mode enabled.

Use **Firefox extension** to create a Firefox-compatible manifest. Open
`about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and
select the displayed `FirefoxExtension/manifest.json`. This development add-on
is removed when Firefox restarts. Standard Firefox releases require a
Mozilla-signed XPI for permanent installation; the existing macOS release
pipeline supports AMO signing, but cross-platform release signing is not yet
configured.
