// Where the shared config and the second brain live. The user picks a folder
// in Files (normally iCloud Drive/service-db/Atype, the same one the Mac uses);
// we keep a security-scoped bookmark. Without one, the app's own Documents
// folder is used (visible in Files under "On My iPhone/Atype").

import Foundation

@MainActor
enum SharedFolder {
    private static let bookmarkKey = "sharedFolderBookmark"

    /// Default: the same folder the Mac uses. iOS still needs the user to
    /// grant it once, so the picker opens right there.
    static let defaultICloudURL = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/service-db/Atype", isDirectory: true)
    static let defaultDisplay = "iCloud 雲碟/service-db/Atype"

    /// "iCloud 雲碟/…" for iCloud Drive paths, otherwise the folder name.
    static func displayPath(_ url: URL) -> String {
        let p = url.path
        if let r = p.range(of: "com~apple~CloudDocs/") { return "iCloud 雲碟/" + p[r.upperBound...] }
        return url.lastPathComponent
    }

    static var localFallback: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The picked folder (with access started), or nil.
    static func picked() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return url
    }

    static var current: URL { picked() ?? localFallback }

    static func pick(_ url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: bookmarkKey) }

    /// True when `file` is on this device (or does not exist anywhere). When
    /// iCloud only has a placeholder, start the download and return false.
    static func ensureDownloaded(_ file: URL) -> Bool {
        let fm = FileManager.default
        let placeholder = file.deletingLastPathComponent()
            .appendingPathComponent("." + file.lastPathComponent + ".icloud")
        if let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = values.ubiquitousItemDownloadingStatus {
            if status == .current { return true }
            try? fm.startDownloadingUbiquitousItem(at: file)
            return false
        }
        if fm.fileExists(atPath: placeholder.path) {
            try? fm.startDownloadingUbiquitousItem(at: file)
            return false
        }
        return true
    }
}
