# ADR 0001: Cross-platform desktop architecture

- Status: Accepted
- Date: 2026-10-11
- Decision owners: MC Download Manager maintainers and contributors

## Context

MC Download Manager 1.2.0 is a macOS application built with SwiftUI, AppKit,
Network.framework, WebKit, UserNotifications, ServiceManagement, XcodeGen, and
Xcode. The browser integration is already a shared WebExtension for Safari,
Chromium-family browsers, and Firefox. It talks to the desktop process through a
small HTTP API bound to `127.0.0.1:48213`.

Linux and Windows support cannot be delivered by changing the existing Xcode
target. The current presentation, process lifecycle, local server, browser
discovery, login web view, autostart, notification, clipboard, quarantine,
tool-installation, and packaging code all depend on Apple frameworks or macOS
filesystem conventions.

The port must preserve the existing macOS application and its download data
while creating an implementation that can be built, tested, packaged, and
installed on Linux and Windows.

## Decision drivers

- Keep the existing WebExtension and bridge contract usable during migration.
- Support background/tray operation, multiple windows, notifications,
  clipboard access, autostart, and opening/revealing downloaded files.
- Run and supervise platform-specific `yt-dlp`, `ffmpeg`, and optional `deno`
  binaries.
- Provide a reliable segmented downloader with restart-safe persistence.
- Produce native installers/packages and CI artifacts on all target systems.
- Avoid shipping an additional full browser runtime when the operating system
  web view is sufficient.
- Keep the core independently testable without a desktop session.
- Allow the macOS Swift application to remain the production implementation
  until the replacement reaches explicit parity milestones.

## Considered options

### Continue with Swift and add platform-specific desktop UIs

Swift itself supports Linux and Windows, and some Foundation-based domain logic
could be extracted into SwiftPM packages. SwiftUI, AppKit, Network.framework,
Combine, WebKit, ServiceManagement, and UserNotifications do not provide the
needed cross-platform desktop layer, however. This approach would retain the
language while still requiring two new UI/integration stacks and a substantial
build/release investment.

### Electron with a TypeScript/Node.js backend

Electron has mature desktop APIs and would make an initial prototype quick. It
also bundles Chromium and Node.js, increasing installer size and idle resource
cost for an application intended to remain running in the background.

### Flutter desktop with a Dart core

Flutter offers one UI codebase, but this project would still need native plugins
or a second systems-language layer for download file I/O, process supervision,
tray edge cases, browser integration, and platform packaging. It adds another
runtime without reusing the existing implementation.

### Tauri 2 with a Rust core and web frontend

Tauri provides a cross-platform desktop shell using the operating system web
view, Rust commands/state, tray and lifecycle APIs, scoped capabilities,
sidecars, and native bundle targets. Rust is well suited to concurrent network
and file I/O and can expose a headless core for contract and recovery tests.
Platform differences still require explicit adapters and real target-system
verification.

## Decision

Build the new Linux and Windows application with **Tauri 2**, a **Rust core**,
and a small **TypeScript/Vite frontend**. Keep the current Swift macOS
application in place during the migration. Reconsider a macOS UI replacement
only after the new core reaches feature parity and can migrate existing data.

Place the new implementation under `CrossPlatform/` so it can evolve without
destabilizing the Xcode targets. Split the Rust code into these logical modules:

- `domain`: download models, state transitions, categories, errors, and events;
- `engine`: probing, range planning, transfer workers, retry/throttling,
  pause/resume, and atomic finalization;
- `persistence`: versioned settings, download state, recovery, and migrations;
- `bridge`: loopback HTTP server implementing `contract/bridge/v1/spec.json`;
- `tools`: `yt-dlp`, `ffmpeg`, and `deno` discovery, update, and process control;
- `platform`: paths, trash/reveal/open, notifications, clipboard, autostart,
  tray behavior, browser discovery, and downloaded-file trust metadata;
- `app`: Tauri commands, event projection, and desktop lifecycle wiring.

The frontend is a projection of core state. It must not own queue transitions,
persistence, security decisions, or download file I/O.

## Compatibility and security rules

- `contract/bridge/v1/spec.json` is the compatibility source for the existing
  extension endpoints and payloads.
- The first vertical slice preserves the v1 wire contract. Incompatible changes
  require a new contract version and a negotiated migration period.
- The server binds only to loopback and validates `Host`, extension `Origin`,
  and the extension marker header as described by the contract.
- The current marker/origin policy is request filtering, not strong client
  authentication. A separate security design must evaluate stable extension ID
  allowlists or an install-scoped pairing secret before broad distribution.
- Cookies, authorization headers, authenticated URLs, and tool credentials must
  not appear in ordinary logs, fixtures, crash reports, or UI telemetry.
- Cookie material required for recovery must use restrictive platform storage;
  it must not remain indefinitely in general download-history JSON.

## Migration strategy

1. Add the versioned bridge contract and compatibility tests.
2. Prove a headless Rust vertical slice: extension request, loopback validation,
   single-stream download, progress event, and atomic completed file.
3. Wrap the slice in a minimal Tauri window and validate packaged Linux and
   Windows builds.
4. Add segmented restart recovery, queue scheduling, and migration-safe state.
5. Add tool sidecars and platform adapters.
6. Reach documented Linux and Windows feature milestones independently.
7. Consider sharing or replacing the macOS core only after data migration and
   behavior parity are verified.

## Consequences

### Positive

- Linux and Windows share one core, UI, test suite, and most packaging logic.
- The existing extension and macOS app remain usable throughout the work.
- The download engine and bridge can be tested without rendering the UI.
- External tools can be packaged per Rust target triple and supervised by the
  desktop process.

### Costs and risks

- Most Swift application code will be behaviorally ported rather than directly
  compiled into the new application.
- Rust, Tauri, and frontend toolchains become contributor prerequisites.
- Linux tray behavior, web-view availability, desktop portals, and packaging
  differ by distribution and desktop environment.
- Windows process trees, file locking, path rules, Defender reputation, and
  signing must be handled explicitly.
- Two desktop implementations will coexist until migration milestones are met.

## Validation gates

The architecture is re-evaluated if the proof of concept cannot demonstrate all
of the following on installed Linux and Windows packages:

- extension-to-loopback handoff with the v1 contract;
- completed file download and restart-safe pause/resume;
- tray/background lifecycle and reliable window reopening;
- `yt-dlp` and `ffmpeg` sidecar launch, progress, cancellation, and cleanup;
- native paths, Unicode filenames, notifications, clipboard, autostart, and
  uninstall behavior;
- acceptable idle resource use, package size, accessibility, and signing flow.
