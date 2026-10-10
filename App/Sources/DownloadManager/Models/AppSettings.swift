import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var segmentCount: Int { didSet { defaults.set(segmentCount, forKey: "segmentCount") } }
    @Published var maxConcurrent: Int { didSet { defaults.set(maxConcurrent, forKey: "maxConcurrent") } }
    @Published var serverPort: Int { didSet { defaults.set(serverPort, forKey: "serverPort") } }
    @Published var downloadDirectory: String { didSet { defaults.set(downloadDirectory, forKey: "downloadDirectory") } }
    @Published var ytdlpPath: String { didSet { defaults.set(ytdlpPath, forKey: "ytdlpPath") } }
    @Published var videoFormat: String { didSet { defaults.set(videoFormat, forKey: "videoFormat") } }
    @Published var autoStart: Bool { didSet { defaults.set(autoStart, forKey: "autoStart") } }
    @Published var notifyOnComplete: Bool { didSet { defaults.set(notifyOnComplete, forKey: "notifyOnComplete") } }
    @Published var showDetailOnStart: Bool { didSet { defaults.set(showDetailOnStart, forKey: "showDetailOnStart") } }
    @Published var autoCloseDetail: Bool { didSet { defaults.set(autoCloseDetail, forKey: "autoCloseDetail") } }
    @Published var watchClipboard: Bool { didSet { defaults.set(watchClipboard, forKey: "watchClipboard") } }
    @Published var captureGroupIDs: Set<String> { didSet { defaults.set(Array(captureGroupIDs).sorted(), forKey: "captureGroupIDs") } }
    @Published var customExtensions: String { didSet { defaults.set(customExtensions, forKey: "customExtensions") } }
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var organizeByCategory: Bool { didSet { defaults.set(organizeByCategory, forKey: "organizeByCategory") } }
    @Published var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") } }

    /// All file extensions (lowercase, no dot) the app should capture.
    var captureExtensions: [String] { CaptureTypes.extensions(groupIDs: captureGroupIDs, custom: customExtensions) }

    static let defaultDownloadDir: String = {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory() + "/Downloads"
        return downloads + "/MC Download Manager"
    }()

    private init() {
        segmentCount = defaults.object(forKey: "segmentCount") as? Int ?? 8
        maxConcurrent = defaults.object(forKey: "maxConcurrent") as? Int ?? 3
        serverPort = defaults.object(forKey: "serverPort") as? Int ?? 48213
        downloadDirectory = defaults.string(forKey: "downloadDirectory") ?? Self.defaultDownloadDir
        ytdlpPath = defaults.string(forKey: "ytdlpPath") ?? ""
        videoFormat = defaults.string(forKey: "videoFormat") ?? "bv*+ba/b"
        autoStart = defaults.object(forKey: "autoStart") as? Bool ?? true
        notifyOnComplete = defaults.object(forKey: "notifyOnComplete") as? Bool ?? true
        showDetailOnStart = defaults.object(forKey: "showDetailOnStart") as? Bool ?? true
        autoCloseDetail = defaults.object(forKey: "autoCloseDetail") as? Bool ?? false
        watchClipboard = defaults.object(forKey: "watchClipboard") as? Bool ?? true
        captureGroupIDs = Set(defaults.stringArray(forKey: "captureGroupIDs") ?? Array(CaptureTypes.defaultGroupIDs))
        customExtensions = defaults.string(forKey: "customExtensions") ?? ""
        onboardingDone = defaults.object(forKey: "onboardingDone") as? Bool ?? false
        organizeByCategory = defaults.object(forKey: "organizeByCategory") as? Bool ?? true
        checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
    }
}
