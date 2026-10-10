import SwiftUI
import AppKit

/// Category checkboxes + custom extensions. Used by the first-launch sheet and the Settings tab.
struct CaptureTypesEditor: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(CaptureTypes.groups) { g in
                Toggle(isOn: Binding(
                    get: { settings.captureGroupIDs.contains(g.id) },
                    set: { on in if on { settings.captureGroupIDs.insert(g.id) } else { settings.captureGroupIDs.remove(g.id) } }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: g.category.symbol).frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.category.label)
                            Text(g.extensions.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
            LabeledContent("Other extensions") {
                TextField("e.g. torrent, srt, ttf", text: $settings.customExtensions)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

/// First-launch flow: 1) file types  2) browser extensions.
struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var chromium = BrowserIntegration.installedChromiumBrowsers
    @State private var installed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to MC Download Manager").font(.title2.bold())
                    if step == 0 {
                        Text("Which file types should be captured?").foregroundStyle(.secondary)
                    } else {
                        Text("Install the browser extensions?").foregroundStyle(.secondary)
                    }
                }
            }
            if step == 0 {
                Text("Browser downloads and copied links with these extensions are handed to the app. Everything else stays in the browser. You can change this later in Settings ▸ File Types.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                CaptureTypesEditor()
                Divider()
                Toggle("Watch the clipboard for links and ask to download them", isOn: $settings.watchClipboard)
            } else {
                Text("The extensions let Safari and Chrome hand their downloads to MC Download Manager and capture videos on pages. You can do this later from Settings ▸ Browser Extensions.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Safari — the extension is built in; it only needs to be enabled in Safari's settings.", systemImage: "safari")
                    ForEach(chromium) { b in
                        Label("\(b.name) — the extensions page opens; turn on Developer mode and choose “Load unpacked” for the revealed folder.", systemImage: "globe")
                    }
                }
                .font(.callout)
                if installed {
                    Text("Done. Enable the extension in Safari, and load the revealed folder in your Chromium browser.")
                        .font(.callout).foregroundStyle(.green)
                }
            }
            HStack {
                if step == 1 {
                    Button("Back") { step = 0 }
                }
                Spacer()
                if step == 0 {
                    Button("Continue") { step = 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { finish() }.keyboardShortcut(.cancelAction)
                    Button(installed ? "Finish" : "Install Extensions") {
                        if installed { finish() } else { installAll() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func installAll() {
        BrowserIntegration.repairSafariExtension()
        BrowserIntegration.openSafariExtensionPreferences()
        for b in chromium {
            BrowserIntegration.openExtensionsPage(in: b)
        }
        installed = true
    }

    private func finish() {
        settings.onboardingDone = true
        dismiss()
    }
}
