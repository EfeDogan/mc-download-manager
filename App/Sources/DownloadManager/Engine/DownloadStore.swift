import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import UserNotifications

struct NewDownloadRequest {
    var url: URL
    var fileName: String?
    var referer: String?
    var userAgent: String?
    var cookieHeader: String?
    var cookies: [[String: Any]]?
    var kind: DownloadKind = .file
    var extraHeaders: [String: String] = [:]
    var segments: Int? = nil

    init(url: URL) { self.url = url }
}

/// Tüm indirmelerin durumu, kuyruk ve kalıcılık. Yalnızca ana iş parçacığında kullanılır.
final class DownloadStore: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    let settings: AppSettings
    private var downloaders: [UUID: SegmentedDownloader] = [:]
    private var videoProcesses: [UUID: Process] = [:]
    private var samples: [UUID: (bytes: Int64, time: Date)] = [:]
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var tickCount = 0
    private let supportDir: URL
    private let storeURL: URL

    init(settings: AppSettings) {
        self.settings = settings
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDir = base.appendingPathComponent("MC Download Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        storeURL = supportDir.appendingPathComponent("downloads.json")
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    // MARK: - Sorgular

    /// Final folder for an item: base folder, plus a category subfolder when enabled.
    func destinationDirectory(for item: DownloadItem) -> URL {
        guard settings.organizeByCategory else { return item.directory }
        return item.directory.appendingPathComponent(item.category.label, isDirectory: true)
    }

    func destinationURL(for item: DownloadItem) -> URL {
        destinationDirectory(for: item).appendingPathComponent(item.fileName)
    }

    var activeCount: Int { items.filter { $0.state.isActive }.count }
    var totalSpeed: Double { items.filter { $0.state == .downloading }.reduce(0) { $0 + $1.speed } }

    private func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func update(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let i = index(of: id) else { return }
        var item = items[i]
        mutate(&item)
        items[i] = item
    }

    // MARK: - Ekleme

    @discardableResult
    func add(_ req: NewDownloadRequest) -> DownloadItem {
        var headers = req.extraHeaders
        if let r = req.referer, !r.isEmpty { headers["Referer"] = r }
        if let ua = req.userAgent, !ua.isEmpty { headers["User-Agent"] = ua }
        if let c = req.cookieHeader, !c.isEmpty { headers["Cookie"] = c }
        if headers["User-Agent"] == nil { headers["User-Agent"] = Self.defaultUserAgent }

        var name = req.fileName.flatMap { $0.isEmpty ? nil : $0 } ?? Self.fileName(from: req.url)
        if req.kind == .video { name = req.url.host ?? "video" }
        name = Self.sanitize(name)

        var item = DownloadItem(url: req.url, fileName: name,
                                directory: URL(fileURLWithPath: settings.downloadDirectory),
                                kind: req.kind)
        item.headers = headers
        item.requestedSegments = req.segments ?? 0
        if req.kind == .video, let cookies = req.cookies, !cookies.isEmpty {
            item.cookieFile = writeCookieFile(cookies, id: item.id)
        }
        try? FileManager.default.createDirectory(at: item.directory, withIntermediateDirectories: true)
        items.insert(item, at: 0)
        scheduleSave()
        if settings.autoStart { pumpQueue() }
        if settings.showDetailOnStart { DetailWindowManager.shared.show(id: item.id, store: self) }
        return item
    }

    func addURLs(_ text: String, kind: DownloadKind, segments: Int? = nil) {
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { continue }
            var r = NewDownloadRequest(url: url)
            r.kind = kind
            r.segments = segments
            add(r)
        }
    }

    // MARK: - Kuyruk

    func pumpQueue() {
        var slots = max(0, settings.maxConcurrent - activeCount)
        for item in items.reversed() where item.state == .queued && slots > 0 {
            startItem(item.id)
            slots -= 1
        }
    }

    private func startItem(_ id: UUID) {
        guard let i = index(of: id) else { return }
        let item = items[i]
        if item.kind == .video { startVideo(item) } else { startFile(item) }
    }

    private func startFile(_ item: DownloadItem) {
        let resumable = item.supportsRanges && item.totalBytes > 0 && !item.segments.isEmpty
            && FileManager.default.fileExists(atPath: item.partURL.path)
        var cfg = SegmentedDownloader.Configuration(
            url: item.url, headers: item.headers, partURL: item.partURL,
            segmentCount: item.requestedSegments > 0 ? item.requestedSegments : settings.segmentCount)
        if resumable {
            cfg.resumeSegments = item.segments
            cfg.resumeTotal = item.totalBytes
        }
        let dl = SegmentedDownloader(configuration: cfg)
        let id = item.id
        dl.onProbe = { [weak self, weak dl] probe in
            DispatchQueue.main.async {
                guard let self, self.downloaders[id] === dl else { return }
                self.handleProbe(id: id, probe)
            }
        }
        dl.onProgress = { [weak self, weak dl] received, segs in
            DispatchQueue.main.async {
                guard let self, self.downloaders[id] === dl else { return }
                self.update(id) {
                    $0.receivedBytes = received
                    $0.segments = segs
                    if $0.state == .probing { $0.state = .downloading }
                }
            }
        }
        dl.onFinish = { [weak self, weak dl] result in
            DispatchQueue.main.async {
                guard let self, self.downloaders[id] === dl else { return }
                self.handleFinish(id: id, result)
            }
        }
        downloaders[id] = dl
        update(id) {
            $0.state = resumable ? .downloading : .probing
            $0.errorMessage = nil
            $0.speed = 0
            if !resumable { $0.receivedBytes = 0; $0.segments = [] }
        }
        dl.start()
    }

    private func handleProbe(id: UUID, _ p: ProbeResult) {
        update(id) { item in
            item.totalBytes = p.totalBytes
            item.supportsRanges = p.supportsRanges
            item.state = .downloading
            if let n = p.suggestedFileName, !n.isEmpty {
                item.fileName = Self.sanitize(n)
            } else if let final = p.finalURL, item.fileName == Self.sanitize(Self.fileName(from: item.url)), final != item.url {
                let candidate = Self.fileName(from: final)
                if !(candidate as NSString).pathExtension.isEmpty { item.fileName = Self.sanitize(candidate) }
            }
            if (item.fileName as NSString).pathExtension.isEmpty,
               let ct = p.contentType, let ext = UTType(mimeType: ct)?.preferredFilenameExtension, ext != "bin" {
                item.fileName += "." + ext
            }
        }
    }

    private func handleFinish(id: UUID, _ result: Result<Void, Error>) {
        downloaders[id] = nil
        switch result {
        case .success:
            guard let i = index(of: id) else { return }
            var item = items[i]
            let destDir = destinationDirectory(for: item)
            let dest = Self.uniqueDestination(for: destDir.appendingPathComponent(item.fileName))
            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.partURL, to: dest)
                item.fileName = dest.lastPathComponent
                item.finalPath = dest.path
                item.state = .completed
                item.completedAt = Date()
                item.speed = 0
                if item.totalBytes <= 0 { item.totalBytes = item.receivedBytes }
                items[i] = item
                notifyCompleted(item)
                DetailWindowManager.shared.didComplete(id: id, autoClose: settings.autoCloseDetail)
            } catch {
                item.state = .failed
                item.errorMessage = error.localizedDescription
                items[i] = item
            }
        case .failure(let e):
            update(id) {
                guard $0.state != .paused, $0.state != .cancelled else { return }
                $0.state = .failed
                $0.errorMessage = e.localizedDescription
                $0.speed = 0
            }
        }
        scheduleSave()
        pumpQueue()
    }

    // MARK: - Video (yt-dlp)

    private func startVideo(_ item: DownloadItem) {
        let id = item.id
        guard let exe = VideoDownloader.locateYtDlp(custom: settings.ytdlpPath) else {
            update(id) {
                $0.state = .failed
                $0.errorMessage = String(localized: "yt-dlp not found. Use “Install yt-dlp” in Settings ▸ Video.")
            }
            pumpQueue()
            return
        }
        update(id) { $0.state = .downloading; $0.errorMessage = nil; $0.log = ""; $0.receivedBytes = 0; $0.speed = 0 }
        let outDir = destinationDirectory(for: item)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let proc = VideoDownloader.run(
            executable: exe, url: item.url, outputDir: outDir, format: settings.videoFormat,
            headers: item.headers, cookieFile: item.cookieFile,
            onProgress: { [weak self] p in
                DispatchQueue.main.async {
                    self?.update(id) {
                        $0.receivedBytes = p.downloaded
                        if p.total > 0 { $0.totalBytes = p.total }
                    }
                }
            },
            onLine: { [weak self] line in
                DispatchQueue.main.async {
                    self?.update(id) {
                        $0.log = String(($0.log + line + "\n").suffix(6000))
                        if let r = line.range(of: "Destination: ") {
                            $0.fileName = URL(fileURLWithPath: String(line[r.upperBound...])).lastPathComponent
                        }
                    }
                }
            },
            onFinish: { [weak self] result in
                DispatchQueue.main.async { self?.handleVideoFinish(id: id, result) }
            })
        videoProcesses[id] = proc
    }

    private func handleVideoFinish(id: UUID, _ result: Result<String?, Error>) {
        videoProcesses[id] = nil
        guard let i = index(of: id) else { return }
        var item = items[i]
        guard item.state == .downloading else { return }   // kullanıcı duraklattı/iptal etti
        switch result {
        case .success(let path):
            item.state = .completed
            item.completedAt = Date()
            item.speed = 0
            if let path {
                item.finalPath = path
                item.fileName = URL(fileURLWithPath: path).lastPathComponent
                if let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 {
                    item.totalBytes = size
                    item.receivedBytes = size
                }
            } else if item.totalBytes > 0 {
                item.receivedBytes = item.totalBytes
            }
            items[i] = item
            notifyCompleted(item)
            DetailWindowManager.shared.didComplete(id: id, autoClose: settings.autoCloseDetail)
        case .failure(let e):
            item.state = .failed
            item.errorMessage = e.localizedDescription
            item.speed = 0
            items[i] = item
        }
        scheduleSave()
        pumpQueue()
    }

    // MARK: - Kullanıcı eylemleri

    func pause(_ id: UUID) {
        guard let i = index(of: id), items[i].state.isActive || items[i].state == .queued else { return }
        update(id) { $0.state = .paused; $0.speed = 0 }
        downloaders[id]?.stop()
        if let p = videoProcesses.removeValue(forKey: id) { p.terminate() }
        scheduleSave()
        pumpQueue()
    }

    func resume(_ id: UUID) {
        guard let i = index(of: id), [.paused, .failed, .cancelled].contains(items[i].state) else { return }
        update(id) { $0.state = .queued; $0.errorMessage = nil }
        pumpQueue()
    }

    func cancel(_ id: UUID) {
        guard let i = index(of: id) else { return }
        let item = items[i]
        if let dl = downloaders.removeValue(forKey: id) { dl.stop() }
        if let p = videoProcesses.removeValue(forKey: id) { p.terminate() }
        try? FileManager.default.removeItem(at: item.partURL)
        update(id) { $0.state = .cancelled; $0.speed = 0; $0.receivedBytes = 0; $0.segments = [] }
        scheduleSave()
        pumpQueue()
    }

    func remove(_ id: UUID, deleteFile: Bool = false) {
        guard let i = index(of: id) else { return }
        let item = items[i]
        if let dl = downloaders.removeValue(forKey: id) { dl.stop() }
        if let p = videoProcesses.removeValue(forKey: id) { p.terminate() }
        try? FileManager.default.removeItem(at: item.partURL)
        if let cf = item.cookieFile { try? FileManager.default.removeItem(atPath: cf) }
        if deleteFile, let fp = item.finalPath, FileManager.default.fileExists(atPath: fp) {
            // Always move to Trash so the user can recover the file.
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: fp), resultingItemURL: nil)
        }
        items.remove(at: i)
        samples[id] = nil
        scheduleSave()
        pumpQueue()
    }

    func pauseAll() { items.filter { $0.state.isActive || $0.state == .queued }.forEach { pause($0.id) } }
    func resumeAll() { items.filter { [.paused, .failed].contains($0.state) }.forEach { resume($0.id) } }
    func clearFinished() {
        items.filter { [.completed, .cancelled].contains($0.state) }.forEach { remove($0.id) }
    }

    func revealInFinder(_ item: DownloadItem) {
        if let fp = item.finalPath, FileManager.default.fileExists(atPath: fp) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fp)])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([destinationDirectory(for: item)])
        }
    }

    func open(_ item: DownloadItem) {
        guard let fp = item.finalPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: fp))
    }

    func shutdown() {
        pauseAll()
        save()
    }

    // MARK: - Hız ölçümü

    private func tick() {
        let now = Date()
        var activeIDs = Set<UUID>()
        for i in items.indices where items[i].state == .downloading {
            let id = items[i].id
            activeIDs.insert(id)
            let bytes = items[i].receivedBytes
            if let s = samples[id] {
                let dt = now.timeIntervalSince(s.time)
                if dt > 0 {
                    let inst = max(0, Double(bytes - s.bytes) / dt)
                    items[i].speed = items[i].speed == 0 ? inst : items[i].speed * 0.6 + inst * 0.4
                }
            }
            samples[id] = (bytes, now)
        }
        samples = samples.filter { activeIDs.contains($0.key) }
        DetailWindowManager.shared.refreshTitles(items: items)
        tickCount += 1
        if !activeIDs.isEmpty, tickCount % 10 == 0 { save() }   // parça durumu 5 sn'de bir diske
    }

    // MARK: - Kalıcılık

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              var arr = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        for i in arr.indices {
            if arr[i].state.isActive || arr[i].state == .queued { arr[i].state = .paused }
            arr[i].speed = 0
        }
        items = arr
        cleanupOrphanParts()
    }

    /// Listede olmayan indirmelerden kalan `.dm-<id>.part` dosyalarını siler.
    private func cleanupOrphanParts() {
        let dir = URL(fileURLWithPath: settings.downloadDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let known = Set(items.map { ".dm-\($0.id.uuidString).part" })
        for n in names where n.hasPrefix(".dm-") && n.hasSuffix(".part") && !known.contains(n) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    private func writeCookieFile(_ cookies: [[String: Any]], id: UUID) -> String? {
        var lines = ["# Netscape HTTP Cookie File"]
        for c in cookies {
            guard let name = c["name"] as? String, let value = c["value"] as? String,
                  let domain = c["domain"] as? String else { continue }
            let path = c["path"] as? String ?? "/"
            let secure = (c["secure"] as? Bool ?? false) ? "TRUE" : "FALSE"
            let exp = Int64((c["expirationDate"] as? Double) ?? 0)
            let flag = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            lines.append([domain, flag, path, secure, String(exp), name, value].joined(separator: "\t"))
        }
        let dir = supportDir.appendingPathComponent("cookies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id.uuidString).txt")
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url.path
        } catch {
            return nil
        }
    }

    // MARK: - Bildirim

    private func notifyCompleted(_ item: DownloadItem) {
        guard settings.notifyOnComplete, Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Download completed")
        content.body = item.fileName
        content.sound = .default
        let req = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    static let defaultUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // MARK: - Dosya adı yardımcıları

    static func fileName(from url: URL) -> String {
        var name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if name.isEmpty || name == "/" { name = url.host ?? "download" }
        return name
    }

    static func sanitize(_ s: String) -> String {
        var n = s.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix(".") { n = "_" + n }
        if n.count > 200 {
            let ext = (n as NSString).pathExtension
            let base = String((n as NSString).deletingPathExtension.prefix(180))
            n = ext.isEmpty ? base : base + "." + ext
        }
        return n.isEmpty ? "download" : n
    }

    static func uniqueDestination(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
