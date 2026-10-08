// A small shared log (App Group container) so a test on the phone can be
// read back with `devicectl device copy from --domain-type appGroupDataContainer`.

import Foundation

enum DebugLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Bridge.group)?.appendingPathComponent("debug.log")
    }

    static func log(_ who: String, _ message: String) {
        guard let url else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "\(formatter.string(from: Date())) [\(who)] \(message)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
            // Keep the previous 1 MB as debug.old.log instead of wiping it.
            if (try? h.offset()) ?? 0 > 1_000_000 {
                try? h.close()
                let old = url.deletingLastPathComponent().appendingPathComponent("debug.old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
