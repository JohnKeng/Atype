//! Personal dictionary: fix names and terms the recogniser keeps mishearing.
//!
//! Runs locally on the raw transcription, before the LLM and the Chinese
//! layer, so it works with the LLM off. Two kinds of match:
//! - **Aliases**: wrong spellings the user listed (`iclo` → `iCloud`).
//!   ASCII aliases match case-insensitively on word boundaries; anything
//!   with Chinese in it matches as a plain substring. The term itself is an
//!   implicit ASCII alias, so `icloud` becomes `iCloud`.
//! - **Pinyin**: an all-Chinese term (2+ characters) also replaces any run of
//!   Chinese characters that sounds the same, tones ignored and the Taiwanese
//!   mergers folded (zh/z, ch/c, sh/s, ing/in, eng/en): 城市馬 → 程式碼
//!   without listing it. Every reading of a heteronym counts.
//!
//! The terms are also handed to the LLM as `<known_terms>`.

use pinyin::ToPinyinMulti;
use serde::{Deserialize, Serialize};
use specta::Type;

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, Type)]
#[serde(default)]
pub struct DictEntry {
    /// The correct spelling, e.g. `iCloud`, `程式碼`.
    pub term: String,
    /// Known wrong spellings, e.g. `iclo`, `城市馬`.
    pub aliases: Vec<String>,
}

/// Trim, drop empty terms and aliases, drop aliases equal to their term and
/// duplicate aliases. Order is kept.
pub fn sanitize(entries: Vec<DictEntry>) -> Vec<DictEntry> {
    entries
        .into_iter()
        .filter_map(|e| {
            let term = e.term.trim().to_string();
            if term.is_empty() {
                return None;
            }
            let mut aliases: Vec<String> = Vec::new();
            for a in e.aliases {
                let a = a.trim().to_string();
                if !a.is_empty() && a != term && !aliases.contains(&a) {
                    aliases.push(a);
                }
            }
            Some(DictEntry { term, aliases })
        })
        .collect()
}

fn is_han(c: char) -> bool {
    matches!(c as u32, 0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0xF900..=0xFAFF | 0x20000..=0x2FA1F)
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric()
}

/// Toneless pinyin with the Taiwanese mergers folded, for comparison only.
fn fold(syllable: &str) -> String {
    let mut s = syllable.to_string();
    for (from, to) in [("zh", "z"), ("ch", "c"), ("sh", "s")] {
        if let Some(rest) = s.strip_prefix(from) {
            s = format!("{to}{rest}");
            break;
        }
    }
    if let Some(stem) = s.strip_suffix("ng") {
        if stem.ends_with('i') || stem.ends_with('e') {
            s = format!("{stem}n");
        }
    }
    s
}

fn readings(c: char) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    if let Some(multi) = c.to_pinyin_multi() {
        for p in multi {
            let f = fold(p.plain());
            if !out.contains(&f) {
                out.push(f);
            }
        }
    }
    out
}

struct Matcher {
    /// What gets inserted.
    term: String,
    kind: Kind,
}

enum Kind {
    /// Case-insensitive, on ASCII word boundaries.
    Ascii(Vec<char>),
    /// Exact substring.
    Exact(Vec<char>),
    /// Same folded pinyin, one reading set per character.
    Sound(Vec<Vec<String>>),
}

impl Matcher {
    fn len(&self) -> usize {
        match &self.kind {
            Kind::Ascii(p) | Kind::Exact(p) => p.len(),
            Kind::Sound(r) => r.len(),
        }
    }

    /// Whether this matcher matches `text` at `i` (and would change it).
    fn matches_at(&self, text: &[char], i: usize) -> bool {
        let n = self.len();
        if n == 0 || i + n > text.len() {
            return false;
        }
        let window = &text[i..i + n];
        match &self.kind {
            Kind::Ascii(p) => {
                let before_ok = i == 0 || !is_word_char(text[i - 1]);
                let after_ok = i + n == text.len() || !is_word_char(text[i + n]);
                before_ok
                    && after_ok
                    && window.iter().zip(p).all(|(a, b)| a.eq_ignore_ascii_case(b))
            }
            Kind::Exact(p) => window == p.as_slice(),
            Kind::Sound(r) => {
                window.iter().all(|&c| is_han(c))
                    && window
                        .iter()
                        .zip(r)
                        .all(|(&c, wanted)| readings(c).iter().any(|got| wanted.contains(got)))
            }
        }
    }
}

fn matchers(entries: &[DictEntry]) -> Vec<Matcher> {
    let mut out = Vec::new();
    for e in entries {
        let term = e.term.trim();
        if term.is_empty() {
            continue;
        }
        let mut patterns: Vec<&str> = e.aliases.iter().map(|a| a.trim()).collect();
        if term.is_ascii() {
            patterns.push(term);
        }
        for p in patterns.into_iter().filter(|p| !p.is_empty()) {
            let chars: Vec<char> = p.chars().collect();
            let kind = if p.is_ascii() {
                Kind::Ascii(chars)
            } else {
                Kind::Exact(chars)
            };
            out.push(Matcher {
                term: term.to_string(),
                kind,
            });
        }
        let term_chars: Vec<char> = term.chars().collect();
        if term_chars.len() >= 2 && term_chars.iter().all(|&c| is_han(c)) {
            let r: Vec<Vec<String>> = term_chars.iter().map(|&c| readings(c)).collect();
            if r.iter().all(|x| !x.is_empty()) {
                out.push(Matcher {
                    term: term.to_string(),
                    kind: Kind::Sound(r),
                });
            }
        }
    }
    // Longest pattern first; listed aliases before sound matches of equal length.
    out.sort_by(|a, b| {
        b.len().cmp(&a.len()).then_with(|| {
            let rank = |m: &Matcher| matches!(m.kind, Kind::Sound(_)) as u8;
            rank(a).cmp(&rank(b))
        })
    });
    out
}

/// Replace misheard spellings in `text` with the dictionary terms.
pub fn apply(text: &str, entries: &[DictEntry]) -> String {
    if entries.is_empty() {
        return text.to_string();
    }
    let ms = matchers(entries);
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < chars.len() {
        if let Some(m) = ms.iter().find(|m| m.matches_at(&chars, i)) {
            out.push_str(&m.term);
            i += m.len();
        } else {
            out.push(chars[i]);
            i += 1;
        }
    }
    out
}

/// Block appended to the LLM prompt, or `None` with an empty dictionary.
pub fn known_terms_prompt(entries: &[DictEntry]) -> Option<String> {
    let terms: Vec<&str> = entries
        .iter()
        .map(|e| e.term.trim())
        .filter(|t| !t.is_empty())
        .collect();
    if terms.is_empty() {
        return None;
    }
    Some(format!(
        "\n<known_terms>\n{}\n</known_terms>\n以上是使用者常用的專有名詞與用語。辨識結果裡發音相近或拼法接近的字詞，請改成這些詞的正確寫法。\n",
        terms.join("、")
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn e(term: &str, aliases: &[&str]) -> DictEntry {
        DictEntry {
            term: term.into(),
            aliases: aliases.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn dict() -> Vec<DictEntry> {
        vec![
            e("iCloud", &["iclo", "icrow", "icl", "ic克l芯"]),
            e("程式碼", &[]),
            e("Typeless", &[]),
        ]
    }

    #[test]
    fn listed_aliases_are_replaced() {
        let d = dict();
        assert_eq!(
            apply("測試一下錄音是否有丟在ic克l芯的位置。", &d),
            "測試一下錄音是否有丟在iCloud的位置。"
        );
        assert_eq!(apply("在icrow的新位置", &d), "在iCloud的新位置");
        assert_eq!(apply("然後iclo上的儲存位置", &d), "然後iCloud上的儲存位置");
        assert_eq!(apply("ICLO", &d), "iCloud");
    }

    #[test]
    fn ascii_aliases_respect_word_boundaries() {
        let d = dict();
        assert_eq!(apply("include", &d), "include");
        assert_eq!(apply("iclone", &d), "iclone");
        assert_eq!(apply("可以取代typeless嗎？", &d), "可以取代Typeless嗎？");
    }

    #[test]
    fn homophones_are_found_by_pinyin() {
        let d = dict();
        assert_eq!(
            apply("並且城市馬那邊看需不需要改", &d),
            "並且程式碼那邊看需不需要改"
        );
        // Taiwanese merger: zh/z, sh/s.
        assert_eq!(apply("成四碼", &d), "程式碼");
    }

    #[test]
    fn unrelated_text_is_untouched() {
        let d = dict();
        for s in ["我們明天下午開會", "城市很大", "程式", ""] {
            assert_eq!(apply(s, &d), s);
        }
        assert_eq!(apply("anything", &[]), "anything");
    }

    #[test]
    fn sanitize_cleans_entries() {
        let got = sanitize(vec![
            e("  iCloud ", &[" iclo", "", "iclo", "iCloud"]),
            e("   ", &["x"]),
        ]);
        assert_eq!(got, vec![e("iCloud", &["iclo"])]);
    }

    #[test]
    fn known_terms_block() {
        assert_eq!(known_terms_prompt(&[]), None);
        let p = known_terms_prompt(&dict()).unwrap();
        assert!(p.contains("iCloud、程式碼、Typeless"));
    }
}
