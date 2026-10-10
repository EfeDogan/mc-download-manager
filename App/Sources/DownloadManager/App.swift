import SwiftUI
import AppKit
import UserNotifications

@main
struct DownloadManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var store: DownloadStore
    @StateObject private var server: ServerController

    init() {
        let s = AppSettings.shared
        let st = DownloadStore(settings: s)
        _settings = StateObject(wrappedValue: s)
        _store = StateObject(wrappedValue: st)
        _server = StateObject(wrappedValue: ServerController(store: st, settings: s))
        AppDelegate.sharedStore = st
        ClipboardWatcher.shared.start(store: st, settings: s)
        UpdateChecker.shared.start(store: st, settings: s)
    }

    var body: some Scene {
        Window("MC Download Manager", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(server)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download…") { NotificationCenter.default.post(name: .showAddSheet, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.shared.check(interactive: true) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(server)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(server)
        } label: {
            Image(systemName: store.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var server: ServerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.activeCount > 0 {
            Text("\(store.activeCount) downloading · \(Fmt.speed(store.totalSpeed))")
        } else {
            Text("No active downloads")
        }
        if server.running { Text("Bridge is running") } else { Text("Bridge is not running") }
        Divider()
        Button("Show Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("New Download…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .showAddSheet, object: nil)
            }
        }
        Divider()
        Button("Pause All") { store.pauseAll() }
        Button("Resume All") { store.resumeAll() }
        Divider()
        if #available(macOS 14.0, *) {
            SettingsLink { Text("Settings…") }
        }
        Button("Check for Updates…") { UpdateChecker.shared.check(interactive: true) }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var sharedStore: DownloadStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleURL.pathExtension == "app" {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for w in sender.windows where w.identifier?.rawValue.contains("main") == true {
                w.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedStore?.shutdown()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
