//! Deterministic Chinese layer: the part of the pipeline that must not depend
//! on an LLM "remembering" the rules.
//!
//! 1. Simplified → Traditional (Taiwan phrases) with OpenCC `s2twp`, gated so
//!    text that is already Traditional is left alone.
//! 2. Full-width punctuation inside Chinese sentences (，。？！：；), keeping
//!    decimals, times and URLs intact.
//! 3. A half-width space between CJK and Latin/digits (pangu style).
//!
//! Runs on every result: on the LLM output when there is one, on the raw
//! transcription when the LLM is off, failed or timed out.

use ferrous_opencc::{config::BuiltinConfig, OpenCC};
use std::sync::OnceLock;

static S2T: OnceLock<Option<OpenCC>> = OnceLock::new();
static S2TWP: OnceLock<Option<OpenCC>> = OnceLock::new();

fn converter(
    cfg: BuiltinConfig,
    cell: &'static OnceLock<Option<OpenCC>>,
) -> Option<&'static OpenCC> {
    cell.get_or_init(|| OpenCC::from_config(cfg).ok()).as_ref()
}

/// Characters that OpenCC treats as Simplified but that are also ordinary
/// Traditional characters in Taiwan usage. They must not, on their own, trigger
/// a conversion pass (台北, 著名, 什麼, 後面, 裡面 are all fine as written).
const AMBIGUOUS: &[char] = &[
    '台', '着', '么', '云', '后', '干', '发', '里', '余', '系', '面', '志', '丑', '斗', '谷', '松',
    '几', '只', '向', '借', '冲', '准', '复', '并', '布', '才', '采', '范', '丰', '合', '回', '伙',
    '姜', '据', '卷', '克', '困', '夸', '累', '了', '蒙', '千', '秋', '曲', '舍', '胜', '术', '叹',
    '坛', '体', '同', '涂', '团', '万', '为', '咸', '叶', '佣', '游', '于', '郁', '愿', '岳', '征',
    '症', '制', '致', '钟', '周', '朱', '筑', '兹', '总', '钻', '划', '划', '签', '吁', '咽', '弦',
];

/// True when `text` contains a character that is unambiguously Simplified.
pub fn has_simplified(text: &str) -> bool {
    let Some(s2t) = converter(BuiltinConfig::S2t, &S2T) else {
        return false;
    };
    text.chars()
        .filter(|c| is_cjk(*c) && !AMBIGUOUS.contains(c))
        .any(|c| {
            let mut buf = [0u8; 4];
            let s: &str = c.encode_utf8(&mut buf);
            s2t.convert(s) != s
        })
}

/// Simplified → Traditional (Taiwan phrases). Only converts when
/// [`has_simplified`] says there is something to convert.
pub fn to_traditional(text: &str) -> String {
    if !has_simplified(text) {
        return text.to_string();
    }
    match converter(BuiltinConfig::S2twp, &S2TWP) {
        Some(c) => c.convert(text),
        None => text.to_string(),
    }
}

pub fn is_cjk(c: char) -> bool {
    matches!(
        c as u32,
        0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0xF900..=0xFAFF | 0x20000..=0x2A6DF
            | 0x3040..=0x30FF | 0xAC00..=0xD7AF
    )
}

fn is_fullwidth_punct(c: char) -> bool {
    matches!(
        c,
        '，' | '。'
            | '？'
            | '！'
            | '：'
            | '；'
            | '、'
            | '（'
            | '）'
            | '「'
            | '」'
            | '『'
            | '』'
            | '《'
            | '》'
            | '〈'
            | '〉'
            | '【'
            | '】'
            | '…'
            | '—'
    )
}

/// Latin-side characters for spacing purposes: ASCII letters/digits plus the
/// symbols that commonly glue to them (10%, $5, #tag, @name, C++).
fn is_latin_side(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '%' | '$' | '#' | '@' | '+' | '&' | '=')
}

/// Convert ASCII punctuation to full-width inside Chinese sentences.
pub fn fullwidth_punct(text: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len() + 8);
    // Whether the current sentence (since the last terminator) contains CJK.
    let mut sentence_has_cjk = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let prev = out.chars().rev().find(|p| !p.is_whitespace());
        let next = chars.get(i + 1).copied();
        let prev_cjk = prev.is_some_and(|p| is_cjk(p) || is_fullwidth_punct(p));
        let next_alnum = next.is_some_and(|n| n.is_ascii_alphanumeric());
        let prev_alnum = prev.is_some_and(|p| p.is_ascii_alphanumeric());

        if is_cjk(c) {
            sentence_has_cjk = true;
        }

        let replacement = match c {
            ',' if !(prev_alnum && next_alnum) && (prev_cjk || sentence_has_cjk) => Some('，'),
            ';' if prev_cjk || sentence_has_cjk => Some('；'),
            '?' if prev_cjk || sentence_has_cjk => Some('？'),
            '!' if prev_cjk || sentence_has_cjk => Some('！'),
            // 3:30 stays; 「注意:」 and 「注意: 以下」 become full-width.
            ':' if prev_cjk && !next_alnum => Some('：'),
            // 3.5 and example.com stay; a sentence-final period in a Chinese
            // sentence becomes 。 even after a Latin word (…了 code.).
            '.' if !(prev_alnum && next_alnum)
                && (prev_cjk || (sentence_has_cjk && !next_alnum)) =>
            {
                Some('。')
            }
            _ => None,
        };

        match replacement {
            Some(fw) => {
                // No spaces around full-width punctuation.
                while out.ends_with(' ') {
                    out.pop();
                }
                out.push(fw);
                while matches!(chars.get(i + 1), Some(' ')) {
                    i += 1;
                }
                if matches!(fw, '。' | '？' | '！' | '；') {
                    sentence_has_cjk = false;
                }
            }
            None if is_fullwidth_punct(c) => {
                // Existing full-width punctuation: also no spaces around it.
                while out.ends_with(' ') {
                    out.pop();
                }
                out.push(c);
                while matches!(chars.get(i + 1), Some(' ')) {
                    i += 1;
                }
                if matches!(c, '。' | '？' | '！' | '；') {
                    sentence_has_cjk = false;
                }
            }
            None => {
                if c == '\n' {
                    sentence_has_cjk = false;
                }
                out.push(c);
            }
        }
        i += 1;
    }
    out
}

/// Insert one half-width space between CJK and Latin/digits (both directions).
pub fn pangu_spacing(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 16);
    let mut prev: Option<char> = None;
    for c in text.chars() {
        if let Some(p) = prev {
            let boundary = (is_cjk(p) && is_latin_side(c)) || (is_latin_side(p) && is_cjk(c));
            if boundary {
                out.push(' ');
            }
        }
        out.push(c);
        prev = Some(c);
    }
    out
}

fn collapse_spaces(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last_space = false;
    for c in text.chars() {
        if c == ' ' {
            if !last_space {
                out.push(c);
            }
            last_space = true;
        } else {
            out.push(c);
            last_space = false;
        }
    }
    out.trim().to_string()
}

/// The whole deterministic layer, in order.
pub fn polish(text: &str) -> String {
    let t = to_traditional(text);
    let t = fullwidth_punct(&t);
    let t = pangu_spacing(&t);
    collapse_spaces(&t)
}

/// Drop the full stop that ends the whole text (a recognizer adds one to
/// every take), so text dictated into the middle of a sentence, or as an
/// addition, does not carry a stray 。. ？ and ！ stay: they carry meaning.
pub fn drop_final_period(text: &str) -> String {
    let t = text.trim_end();
    t.strip_suffix('。').unwrap_or(t).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn final_period_is_dropped_others_kept() {
        assert_eq!(drop_final_period("好的，我知道了。"), "好的，我知道了");
        assert_eq!(drop_final_period("第一句。第二句。\n"), "第一句。第二句");
        assert_eq!(drop_final_period("你用過 GitHub？"), "你用過 GitHub？");
        assert_eq!(drop_final_period("太好了！"), "太好了！");
        assert_eq!(drop_final_period("沒有句號"), "沒有句號");
        assert_eq!(drop_final_period(""), "");
    }

    #[test]
    fn simplified_is_converted_with_taiwan_phrases() {
        // s2twp = characters + Taiwan vocabulary (软件→軟體, 网络→網路, 鼠标→滑鼠).
        assert_eq!(polish("这个软件的网络很好"), "這個軟體的網路很好");
        assert_eq!(polish("用鼠标点一下"), "用滑鼠點一下");
    }

    #[test]
    fn traditional_text_is_left_alone() {
        for s in [
            "台北的軟體很好",
            "著名的後面裡面",
            "什麼時候",
            "我們明天開會",
        ] {
            assert!(!has_simplified(s), "{s} wrongly flagged as simplified");
            assert_eq!(polish(s), s);
        }
    }

    #[test]
    fn llm_leak_in_a_traditional_sentence_is_fixed() {
        assert_eq!(polish("我們的软件要更新"), "我們的軟體要更新");
    }

    #[test]
    fn punctuation_and_spacing_example_from_the_plan() {
        assert_eq!(
            polish("我们明天下午3:30开会,地点在Costco旁边的路易莎."),
            "我們明天下午 3:30 開會，地點在 Costco 旁邊的路易莎。"
        );
    }

    #[test]
    fn numbers_urls_and_english_sentences_are_untouched() {
        assert_eq!(
            polish("版本是3.5,網址是example.com"),
            "版本是 3.5，網址是 example.com"
        );
        assert_eq!(
            polish("Hello, world. How are you?"),
            "Hello, world. How are you?"
        );
        assert_eq!(polish("總共1,000元"), "總共 1,000 元");
    }

    #[test]
    fn chinese_sentence_ending_after_latin_word() {
        assert_eq!(polish("我今天push了code."), "我今天 push 了 code。");
        assert_eq!(polish("你用過GitHub?"), "你用過 GitHub？");
    }

    #[test]
    fn spaces_around_fullwidth_punctuation_are_removed() {
        assert_eq!(polish("好的 ， 我知道了 。"), "好的，我知道了。");
        assert_eq!(polish("iPhone很好 ,  真的"), "iPhone 很好，真的");
    }

    #[test]
    fn percent_and_symbols_space_like_pangu() {
        assert_eq!(polish("有10%的人用C++寫"), "有 10% 的人用 C++ 寫");
    }
}
