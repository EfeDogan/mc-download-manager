import Foundation
import Combine
import Network

/// Yerel HTTP köprüsünü yönetir ve istekleri DownloadStore'a çevirir.
final class ServerController: ObservableObject {
    @Published var statusText = String(localized: "Not started")
    @Published var running = false

    private var server: LocalServer?
    private let store: DownloadStore
    private let settings: AppSettings
    private var cancellable: AnyCancellable?

    static let version = "1.0.0"

    init(store: DownloadStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        start()
        cancellable = settings.$serverPort
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.start() }
    }

    func start() {
        server?.stop()
        running = false
        let port = UInt16(clamping: max(1024, min(65535, settings.serverPort)))
        let s = LocalServer(port: port) { [weak self] req, done in
            DispatchQueue.main.async {
                done(self?.handle(req) ?? .json(["ok": false, "error": "shutting down"], status: 500))
            }
        }
        s.onStateChange = { [weak self] st in
            DispatchQueue.main.async {
                switch st {
                case .ready:
                    self?.running = true
                    self?.statusText = String(localized: "Listening on 127.0.0.1:\(String(port))")
                case .failed(let e):
                    self?.running = false
                    self?.statusText = String(localized: "Error: \(e.localizedDescription) (port \(String(port)) may be in use)")
                case .cancelled:
                    self?.running = false
                    self?.statusText = String(localized: "Stopped")
                default:
                    break
                }
            }
        }
        do {
            try s.start()
            server = s
        } catch {
            statusText = String(localized: "Could not start: \(error.localizedDescription)")
        }
    }

    private static func originAllowed(_ origin: String?) -> Bool {
        // Yalnızca tarayıcı eklentileri (ve Origin göndermeyen yerel araçlar, örn. curl).
        guard let origin, !origin.isEmpty, origin != "null" else { return true }
        return origin.hasPrefix("chrome-extension://")
            || origin.hasPrefix("safari-web-extension://")
            || origin.hasPrefix("moz-extension://")
            || origin.hasPrefix("extension://")
    }

    private func handle(_ req: HTTPRequest) -> HTTPResponse {
        if req.method == "OPTIONS" { return .json(["ok": true]) }
        guard Self.originAllowed(req.headers["origin"]) else {
            return .json(["ok": false, "error": "origin not allowed"], status: 403)
        }
        let path = req.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? req.path

        switch (req.method, path) {
        case ("GET", "/ping"):
            return .json([
                "ok": true,
                "app": "MCDownloadManager",
                "version": Self.version,
                "ytdlp": VideoDownloader.locateYtDlp(custom: settings.ytdlpPath) != nil,
                "active": store.items.filter { $0.state.isActive }.count,
                "captureExtensions": settings.captureExtensions,
            ])

        case ("GET", "/downloads"):
            let list: [[String: Any]] = store.items.prefix(50).map {
                [
                    "id": $0.id.uuidString,
                    "name": $0.fileName,
                    "state": $0.state.rawValue,
                    "progress": $0.progress,
                    "speed": $0.speed,
                    "total": $0.totalBytes,
                    "received": $0.receivedBytes,
                ]
            }
            return .json(["ok": true, "items": list])

        case ("POST", "/download"):
            guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
                  let urlStr = obj["url"] as? String,
                  let url = URL(string: urlStr),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                return .json(["ok": false, "error": "invalid url"], status: 400)
            }
            var r = NewDownloadRequest(url: url)
            r.fileName = obj["filename"] as? String
            r.referer = obj["referer"] as? String
            r.userAgent = obj["userAgent"] as? String
            r.cookieHeader = obj["cookieHeader"] as? String
            r.cookies = obj["cookies"] as? [[String: Any]]
            r.kind = (obj["kind"] as? String) == "video" ? .video : .file
            if let h = obj["headers"] as? [String: String] { r.extraHeaders = h }
            if let s = obj["segments"] as? Int { r.segments = s }
            let item = store.add(r)
            return .json(["ok": true, "id": item.id.uuidString])

        case ("POST", "/action"):
            guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any],
                  let idStr = obj["id"] as? String, let id = UUID(uuidString: idStr),
                  let action = obj["action"] as? String else {
                return .json(["ok": false, "error": "id and action required"], status: 400)
            }
            switch action {
            case "pause": store.pause(id)
            case "resume": store.resume(id)
            case "cancel": store.cancel(id)
            case "remove": store.remove(id)
            default: return .json(["ok": false, "error": "unknown action"], status: 400)
            }
            return .json(["ok": true])

        default:
            return .json(["ok": false, "error": "not found"], status: 404)
        }
    }
}
