# Dark appearance and download controls QA

## Comparison target

- Source visual truth: `/tmp/codex-clipboard-1684a7c3-d529-4639-9271-d04479eea6ea.png`
- Source size: 243 x 182 px.
- Browser-rendered implementation: `CrossPlatform/app/design-qa-download-type-fixed.jpg`
- Implementation crop: 440 x 190 px from a 490 x 900 CSS px viewport at DPR 1.
- Focused comparison: `CrossPlatform/app/design-qa-download-type-comparison.jpg`
- Dark-mode full view: `CrossPlatform/app/design-qa-dark-mode.jpg` (540 x 876 px capture).
- Logo source: `logo.png` (1254 x 1254 px RGBA).
- Logo implementation view: `CrossPlatform/app/design-qa-logo-light.jpg` (540 x 876 px capture).
- State: Stormy morning palette; light mode for the reported native-select defect and dark mode for the new appearance option.

## Findings

- Resolved P1: Download type value was unreadable in a light theme.
  - Evidence: the source shows Chromium drawing a dark native select while its text remains dark. The focused post-fix comparison shows the select using the light theme's explicit surface and text colors.
  - Fix: changed the document declaration from dark-only to light/dark, assigned `color-scheme` from the selected appearance, and explicitly themed `select` and `option` foreground/background colors.
- Resolved P2: no dark appearance was available for the supplied palettes.
  - Evidence: the full-view capture shows the Stormy morning dark variant with consistent field, card, button, status, and typography colors. Ink wash and Lush forest dark variants were also exercised in the browser preview.
  - Fix: added a persisted Light/Dark selector independent of the three palette choices and supplied dark tokens for every palette.
- Resolved P2: the download directory required manual navigation.
  - Evidence: the rendered Downloads header contains an enabled Open download folder action; the browser interaction announced `Download folder opened.`
  - Fix: added a cross-platform desktop command using Explorer on Windows, `open` on macOS, and `xdg-open` on Linux.
- Resolved P1: the app still used the previous neon icon and an in-app text mark.
  - Evidence: the supplied 1254 px logo is visible in the final light and dark application captures; generated 32 px and 512 px icon outputs retain its shape and color separation.
  - Fix: installed the supplied logo in the app header and generated Tauri's PNG, ICO, ICNS, Linux, and Windows icon assets from the same source.

## Fidelity surfaces

- Fonts and typography: existing restrained Noto Sans/system stack and hierarchy remain unchanged; light and dark labels remain legible.
- Spacing and layout: the new folder action aligns with the download count and wraps at the existing responsive breakpoint. Settings remains usable in the 490 px QA viewport.
- Colors and tokens: all six palette/mode combinations use explicit foreground, background, border, focus, and semantic-state tokens. Field contrast ranges from 9.38:1 to 14.32:1.
- Image quality and assets: the supplied source logo is used directly in the UI and as the single source for all desktop package icons; no substitute or code-drawn approximation was introduced.
- Copy and content: Light/Dark, Palette, and Open download folder labels describe their actions directly.

## Interaction and automated checks

- Theme and appearance selections update immediately and persist after reload.
- Download type computed colors in Stormy morning light: foreground `rgb(45, 61, 75)`, background `rgb(227, 237, 241)`, `color-scheme: light`.
- Download type computed colors in Stormy morning dark: foreground `rgb(234, 244, 252)`, background `rgb(41, 56, 69)`, `color-scheme: dark`.
- Browser console warnings/errors: none.
- Frontend build: passed.
- Rust workspace tests: 19/19 passed.
- Repository JavaScript tests: 21/21 passed.
- Desktop packaging: `.deb`, `.rpm`, and `.AppImage` passed; packaged Debian 32 px and 128 px icon hashes match the generated source icons.
- `git diff --check`: passed.

## Comparison history

1. Initial source evidence identified the light-theme native select as a P1 contrast failure.
2. The document and control color schemes were corrected and explicit select colors were added.
3. Post-fix focused comparison confirms readable light-theme text; no P0/P1/P2 issue remains for the select, dark appearance, or folder action.
4. After the source logo became available, it was installed and regenerated at all required desktop sizes; the final light/dark captures and icon inspection show no actionable raster issue.

## Implementation checklist

- Keep `logo.png` as the canonical source asset.
- Re-run `tauri icon ../../logo.png` when the canonical logo changes.
- Rebuild platform packages after icon changes.

## Final result

final result: passed

No actionable P0, P1, or P2 issue remains in the implemented scope.
