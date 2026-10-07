//! Tauri commands behind the Atype settings page ("個人化").
//!
//! Everything reads and writes `atype.json` through [`super::config`] and the
//! second-brain JSONL file written by [`super::brain`]; Handy's own settings
//! store is not touched.

use super::config::{self, AtypeConfig};
use chrono::{DateTime, Datelike, Local};
use serde::{Deserialize, Serialize};
use specta::Type;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use tauri::AppHandle;
use tauri_plugin_opener::OpenerExt;

/// Bounds for the LLM time budget accepted from the settings page.
pub const LLM_TIMEOUT_MIN_MS: u64 = 500;
pub const LLM_TIMEOUT_MAX_MS: u64 = 10_000;
pub const COMMAND_TIMEOUT_MAX_MS: u64 = 30_000;

/// [`AtypeConfig`] plus the folder the second brain actually writes to.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Type)]
pub struct AtypeConfigView {
    pub zh_post_enabled: bool,
    pub llm_timeout_ms: u64,
    pub llm_on_main_hotkey: bool,
    pub brain_enabled: bool,
    pub brain_dir: Option<String>,
    pub defaults_version: u32,
    pub dictionary: Vec<super::dictionary::DictEntry>,
    pub profile: String,
    pub command_timeout_ms: u64,
    /// `brain_dir` after defaults and `~/` expansion (empty if unknown).
    pub resolved_brain_dir: String,
}

/// Dictation totals from the second-brain `atype.jsonl`.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq, Type)]
pub struct AtypeStats {
    pub today_chars: u64,
    pub today_entries: u64,
    pub week_chars: u64,
    pub week_entries: u64,
    pub total_chars: u64,
    pub total_entries: u64,
}

fn view(app: &AppHandle, cfg: AtypeConfig) -> AtypeConfigView {
    let resolved = config::brain_dir(app, &cfg)
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default();
    AtypeConfigView {
        zh_post_enabled: cfg.zh_post_enabled,
        llm_timeout_ms: cfg.llm_timeout_ms,
        llm_on_main_hotkey: cfg.llm_on_main_hotkey,
        brain_enabled: cfg.brain_enabled,
        brain_dir: cfg.brain_dir,
        defaults_version: cfg.defaults_version,
        dictionary: cfg.dictionary,
        profile: cfg.profile,
        command_timeout_ms: cfg.command_timeout_ms,
        resolved_brain_dir: resolved,
    }
}

/// Clean up a config coming from the UI. `defaults_version` is managed by the
/// app, so the stored value always wins over whatever the client sent.
fn sanitize(mut incoming: AtypeConfig, stored: &AtypeConfig) -> AtypeConfig {
    incoming.llm_timeout_ms = incoming
        .llm_timeout_ms
        .clamp(LLM_TIMEOUT_MIN_MS, LLM_TIMEOUT_MAX_MS);
    incoming.brain_dir = incoming
        .brain_dir
        .map(|d| d.trim().to_string())
        .filter(|d| !d.is_empty());
    incoming.defaults_version = stored.defaults_version;
    incoming.shared_synced_at = stored.shared_synced_at.clone();
    incoming.dictionary = super::dictionary::sanitize(incoming.dictionary);
    incoming.command_timeout_ms = incoming
        .command_timeout_ms
        .clamp(LLM_TIMEOUT_MIN_MS, COMMAND_TIMEOUT_MAX_MS);
    incoming
}

#[tauri::command]
#[specta::specta]
pub fn get_atype_config(app: AppHandle) -> Result<AtypeConfigView, String> {
    super::shared::sync(&app);
    Ok(view(&app, config::load(&app)))
}

#[tauri::command]
#[specta::specta]
pub fn set_atype_config(app: AppHandle, config: AtypeConfig) -> Result<AtypeConfigView, String> {
    let stored = config::load(&app);
    let cfg = sanitize(config, &stored);
    let dictionary_changed = cfg.dictionary != stored.dictionary || cfg.profile != stored.profile;
    let brain_moved = cfg.brain_dir != stored.brain_dir;
    config::save(&app, &cfg);
    if brain_moved {
        // A different folder may already hold a newer shared file.
        super::shared::sync(&app);
    } else if dictionary_changed {
        super::shared::push(&app);
    }
    Ok(view(&app, config::load(&app)))
}

/// Open the second-brain folder in Finder, creating it first if needed.
#[tauri::command]
#[specta::specta]
pub fn open_brain_dir(app: AppHandle) -> Result<(), String> {
    let cfg = config::load(&app);
    let dir = config::brain_dir(&app, &cfg)
        .ok_or_else(|| "Could not resolve the second-brain folder".to_string())?;
    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create {}: {}", dir.display(), e))?;
    app.opener()
        .open_path(dir.to_string_lossy().to_string(), None::<String>)
        .map_err(|e| format!("Failed to open {}: {}", dir.display(), e))
}

#[tauri::command]
#[specta::specta]
pub fn get_atype_stats(app: AppHandle) -> Result<AtypeStats, String> {
    let cfg = config::load(&app);
    let Some(dir) = config::brain_dir(&app, &cfg) else {
        return Ok(AtypeStats::default());
    };
    let file = match std::fs::File::open(dir.join("atype.jsonl")) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(AtypeStats::default()),
        Err(e) => return Err(format!("Failed to read atype.jsonl: {}", e)),
    };
    let lines = BufReader::new(file).lines().map_while(Result::ok);
    Ok(aggregate(lines, Local::now()))
}

/// Run the dictionary and the deterministic Chinese layer on `text` (the
/// "試試看" box), the same local steps a dictation gets without the LLM.
#[tauri::command]
#[specta::specta]
pub fn atype_polish(app: AppHandle, text: String) -> String {
    local_polish(&text, &config::load(&app).dictionary)
}

fn local_polish(text: &str, dictionary: &[super::dictionary::DictEntry]) -> String {
    super::zh_post::polish(&super::dictionary::apply(text, dictionary))
}

fn count_chars(text: &str) -> u64 {
    text.chars().filter(|c| !c.is_whitespace()).count() as u64
}

/// Totals over the brain JSONL lines. Each dictation appends one `added`
/// line and possibly `updated` lines later (retry, LLM result): an entry is
/// counted once, with the text of its latest line. `updated` lines without a
/// matching `added` line are ignored, as are malformed lines.
///
/// Entries are keyed by `(id, timestamp)` so that history ids reused after a
/// database reset still count as separate dictations (an `updated` line keeps
/// the original entry's timestamp).
fn aggregate(lines: impl Iterator<Item = String>, now: DateTime<Local>) -> AtypeStats {
    let mut entries: HashMap<(i64, i64), (DateTime<Local>, u64)> = HashMap::new();
    for line in lines {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        let (Some(event), Some(id), Some(ts), Some(text)) = (
            v.get("event").and_then(|e| e.as_str()),
            v.get("id").and_then(|i| i.as_i64()),
            v.get("ts").and_then(|t| t.as_str()),
            v.get("text").and_then(|t| t.as_str()),
        ) else {
            continue;
        };
        let Ok(when) = DateTime::parse_from_rfc3339(ts) else {
            continue;
        };
        let when = when.with_timezone(&Local);
        let key = (id, when.timestamp());
        match event {
            "added" => {
                entries.insert(key, (when, count_chars(text)));
            }
            "updated" => {
                if let Some(slot) = entries.get_mut(&key) {
                    *slot = (when, count_chars(text));
                }
            }
            _ => {}
        }
    }

    let today = now.date_naive();
    let this_week = today.iso_week();
    let mut stats = AtypeStats::default();
    for (when, chars) in entries.values() {
        let day = when.date_naive();
        stats.total_entries += 1;
        stats.total_chars += chars;
        if day.iso_week() == this_week {
            stats.week_entries += 1;
            stats.week_chars += chars;
        }
        if day == today {
            stats.today_entries += 1;
            stats.today_chars += chars;
        }
    }
    stats
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn at(y: i32, m: u32, d: u32, h: u32, min: u32) -> DateTime<Local> {
        Local.with_ymd_and_hms(y, m, d, h, min, 0).single().unwrap()
    }

    fn line(event: &str, id: i64, when: DateTime<Local>, text: &str) -> String {
        serde_json::json!({
            "ts": when.to_rfc3339(),
            "event": event,
            "id": id,
            "text": text,
            "raw": text,
            "polished": false,
            "audio": "a.wav",
        })
        .to_string()
    }

    fn run(lines: Vec<String>, now: DateTime<Local>) -> AtypeStats {
        aggregate(lines.into_iter(), now)
    }

    // 2026-10-07 is a Wednesday; its week starts Monday 2026-10-05.
    fn now() -> DateTime<Local> {
        at(2026, 10, 7, 15, 0)
    }

    #[test]
    fn empty_input_is_all_zeros() {
        assert_eq!(run(vec![], now()), AtypeStats::default());
    }

    #[test]
    fn today_and_week_boundaries() {
        let lines = vec![
            line("added", 1, at(2026, 10, 7, 0, 5), "今天一"), // today, 3 chars
            line("added", 2, at(2026, 10, 7, 23, 50), "hi you"), // today, 5 chars
            line("added", 3, at(2026, 10, 6, 23, 59), "昨天"), // Tue, this week
            line("added", 4, at(2026, 10, 5, 0, 1), "週一"),   // Mon, this week
            line("added", 5, at(2026, 10, 4, 23, 59), "上週日"), // Sun, last week
            line("added", 6, at(2025, 10, 7, 12, 0), "去年同日"), // a year ago
        ];
        let s = run(lines, now());
        assert_eq!((s.today_entries, s.today_chars), (2, 3 + 5));
        assert_eq!((s.week_entries, s.week_chars), (4, 3 + 5 + 2 + 2));
        assert_eq!((s.total_entries, s.total_chars), (6, 3 + 5 + 2 + 2 + 3 + 4));
    }

    #[test]
    fn week_starting_monday_spans_a_year_boundary() {
        // Thu 2026-01-01; the ISO week began Mon 2025-12-29.
        let now = at(2026, 1, 1, 9, 0);
        let lines = vec![
            line("added", 1, at(2025, 12, 29, 8, 0), "一二"),
            line("added", 2, at(2025, 12, 28, 8, 0), "三四"),
        ];
        let s = run(lines, now);
        assert_eq!((s.week_entries, s.week_chars), (1, 2));
        assert_eq!(s.today_entries, 0);
        assert_eq!(s.total_entries, 2);
    }

    #[test]
    fn updated_overwrites_added_without_a_new_entry() {
        let when = at(2026, 10, 7, 10, 0);
        let lines = vec![
            line("added", 9, when, "呃 我想說"),
            line("updated", 9, when, "我想說一下"),
            // An update for an entry never added is ignored.
            line("updated", 10, when, "孤兒"),
        ];
        let s = run(lines, now());
        assert_eq!((s.today_entries, s.today_chars), (1, 5));
        assert_eq!((s.total_entries, s.total_chars), (1, 5));
    }

    #[test]
    fn reused_id_with_a_different_timestamp_is_a_separate_entry() {
        let lines = vec![
            line("added", 1, at(2026, 9, 1, 10, 0), "舊的"),
            line("added", 1, at(2026, 10, 7, 10, 0), "新的"),
        ];
        let s = run(lines, now());
        assert_eq!(s.total_entries, 2);
        assert_eq!(s.today_entries, 1);
    }

    #[test]
    fn malformed_lines_are_skipped() {
        let lines = vec![
            String::new(),
            "not json".to_string(),
            "{\"event\":\"added\"}".to_string(),
            r#"{"event":"added","id":1,"ts":"yesterday","text":"x"}"#.to_string(),
            r#"{"event":"added","id":"2","ts":"2026-10-07T10:00:00+08:00","text":"x"}"#.to_string(),
            line("deleted", 3, at(2026, 10, 7, 10, 0), "x"),
            line("added", 4, at(2026, 10, 7, 11, 0), "好 的"),
        ];
        let s = run(lines, now());
        assert_eq!((s.total_entries, s.total_chars), (1, 2));
        assert_eq!((s.today_entries, s.today_chars), (1, 2));
    }

    #[test]
    fn sanitize_clamps_trims_and_keeps_stored_defaults_version() {
        let stored = AtypeConfig {
            defaults_version: 1,
            ..AtypeConfig::default()
        };
        let incoming = AtypeConfig {
            llm_timeout_ms: 50_000,
            brain_dir: Some("   ".into()),
            defaults_version: 99,
            ..AtypeConfig::default()
        };
        let cfg = sanitize(incoming, &stored);
        assert_eq!(cfg.llm_timeout_ms, LLM_TIMEOUT_MAX_MS);
        assert_eq!(cfg.brain_dir, None);
        assert_eq!(cfg.defaults_version, 1);

        let incoming = AtypeConfig {
            llm_timeout_ms: 10,
            brain_dir: Some(" ~/Notes/brain ".into()),
            ..AtypeConfig::default()
        };
        let cfg = sanitize(incoming, &stored);
        assert_eq!(cfg.llm_timeout_ms, LLM_TIMEOUT_MIN_MS);
        assert_eq!(cfg.brain_dir.as_deref(), Some("~/Notes/brain"));
    }

    #[test]
    fn polish_command_wraps_zh_post() {
        assert_eq!(
            local_polish("我们明天下午3:30开会,地点在Costco旁边.", &[]),
            "我們明天下午 3:30 開會，地點在 Costco 旁邊。"
        );
        let dict = [super::super::dictionary::DictEntry {
            term: "iCloud".into(),
            aliases: vec!["iclo".into()],
        }];
        assert_eq!(local_polish("存在iclo上", &dict), "存在 iCloud 上");
    }
}
