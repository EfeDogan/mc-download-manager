import Foundation

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func size(_ n: Int64) -> String { n < 0 ? "?" : bytes.string(fromByteCount: n) }

    static func speed(_ bps: Double) -> String {
        String(localized: "\(bytes.string(fromByteCount: Int64(bps)))/s")
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return String(localized: "\(s) s") }
        if s < 3600 { return String(localized: "\(s / 60) min \(s % 60) s") }
        return String(localized: "\(s / 3600) h \((s % 3600) / 60) min")
    }
}
