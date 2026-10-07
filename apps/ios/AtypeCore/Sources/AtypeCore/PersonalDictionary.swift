// Personal dictionary: fix names and terms the recogniser keeps mishearing.
// Port of the Mac app's `atype/dictionary.rs` (same matching rules and tests).
//
// - Aliases: wrong spellings the user listed (`iclo` → `iCloud`). ASCII aliases
//   match case-insensitively on word boundaries; anything with Chinese in it
//   matches as a plain substring. The term itself is an implicit ASCII alias.
// - Pinyin: an all-Chinese term (2+ characters) also replaces any run of
//   Chinese characters that sounds the same, tones ignored and the Taiwanese
//   mergers folded (zh/z, ch/c, sh/s, ing/in, eng/en): 城市馬 → 程式碼.
//   Readings come from the system Mandarin transliteration (one per character).

import Foundation

public struct DictEntry: Codable, Hashable, Sendable {
    public var term: String
    public var aliases: [String]
    public init(term: String, aliases: [String] = []) {
        self.term = term
        self.aliases = aliases
    }
}

public enum PersonalDictionary {
    /// Trim, drop empty terms/aliases, aliases equal to the term and duplicates.
    public static func sanitize(_ entries: [DictEntry]) -> [DictEntry] {
        entries.compactMap { e in
            let term = e.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            var aliases: [String] = []
            for a in e.aliases.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !a.isEmpty && a != term && !aliases.contains(a) {
                aliases.append(a)
            }
            return DictEntry(term: term, aliases: aliases)
        }
    }

    static func isHan(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    /// Toneless pinyin with the Taiwanese mergers folded.
    static func fold(_ syllable: String) -> String {
        var s = syllable.lowercased()
        for (from, to) in [("zh", "z"), ("ch", "c"), ("sh", "s")] where s.hasPrefix(from) {
            s = to + s.dropFirst(from.count)
            break
        }
        if s.hasSuffix("ing") || s.hasSuffix("eng") {
            s.removeLast()  // ng → n
        }
        return s
    }

    nonisolated(unsafe) private static var readingCache: [Character: String] = [:]
    private static let cacheLock = NSLock()

    static func reading(_ c: Character) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let r = readingCache[c] { return r }
        guard let latin = String(c).applyingTransform(.mandarinToLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .trimmingCharacters(in: .whitespaces),
            !latin.isEmpty, latin != String(c)
        else { return nil }
        let r = fold(latin)
        readingCache[c] = r
        return r
    }

    private enum Kind {
        case ascii([Character])
        case exact([Character])
        case sound([String])
    }

    private struct Matcher {
        let term: String
        let kind: Kind
        var length: Int {
            switch kind {
            case .ascii(let p), .exact(let p): return p.count
            case .sound(let r): return r.count
            }
        }
        var isSound: Bool { if case .sound = kind { return true } else { return false } }

        func matches(_ text: [Character], at i: Int) -> Bool {
            let n = length
            guard n > 0, i + n <= text.count else { return false }
            let window = text[i..<(i + n)]
            switch kind {
            case .ascii(let p):
                let beforeOK = i == 0 || !PersonalDictionary.isWordChar(text[i - 1])
                let afterOK = i + n == text.count || !PersonalDictionary.isWordChar(text[i + n])
                return beforeOK && afterOK
                    && zip(window, p).allSatisfy { $0.lowercased() == $1.lowercased() }
            case .exact(let p):
                return Array(window) == p
            case .sound(let r):
                return window.allSatisfy(PersonalDictionary.isHan)
                    && zip(window, r).allSatisfy { PersonalDictionary.reading($0) == $1 }
            }
        }
    }

    private static func matchers(_ entries: [DictEntry]) -> [Matcher] {
        var out: [Matcher] = []
        for e in entries {
            let term = e.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            var patterns = e.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if term.allSatisfy(\.isASCII) { patterns.append(term) }
            for p in patterns where !p.isEmpty {
                let chars = Array(p)
                out.append(Matcher(term: term, kind: p.allSatisfy(\.isASCII) ? .ascii(chars) : .exact(chars)))
            }
            let termChars = Array(term)
            if termChars.count >= 2, termChars.allSatisfy(isHan) {
                let r = termChars.compactMap(reading)
                if r.count == termChars.count {
                    out.append(Matcher(term: term, kind: .sound(r)))
                }
            }
        }
        // Longest first; listed aliases before sound matches of equal length.
        return out.sorted { a, b in
            a.length != b.length ? a.length > b.length : (!a.isSound && b.isSound)
        }
    }

    /// Replace misheard spellings in `text` with the dictionary terms.
    public static func apply(_ text: String, _ entries: [DictEntry]) -> String {
        guard !entries.isEmpty else { return text }
        let ms = matchers(entries)
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            if let m = ms.first(where: { $0.matches(chars, at: i) }) {
                out += m.term
                i += m.length
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    /// Block appended to the LLM prompt, or nil with an empty dictionary.
    public static func knownTermsPrompt(_ entries: [DictEntry]) -> String? {
        let terms = entries.map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return "\n<known_terms>\n\(terms.joined(separator: "、"))\n</known_terms>\n以上是使用者常用的專有名詞與用語。辨識結果裡發音相近或拼法接近的字詞，請改成這些詞的正確寫法。\n"
    }
}
