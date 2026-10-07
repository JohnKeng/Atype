// Dictation history on this iPhone, plus the second-brain files.
//
// History: Application Support/history.json (newest first, capped).
// Second brain: in the shared folder (iCloud Drive/service-db/Atype when the
// user picked it), the iPhone writes its own files so it never fights the Mac
// over the same file in iCloud: `atype.iphone.jsonl` (same fields as the Mac's
// `atype.jsonl` plus "source") and `YYYY/YYYY-MM-DD.iphone.md`.

import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var raw: String
    var text: String
    var polished: Bool
    var command: Bool
    var promptName: String?
    var error: String?
}

@MainActor
final class HistoryStore {
    static let limit = 500
    private(set) var entries: [HistoryEntry] = []

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder.iso.decode([HistoryEntry].self, from: data) {
            entries = list
        }
    }

    func add(_ entry: HistoryEntry, brainFolder: URL?) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
        if let brainFolder { Self.appendToBrain(entry, folder: brainFolder) }
    }

    func delete(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder.iso.encode(entries) { try? data.write(to: url, options: .atomic) }
    }

    /// Characters dictated (no whitespace) and entries since `start`.
    func totals(since start: Date) -> (chars: Int, entries: Int) {
        let list = entries.filter { $0.date >= start }
        return (list.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }, list.count)
    }

    static func appendToBrain(_ e: HistoryEntry, folder: URL) {
        let fm = FileManager.default
        let day = DateFormatter.ymd.string(from: e.date)
        let year = String(day.prefix(4))
        let line: [String: Any] = [
            "ts": ISO8601DateFormatter.local.string(from: e.date),
            "event": "added",
            "id": e.id.uuidString,
            "text": e.text,
            "raw": e.raw,
            "polished": e.polished,
            "source": "iphone",
        ]
        var md = "- **\(DateFormatter.hm.string(from: e.date))** \(e.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if e.polished, e.raw.trimmingCharacters(in: .whitespacesAndNewlines) != e.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            md += "  - 原文：\(e.raw.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        }
        guard let json = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        let coordinator = NSFileCoordinator()
        var err: NSError?
        coordinator.coordinate(writingItemAt: folder, options: [], error: &err) { dir in
            append(Data(json) + Data("\n".utf8), to: dir.appendingPathComponent("atype.iphone.jsonl"))
            let dayDir = dir.appendingPathComponent(year)
            try? fm.createDirectory(at: dayDir, withIntermediateDirectories: true)
            let mdURL = dayDir.appendingPathComponent("\(day).iphone.md")
            if !fm.fileExists(atPath: mdURL.path) { md = "# \(day)（iPhone）\n\n" + md }
            append(Data(md.utf8), to: mdURL)
        }
    }

    private static func append(_ data: Data, to url: URL) {
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
extension JSONEncoder {
    static let iso: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}
extension DateFormatter {
    static let ymd: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static let hm: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f }()
}
extension ISO8601DateFormatter {
    nonisolated(unsafe) static let local: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.timeZone = .current; return f }()
}
