// Deterministic Chinese layer: the part of the pipeline that must not depend
// on an LLM "remembering" the rules. Port of the Mac app's `atype/zh_post.rs`;
// the tests use the same cases.
//
// 1. Simplified → Traditional (Taiwan phrases) with OpenCC s2twp, gated so
//    text that is already Traditional is left alone.
// 2. Full-width punctuation inside Chinese sentences (，。？！：；), keeping
//    decimals, times and URLs intact.
// 3. A half-width space between CJK and Latin/digits (pangu style).

import Foundation
import OpenCC

public enum ZhPost {
    nonisolated(unsafe) private static let s2t = try? ChineseConverter(options: [.traditionalize])
    nonisolated(unsafe) private static let s2twp = try? ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])

    /// Characters OpenCC treats as Simplified that are also ordinary
    /// Traditional characters in Taiwan usage; alone they never trigger a pass.
    private static let ambiguous: Set<Character> = Set(
        "台着么云后干发里余系面志丑斗谷松几只向借冲准复并布才采范丰合回伙姜据卷克困夸累了蒙千秋曲舍胜术叹坛体同涂团万为咸叶佣游于郁愿岳征症制致钟周朱筑兹总钻划签吁咽弦"
    )

    /// True when `text` has a character that is unambiguously Simplified.
    public static func hasSimplified(_ text: String) -> Bool {
        guard let s2t else { return false }
        return text.contains { c in
            isCJK(c) && !ambiguous.contains(c) && s2t.convert(String(c)) != String(c)
        }
    }

    /// Simplified → Traditional (Taiwan phrases), only when needed.
    public static func toTraditional(_ text: String) -> String {
        guard hasSimplified(text), let s2twp else { return text }
        return s2twp.convert(text)
    }

    public static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF,
             0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static let fullwidthPunct: Set<Character> = Set("，。？！：；、（）「」『』《》〈〉【】…—")
    private static let sentenceEnd: Set<Character> = Set("。？！；")

    private static func isAsciiAlnum(_ c: Character?) -> Bool {
        guard let c, c.isASCII else { return false }
        return c.isLetter || c.isNumber
    }

    /// Latin side for spacing: ASCII letters/digits and symbols that glue to them.
    private static func isLatinSide(_ c: Character) -> Bool {
        isAsciiAlnum(c) || "%$#@+&=".contains(c)
    }

    /// Convert ASCII punctuation to full-width inside Chinese sentences.
    public static func fullwidthPunctuation(_ text: String) -> String {
        let chars = Array(text)
        var out: [Character] = []
        out.reserveCapacity(chars.count + 8)
        var sentenceHasCJK = false
        var i = 0
        func trimTrailingSpaces() { while out.last == " " { out.removeLast() } }
        while i < chars.count {
            let c = chars[i]
            let prev = out.last(where: { !$0.isWhitespace })
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let prevCJK = prev.map { isCJK($0) || fullwidthPunct.contains($0) } ?? false
            let nextAlnum = isAsciiAlnum(next)
            let prevAlnum = isAsciiAlnum(prev)
            if isCJK(c) { sentenceHasCJK = true }

            var replacement: Character?
            switch c {
            case "," where !(prevAlnum && nextAlnum) && (prevCJK || sentenceHasCJK): replacement = "，"
            case ";" where prevCJK || sentenceHasCJK: replacement = "；"
            case "?" where prevCJK || sentenceHasCJK: replacement = "？"
            case "!" where prevCJK || sentenceHasCJK: replacement = "！"
            case ":" where prevCJK && !nextAlnum: replacement = "："
            case "." where !(prevAlnum && nextAlnum) && (prevCJK || (sentenceHasCJK && !nextAlnum)): replacement = "。"
            default: replacement = nil
            }

            if let fw = replacement ?? (fullwidthPunct.contains(c) ? c : nil) {
                trimTrailingSpaces()
                out.append(fw)
                while i + 1 < chars.count, chars[i + 1] == " " { i += 1 }
                if sentenceEnd.contains(fw) { sentenceHasCJK = false }
            } else {
                if c == "\n" { sentenceHasCJK = false }
                out.append(c)
            }
            i += 1
        }
        return String(out)
    }

    /// One half-width space between CJK and Latin/digits, both directions.
    public static func panguSpacing(_ text: String) -> String {
        var out = ""
        var prev: Character?
        for c in text {
            if let p = prev, (isCJK(p) && isLatinSide(c)) || (isLatinSide(p) && isCJK(c)) {
                out.append(" ")
            }
            out.append(c)
            prev = c
        }
        return out
    }

    private static func collapseSpaces(_ text: String) -> String {
        var out = ""
        var lastSpace = false
        for c in text {
            if c == " " {
                if !lastSpace { out.append(c) }
                lastSpace = true
            } else {
                out.append(c)
                lastSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drop the full stop that ends the whole text (a recognizer adds one to
    /// every take), so text dictated into the middle of a sentence, or as an
    /// addition, does not carry a stray 。. ？ and ！ stay: they carry meaning.
    public static func dropFinalPeriod(_ text: String) -> String {
        var t = text
        while let last = t.last, last.isWhitespace { t.removeLast() }
        if t.hasSuffix("。") { t.removeLast() }
        return t
    }

    /// The whole deterministic layer, in order.
    public static func polish(_ text: String) -> String {
        collapseSpaces(panguSpacing(fullwidthPunctuation(toTraditional(text))))
    }
}
