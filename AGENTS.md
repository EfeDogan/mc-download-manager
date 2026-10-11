# AGENTS.md

## Mission

Extend MC Download Manager from a macOS-only application into a maintainable,
cross-platform download manager for macOS, Linux, and Windows, and prepare the
work as reviewable upstream pull requests.

The existing macOS application is the behavioral reference. Preserve working
features and user data while introducing portable components and explicit
platform adapters.

## Current Repository Facts

- The application is written in Swift and uses SwiftUI/AppKit.
- The macOS project and release pipeline are generated with XcodeGen and Xcode.
- Browser integration is a shared WebExtension under `Extension/` and talks to
  a loopback HTTP bridge on `127.0.0.1:48213`.
- Download state is persisted locally; pause/resume and recovery must remain
  backward compatible on macOS unless a migration is provided.
- Video downloads invoke `yt-dlp` and `ffmpeg` as bundled or system tools.
- Safari integration is macOS-only. Chrome/Chromium and Firefox are the
  cross-platform browser targets.

## Working Principles

1. Inspect the current implementation and repository state before changing it.
2. Prefer small, reviewable commits and pull requests over a single rewrite.
3. Keep platform-neutral behavior separate from platform-specific UI and OS
   integration.
4. Do not regress the existing macOS build while adding Linux or Windows work.
5. Preserve existing user data and settings. Document and test every migration.
6. Do not silently change the browser bridge contract. Version it when a
   breaking change is unavoidable.
7. Never weaken loopback binding, `Host` validation, extension `Origin`
   validation, cookie handling, or temporary-file permissions for convenience.
8. Do not commit downloaded binaries, credentials, signing material, cookies,
   build output, or machine-specific configuration.
9. Distinguish verified behavior from assumptions in code reviews and reports.

## Architecture Boundaries

Organize new work around these boundaries, even if the first implementation is
incremental:

- **Core domain:** download models, queue/state transitions, filename and media
  classification, persistence schema, progress reporting, and error mapping.
- **Download engine:** segmented HTTP downloads, range fallback, throttling,
  pause/resume, recovery, and integrity-safe file finalization.
- **Browser bridge:** the existing `/ping`, `/download`, `/downloads`, and
  `/action` behavior plus authentication and origin policy.
- **Tool runner:** discovery, installation/update, invocation, and progress
  parsing for `yt-dlp` and `ffmpeg`.
- **Platform adapters:** paths, process creation, notifications, clipboard,
  autostart, tray/menu behavior, browser discovery, URL opening, and packaging.
- **Presentation:** desktop UI and localization. Business rules must not depend
  on AppKit, SwiftUI, Win32, or a particular Linux desktop environment.

Do not commit to a cross-platform framework solely on familiarity. Record the
decision in an ADR after a small proof of concept demonstrates, on both Linux
and Windows:

- tray/background lifecycle and window reopening;
- the loopback browser bridge;
- segmented download pause/resume across restart;
- launching and stopping `yt-dlp`/`ffmpeg` sidecars;
- native paths, notifications, clipboard, and autostart;
- acceptable package size, accessibility, and release/signing workflow.

## Platform Expectations

### macOS

- Keep the current SwiftUI/AppKit app and Safari extension working until an
  explicitly approved replacement reaches feature parity.
- Continue producing a valid DMG and preserve existing settings/download data.

### Linux

- Support Chrome/Chromium-family browsers and Firefox; Safari is out of scope.
- Treat XDG paths as authoritative (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and
  `XDG_CACHE_HOME`) with documented fallbacks.
- Do not assume one desktop environment. Portal-based integration is preferred
  where practical; document GNOME/KDE-specific limitations.
- Choose package formats only after validating installation, desktop entry,
  tray behavior, autostart, bundled-tool execution, and uninstall cleanup.

### Windows

- Support Chromium-family browsers and Firefox; Safari is out of scope.
- Use Windows-known folders and per-user storage rather than Unix path
  assumptions.
- Account for `.exe` sidecars, process-tree termination, file locking, Defender
  reputation/signing, long paths, and installer/uninstaller behavior.
- Prefer a non-admin per-user installation unless a feature truly requires
  elevation.

## Browser Bridge Compatibility

Treat the current extension payloads and endpoints as a compatibility contract.
Before changing them, add contract fixtures/tests covering:

- allowed extension origins and rejected ordinary/null origins;
- loopback-only host/bind behavior and CORS/private-network preflights;
- file and video download payloads, including cookies, referrer, user agent,
  filename, and segment count;
- pause, resume, cancel, remove, and recent-download status responses;
- behavior when the desktop application is absent or still starting.

Cookie values and authenticated URLs are sensitive. Never log them in normal
operation or include them in test fixtures, issues, screenshots, or PR text.

## Implementation Sequence

1. Inventory current behavior and macOS-specific dependencies; add regression
   tests around portable logic and the browser bridge.
2. Write an ADR comparing viable cross-platform approaches and validate the
   leading option with a disposable proof of concept.
3. Define stable core/adapter interfaces and portable persistence paths/schema.
4. Deliver one end-to-end vertical slice on Linux and Windows: extension request
   to completed single-stream download with visible progress.
5. Add segmented recovery, queue operations, tool integration, settings,
   clipboard, notifications, tray/background mode, and autostart.
6. Add native packaging, CI matrices, signing/checksum/SBOM steps, installation
   documentation, and upgrade/uninstall tests.
7. Close feature gaps deliberately; do not claim parity until the platform
   acceptance checks pass.

## Validation Requirements

For every functional change, run the narrowest relevant tests and then the
affected platform build. Add tests before refactoring security-sensitive bridge,
cookie, persistence, and download-finalization code.

A platform is not "supported" merely because it compiles. Verify on a real or
virtual installation that:

- the packaged app installs and launches without a development environment;
- closing/reopening and tray/background behavior match documented expectations;
- Chrome/Chromium and Firefox can reach the bridge and hand off a download;
- pause/resume survives an application restart;
- filenames, Unicode paths, spaces, and platform path separators work;
- `yt-dlp` and `ffmpeg` discovery/invocation work from the packaged app;
- notification, clipboard, autostart, update, and uninstall behavior are tested;
- secrets are absent from logs and the bridge rejects non-extension callers.

If the current machine cannot run a target platform, say so explicitly and use
CI or a VM for that verification before declaring the work complete.

## Pull Request Standards

- Keep PRs scoped to one architectural step or vertical slice.
- Explain the user-visible outcome, architecture impact, security impact, data
  migration, and rollback strategy.
- Include exact test commands and results for every affected operating system.
- Attach screenshots only when they demonstrate UI behavior; redact private
  data.
- Call out untested platforms and remaining gaps honestly.
- Avoid drive-by formatting or unrelated refactors.

## Definition of Done for Cross-Platform Support

Linux or Windows support is complete only when its packaged release can be
installed by a normal user, integrates with supported browsers, downloads and
resumes both ordinary files and video workflows, survives restart, handles its
platform paths and lifecycle correctly, passes bridge security tests, and has a
repeatable CI/release process with user-facing documentation.
