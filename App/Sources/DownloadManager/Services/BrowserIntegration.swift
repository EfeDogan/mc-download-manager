import AppKit
import Foundation
import SafariServices

/// Installs / repairs the browser extensions.
/// - Safari: the extension ships inside the app; "install" means enabling it in Safari's preferences.
/// - Chromium browsers: the unpacked extension is copied to a stable folder and chrome://extensions is opened.
enum BrowserIntegration {
    static let safariExtensionID = "com.mesutcevik.mcdownloadmanager.safari"
    /// Set this once the extension is published on the Chrome Web Store; "Install" then opens the store page.
    static let chromeWebStoreURL: URL? = nil

    struct ChromiumBrowser: Identifiable, Hashable {
        let id: String          // bundle id
        let name: String
        let appURL: URL
    }

    private static let knownChromium: [(String, String)] = [
        ("com.google.Chrome", "Google Chrome"),
        ("com.brave.Browser", "Brave"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.operasoftware.Opera", "Opera"),
        ("org.chromium.Chromium", "Chromium"),
        ("com.google.Chrome.canary", "Chrome Canary"),
    ]

    static var installedChromiumBrowsers: [ChromiumBrowser] {
        knownChromium.compactMap { id, name in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return ChromiumBrowser(id: id, name: name, appURL: url)
        }
    }

    /// Bundled unpacked extension (inside the app).
    static var bundledExtensionFolder: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension")
    }

    /// Stable copy outside the app bundle so "Load unpacked" keeps working across app updates.
    static var installedExtensionFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MC Download Manager/ChromeExtension", isDirectory: true)
    }

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
            if error != nil {
                // Fallback: open Safari's extension settings pane.
                if let url = URL(string: "x-apple.systempreferences:com.apple.Safari-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Re-registers the app and its extension with the system (helps when Safari does not list it).
    static func repairSafariExtension() {
        let appex = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/MC Download Manager Extension.appex")
        run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            ["-f", Bundle.main.bundleURL.path])
        run("/usr/bin/pluginkit", ["-a", appex.path])
        run("/usr/bin/pluginkit", ["-e", "use", "-i", safariExtensionID])
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

    /// Opens the browser's extension page and reveals the folder to load.
    static func openExtensionsPage(in browser: ChromiumBrowser) {
        if let store = chromeWebStoreURL {
            NSWorkspace.shared.open([store], withApplicationAt: browser.appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let folder = (try? installUnpackedExtension()) ?? bundledExtensionFolder
        let scheme: String
        switch browser.id {
        case "com.microsoft.edgemac": scheme = "edge://extensions"
        case "com.brave.Browser": scheme = "brave://extensions"
        case "com.vivaldi.Vivaldi": scheme = "vivaldi://extensions"
        case "com.operasoftware.Opera": scheme = "opera://extensions"
        default: scheme = "chrome://extensions"
        }
        // chrome:// URLs cannot be passed through NSWorkspace; launch the browser with the URL as an argument.
        let exe = Bundle(url: browser.appURL)?.executableURL
        if let exe {
            run(exe.path, [scheme])
        } else {
            NSWorkspace.shared.openApplication(at: browser.appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
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
        if path.hasSuffix("lsregister") || path.hasSuffix("pluginkit") { p.waitUntilExit() }
        return p.terminationStatus
    }
}
