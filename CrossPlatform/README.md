# MC Download Manager cross-platform implementation

This workspace contains the Linux and Windows implementation selected in
`docs/adr/0001-cross-platform-desktop-architecture.md`.

The first runnable slice is a headless bridge and single-stream download engine.
It implements the existing WebExtension endpoints, validates loopback requests,
supports progress plus pause/resume/cancel/remove actions, writes to a private
`.part` file, and atomically renames completed files.

## Run the core tests

```sh
cd CrossPlatform
cargo test --workspace
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
- end-to-end bridge-to-file integration test.

Not implemented yet:

- persisted restart recovery and segmented range workers;
- video downloads and packaged `yt-dlp`/`ffmpeg`/`deno` tools;
- the Tauri window, tray, notifications, clipboard, and autostart;
- native Linux and Windows packages.
