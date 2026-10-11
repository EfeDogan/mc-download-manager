import SwiftUI

// Entry point (replaces @main): see App.swift for why two App types exist.
if #available(macOS 15.0, *) {
    DownloadManagerApp15.main()
} else {
    DownloadManagerApp.main()
}
