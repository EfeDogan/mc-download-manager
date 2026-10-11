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

## Run the desktop app

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
- page-video downloads through a bundled, checksum-verified `yt-dlp`;
- scoped browser cookies passed to `yt-dlp` through a temporary mode-0600 jar;
- HTML page detection that prevents a page URL being reported as a completed file;
- one shared queue for desktop and browser-extension requests;
- bundled Chromium extension with an in-app extraction button;
- system-tray lifecycle on Linux and Windows;
- Linux and Windows installer jobs in GitHub Actions.

Not implemented yet:

- persisted restart recovery and segmented range workers;
- packaged `ffmpeg`/`deno`, video quality settings, and authenticated-site testing;
- desktop notifications, clipboard capture, and autostart;
- signing and release publication for native packages.
