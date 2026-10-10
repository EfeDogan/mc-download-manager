import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: ServerController

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            FileTypesSettings().tabItem { Label("File Types", systemImage: "doc.badge.gearshape") }
            BrowserSettings().tabItem { Label("Browser Extensions", systemImage: "puzzlepiece.extension") }
            VideoSettings().tabItem { Label("Video", systemImage: "film") }
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Download folder") {
                    HStack {
                        Text(settings.downloadDirectory).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Show") { NSWorkspace.shared.open(URL(fileURLWithPath: settings.downloadDirectory)) }
                        Button("Choose…") { chooseDirectory() }
                    }
                }
                Toggle("Organize downloads into category subfolders (Video, Music, Archives…)", isOn: $settings.organizeByCategory)
            }
            Section("Connections") {
                Slider(value: Binding(get: { Double(settings.segmentCount) },
                                      set: { settings.segmentCount = Int($0) }), in: 1...16, step: 1) {
                    Text("Connections per download: \(settings.segmentCount)")
                }
                Text("Each file is downloaded with up to this many parallel connections (4–10 recommended).")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Concurrent downloads: \(settings.maxConcurrent)", value: $settings.maxConcurrent, in: 1...10)
            }
            Section("Behaviour") {
                Toggle("Start new downloads immediately", isOn: $settings.autoStart)
                Toggle("Show a notification when a download completes", isOn: $settings.notifyOnComplete)
                Toggle("Open the download window when a download starts", isOn: $settings.showDetailOnStart)
                Toggle("Close the download window automatically when completed", isOn: $settings.autoCloseDetail)
                Toggle("Watch the clipboard for links and ask to download them", isOn: $settings.watchClipboard)
                Text("Only links that point to a captured file type trigger the prompt. You can also paste a link into the main window with ⌘V.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch in the background at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in toggleLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Updates") {
                Toggle("Check for updates automatically (GitHub Releases)", isOn: $settings.checkForUpdates)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current version: \(UpdateChecker.currentVersion)")
                        if let v = updater.latestVersion {
                            Text("Latest release: \(v)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let d = updater.lastCheck {
                            Text("Last checked: \(d.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = updater.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer()
                    Button(updater.checking ? "Checking…" : "Check Now") { updater.check(interactive: true) }
                        .disabled(updater.checking)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: settings.downloadDirectory)
        if p.runModal() == .OK, let u = p.url { settings.downloadDirectory = u.path }
    }

    private func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - File types

struct FileTypesSettings: View {
    var body: some View {
        Form {
            Section("Captured file types") {
                Text("Browser downloads and copied links with these extensions are handed to the app. Everything else stays in the browser.")
                    .font(.caption).foregroundStyle(.secondary)
                CaptureTypesEditor()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Browser extensions

struct BrowserSettings: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var server: ServerController
    @State private var safariEnabled: Bool?
    @State private var chromium = BrowserIntegration.installedChromiumBrowsers
    @State private var installMessage: String?

    var body: some View {
        Form {
            Section("Safari") {
                HStack {
                    Circle().fill(safariEnabled == true ? .green : (safariEnabled == false ? .orange : .gray)).frame(width: 8, height: 8)
                    if safariEnabled == true {
                        Text("Extension is enabled in Safari")
                    } else if safariEnabled == false {
                        Text("Extension is not enabled in Safari")
                    } else {
                        Text("Extension state unknown")
                    }
                    Spacer()
                    Button("Refresh") { refreshSafari() }
                }
                HStack {
                    Button("Enable in Safari…") { BrowserIntegration.openSafariExtensionPreferences() }
                    Button("Repair") {
                        BrowserIntegration.repairSafariExtension()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshSafari() }
                    }
                }
                Text("Ad-hoc signed builds also need Safari ▸ Develop ▸ Allow Unsigned Extensions. “Repair” re-registers the extension with the system.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Chrome / Chromium-based browsers") {
                if chromium.isEmpty {
                    Text("No Chromium-based browser found in /Applications.").foregroundStyle(.secondary)
                } else {
                    ForEach(chromium) { b in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: b.appURL.path)).resizable().frame(width: 20, height: 20)
                            Text(b.name)
                            Spacer()
                            Button("Install / Repair…") { install(in: b) }
                        }
                    }
                }
                Text("Chrome does not allow apps to install extensions silently. “Install” copies the extension to a stable folder, opens the browser's extensions page and reveals the folder: turn on Developer mode and choose “Load unpacked”.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(BrowserIntegration.installedExtensionFolder.path).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Show Folder") {
                        let f = (try? BrowserIntegration.installUnpackedExtension()) ?? BrowserIntegration.bundledExtensionFolder
                        NSWorkspace.shared.activateFileViewerSelecting([f])
                    }
                }
                if let installMessage { Text(installMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Local bridge") {
                HStack {
                    TextField("Port", value: $settings.serverPort, format: .number.grouping(.never))
                        .frame(width: 90)
                    Circle().fill(server.running ? .green : .red).frame(width: 8, height: 8)
                    Text(server.statusText).font(.caption).foregroundStyle(.secondary)
                }
                Text("The extension uses port 48213 by default. If you change it here, enter the same port in the extension settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshSafari() }
    }

    private func refreshSafari() {
        Task {
            let state = await BrowserIntegration.safariExtensionEnabled()
            await MainActor.run { safariEnabled = state }
        }
    }

    private func install(in b: BrowserIntegration.ChromiumBrowser) {
        BrowserIntegration.openExtensionsPage(in: b)
        installMessage = String(localized: "Opened \(b.name). Turn on Developer mode, click “Load unpacked” and select the revealed folder.")
    }
}

// MARK: - Video

struct VideoSettings: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var login = SiteLoginManager.shared
    @ObservedObject private var installer = ToolInstaller.shared

    var body: some View {
        Form {
            Section("Site login (YouTube age verification, members-only videos)") {
                Text("Some videos require a signed-in account. Sign in once in the built-in browser window; the saved cookies are passed to yt-dlp for video downloads. Downloads started from the browser extension already carry the browser's cookies.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if login.cookieCount > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in: \(login.domains.prefix(4).joined(separator: ", "))")
                            if let d = login.savedAt {
                                Text("\(login.cookieCount) cookies saved \(d.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Not signed in").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign in to YouTube…") { login.openLogin() }
                    Button("Clear") { login.clear() }.disabled(login.cookieCount == 0)
                }
            }
            Section("yt-dlp") {
                HStack {
                    if let found = VideoDownloader.locateYtDlp(custom: settings.ytdlpPath) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let v = installer.installedVersion {
                                Text("yt-dlp \(v)")
                            } else {
                                Text("yt-dlp")
                            }
                            Text(found).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    } else {
                        Text("yt-dlp not found").foregroundStyle(.red)
                    }
                    Spacer()
                    Button(installer.busy ? "Installing…" : (VideoDownloader.locateYtDlp(custom: settings.ytdlpPath) == nil ? "Install yt-dlp" : "Update yt-dlp")) {
                        installer.installOrUpdateYtDlp { _ in installer.refreshVersion(custom: settings.ytdlpPath) }
                    }
                    .disabled(installer.busy)
                }
                if installer.busy {
                    ProgressView(value: installer.progress).progressViewStyle(.linear)
                }
                if let m = installer.message { Text(m).font(.caption).foregroundStyle(.secondary) }
                Text("yt-dlp and ffmpeg are bundled with the app. “Update” downloads the latest yt-dlp release from GitHub into Application Support and uses it instead of the bundled copy. Update when YouTube downloads stop working.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Custom yt-dlp path (empty = bundled)", text: $settings.ytdlpPath)
                    Button("Choose…") { chooseYtDlp() }
                }
                if let ff = VideoDownloader.locateFfmpeg() {
                    Text("ffmpeg: \(ff)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("ffmpeg not found (merging video and audio will not work)").font(.caption).foregroundStyle(.red)
                }
            }
            Section("Format") {
                TextField("yt-dlp -f value", text: $settings.videoFormat)
                Text("Examples: bv*+ba/b (best), bv*[height<=1080]+ba/b (up to 1080p), ba (audio only)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { installer.refreshVersion(custom: settings.ytdlpPath) }
    }

    private func chooseYtDlp() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.showsHiddenFiles = true
        if p.runModal() == .OK, let u = p.url { settings.ytdlpPath = u.path }
    }
}
