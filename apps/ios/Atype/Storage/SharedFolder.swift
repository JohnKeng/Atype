// Where the shared config and the second brain live. The user picks a folder
// in Files (normally iCloud Drive/service-db/Atype, the same one the Mac uses);
// we keep a security-scoped bookmark. Without one, the app's own Documents
// folder is used (visible in Files under "On My iPhone/Atype").

import Foundation

@MainActor
enum SharedFolder {
    private static let bookmarkKey = "sharedFolderBookmark"

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
}
