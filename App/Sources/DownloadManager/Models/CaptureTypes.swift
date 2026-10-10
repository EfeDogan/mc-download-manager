import Foundation

/// File types the app captures (browser downloads, clipboard links). Grouped by category for the UI.
enum CaptureTypes {
    struct Group: Identifiable {
        let id: String
        let category: FileCategory
        let extensions: [String]
    }

    static let groups: [Group] = [
        Group(id: "compressed", category: .compressed, extensions: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "iso", "img", "cab"]),
        Group(id: "apps", category: .apps, extensions: ["dmg", "pkg", "exe", "msi", "apk", "ipa", "deb", "rpm", "appimage", "jar", "bin"]),
        Group(id: "video", category: .video, extensions: ["mp4", "m4v", "mkv", "webm", "mov", "avi", "flv", "wmv", "mpg", "mpeg", "m3u8", "3gp"]),
        Group(id: "music", category: .music, extensions: ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma", "aiff"]),
        Group(id: "document", category: .document, extensions: ["pdf", "epub", "mobi", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "csv"]),
        Group(id: "image", category: .image, extensions: ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff", "psd", "svg", "raw"]),
    ]

    /// Categories enabled by default on first launch.
    static let defaultGroupIDs: Set<String> = ["compressed", "apps", "video", "music", "document"]

    static func extensions(groupIDs: Set<String>, custom: String) -> [String] {
        var out: [String] = []
        for g in groups where groupIDs.contains(g.id) { out += g.extensions }
        for token in custom.lowercased().split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" || $0.isNewline }) {
            let e = token.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if !e.isEmpty, !out.contains(e) { out.append(e) }
        }
        return out
    }

    static func matches(url: URL, extensions: [String]) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !ext.isEmpty && extensions.contains(ext)
    }
}
