# MC Download Manager desktop shell

This Tauri 2 application is the Linux and Windows desktop shell for MC Download
Manager. Its vanilla TypeScript UI calls the shared Rust download engine and the
same manager instance is exposed through the localhost WebExtension bridge.

## Development

```sh
npm install
npm run tauri dev
```

Use `npm run build` for a frontend-only check or `npm run tauri build` to create
a native installer for the current platform.
