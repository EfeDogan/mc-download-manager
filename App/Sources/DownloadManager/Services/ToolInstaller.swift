import Foundation

/// Downloads the latest yt-dlp from GitHub into Application Support so the app can
/// install it when missing and keep it current (YouTube changes break old yt-dlp builds often).
final class ToolInstaller: ObservableObject {
    static let shared = ToolInstaller()

    @Published var busy = false
    @Published var progress: Double = 0
    @Published var message: String?
    @Published var installedVersion: String?

    static let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    static var binDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MC Download Manager/bin", isDirectory: true)
    }
    static var userYtDlpPath: String { binDirectory.appendingPathComponent("yt-dlp").path }

    /// `yt-dlp --version` for the given executable (cached per path).
    private var versionCache: [String: String] = [:]
    func version(of path: String) -> String? {
        if let v = versionCache[path] { return v }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        p.environment = VideoDownloader.environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let v = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v, !v.isEmpty { versionCache[path] = v }
        return v
    }

    func refreshVersion(custom: String) {
        DispatchQueue.global().async { [weak self] in
            let v = VideoDownloader.locateYtDlp(custom: custom).flatMap { self?.version(of: $0) }
            DispatchQueue.main.async { self?.installedVersion = v }
        }
    }

    /// Downloads yt-dlp_macos, verifies it runs, and installs it to Application Support.
    func installOrUpdateYtDlp(completion: @escaping (Result<String, Error>) -> Void) {
        guard !busy else { return }
        busy = true
        progress = 0
        message = String(localized: "Downloading yt-dlp…")
        let dl = SegmentedDownloader(configuration: .init(
            url: Self.ytDlpURL,
            headers: ["User-Agent": DownloadStore.defaultUserAgent],
            partURL: Self.binDirectory.appendingPathComponent(".yt-dlp.download"),
            segmentCount: 4))
        var total: Int64 = -1
        dl.onProbe = { p in total = p.totalBytes }
        dl.onProgress = { [weak self] received, _ in
            DispatchQueue.main.async { if total > 0 { self?.progress = Double(received) / Double(total) } }
        }
        dl.onFinish = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let e):
                    self.finish(.failure(e), completion)
                case .success:
                    self.message = String(localized: "Verifying…")
                    DispatchQueue.global().async {
                        let r = self.installDownloaded()
                        DispatchQueue.main.async { self.finish(r, completion) }
                    }
                }
            }
        }
        try? FileManager.default.createDirectory(at: Self.binDirectory, withIntermediateDirectories: true)
        dl.start()
    }

    private func installDownloaded() -> Result<String, Error> {
        let fm = FileManager.default
        let tmp = Self.binDirectory.appendingPathComponent(".yt-dlp.download")
        let dest = Self.binDirectory.appendingPathComponent("yt-dlp")
        do {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            // Remove quarantine so Gatekeeper lets us execute it.
            let x = Process()
            x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            x.arguments = ["-d", "com.apple.quarantine", tmp.path]
            x.standardError = FileHandle.nullDevice
            try? x.run(); x.waitUntilExit()
            versionCache[tmp.path] = nil
            guard let v = version(of: tmp.path), !v.isEmpty else {
                try? fm.removeItem(at: tmp)
                throw DownloadFailure(message: String(localized: "The downloaded yt-dlp binary could not be executed."))
            }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: tmp, to: dest)
            versionCache[dest.path] = v
            return .success(v)
        } catch {
            try? fm.removeItem(at: tmp)
            return .failure(error)
        }
    }

    private func finish(_ r: Result<String, Error>, _ completion: (Result<String, Error>) -> Void) {
        busy = false
        progress = 0
        switch r {
        case .success(let v):
            installedVersion = v
            message = String(localized: "yt-dlp \(v) installed.")
        case .failure(let e):
            message = String(localized: "Install failed: \(e.localizedDescription)")
        }
        completion(r)
    }
}
