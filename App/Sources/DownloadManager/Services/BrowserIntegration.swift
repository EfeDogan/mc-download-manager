import AppKit
import Foundation
import SafariServices

/// Installs / repairs the browser extensions.
/// - Safari: the extension ships inside the app; "install" means enabling it in Safari's preferences.
/// - Chromium browsers: the unpacked extension is copied to a stable folder, the browser's extensions page
///   is opened and a step-by-step guide is shown (Chrome does not allow silent installs outside the Web Store).
enum BrowserIntegration {
    static let safariExtensionID = "com.mesutcevik.mcdownloadmanager.safari"
    /// Set this once the extension is published on the Chrome Web Store; "Install" then opens the store page.
    static let chromeWebStoreURL: URL? = nil

    struct ChromiumBrowser: Identifiable, Hashable {
        let id: String          // bundle id
        let name: String
        let appURL: URL
        let extensionsURL: String
    }

    private static let knownChromium: [(String, String, String)] = [
        ("com.google.Chrome", "Google Chrome", "chrome://extensions"),
        ("com.brave.Browser", "Brave", "brave://extensions"),
        ("com.microsoft.edgemac", "Microsoft Edge", "edge://extensions"),
        ("company.thebrowser.Browser", "Arc", "arc://extensions"),
        ("com.vivaldi.Vivaldi", "Vivaldi", "vivaldi://extensions"),
        ("com.operasoftware.Opera", "Opera", "opera://extensions"),
        ("org.chromium.Chromium", "Chromium", "chrome://extensions"),
        ("com.google.Chrome.canary", "Chrome Canary", "chrome://extensions"),
    ]

    static var installedChromiumBrowsers: [ChromiumBrowser] {
        knownChromium.compactMap { id, name, ext in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return ChromiumBrowser(id: id, name: name, appURL: url, extensionsURL: ext)
        }
    }

    /// Bundled unpacked extension (inside the app).
    static var bundledExtensionFolder: URL {
        if let override = ProcessInfo.processInfo.environment["MCDM_EXTENSION_DIR"] { return URL(fileURLWithPath: override) }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension")
    }

    /// Stable copy outside the app bundle so "Load unpacked" keeps working across app updates.
    static var installedExtensionFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MC Download Manager/ChromeExtension", isDirectory: true)
    }

    private static let queue = DispatchQueue(label: "dm.browser-integration", qos: .userInitiated)

    // MARK: Safari

    static func safariExtensionEnabled() async -> Bool? {
        await withCheckedContinuation { cont in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: safariExtensionID) { state, _ in
                cont.resume(returning: state?.isEnabled)
            }
        }
    }

    static func openSafariExtensionPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: safariExtensionID) { error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Safari-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Re-registers the app and its extension with the system (helps when Safari does not list it).
    /// Runs in the background; `completion` is called on the main thread.
    static func repairSafariExtension(completion: (() -> Void)? = nil) {
        let appPath = Bundle.main.bundleURL.path
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/MC Download Manager Extension.appex").path
        queue.async {
            run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", appPath])
            run("/usr/bin/pluginkit", ["-a", appex])
            run("/usr/bin/pluginkit", ["-e", "use", "-i", safariExtensionID])
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: Chromium

    /// Copies the unpacked extension to the stable folder. Returns the folder.
    @discardableResult
    static func installUnpackedExtension() throws -> URL {
        let fm = FileManager.default
        let dest = installedExtensionFolder
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: bundledExtensionFolder, to: dest)
        return dest
    }

    /// Opens the browser's extensions page, reveals the folder and shows a short guide.
    static func openExtensionsPage(in browser: ChromiumBrowser, showGuide: Bool = true) {
        if let store = chromeWebStoreURL {
            NSWorkspace.shared.open([store], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let folder = (try? installUnpackedExtension()) ?? bundledExtensionFolder
        // Same mechanism as `open -a "Google Chrome" chrome://extensions` (works whether or not the browser runs).
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        if let url = URL(string: browser.extensionsURL) {
            NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: cfg) { _, error in
                if error != nil { run("/usr/bin/open", ["-a", browser.appURL.path, browser.extensionsURL]) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            if showGuide {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showLoadUnpackedGuide(browser: browser, folder: folder) }
            }
        }
    }

    private static func showLoadUnpackedGuide(browser: ChromiumBrowser, folder: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Finish installing in \(browser.name)")
        alert.informativeText = String(localized: """
        \(browser.name) does not allow apps to install extensions automatically. On the extensions page that just opened:

        1. Turn on “Developer mode” (top right).
        2. Click “Load unpacked”.
        3. Select this folder (press ⇧⌘G in the file dialog and paste the path):

        \(folder.path)
        """)
        alert.addButton(withTitle: String(localized: "Copy Folder Path"))
        alert.addButton(withTitle: String(localized: "Done"))
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(folder.path, forType: .string)
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
