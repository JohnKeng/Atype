//! Second brain: every transcription is appended to plain files you own.
//!
//! Handy keeps its own SQLite history, but that table is pruned by retention
//! settings and is not meant as an archive. This module listens to the same
//! typed event Handy emits for its history view (`HistoryUpdatePayload`) and
//! writes two things to the brain folder (see `config::brain_dir`):
//!
//! - `atype.jsonl`: one JSON object per event, append-only, for tooling
//!   (search, embeddings, daily summaries).
//! - `YYYY/YYYY-MM-DD.md`: a human-readable daily log for Obsidian / Finder.
//!
//! Nothing in Handy is modified for this; the listener is registered once from
//! `atype::init`.

use crate::managers::history::{HistoryEntry, HistoryUpdatePayload};
use chrono::{DateTime, Local, TimeZone};
use log::{debug, warn};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::Path;
use tauri::AppHandle;
use tauri_specta::Event;

pub fn init(app: &AppHandle) {
    let handle = app.clone();
    let _event_id = HistoryUpdatePayload::listen(app, move |event| {
        let (entry, kind) = match event.payload {
            HistoryUpdatePayload::Added { entry } => (entry, "added"),
            HistoryUpdatePayload::Updated { entry } => (entry, "updated"),
            _ => return,
        };
        let cfg = super::config::load(&handle);
        if !cfg.brain_enabled {
            return;
        }
        let Some(dir) = super::config::brain_dir(&handle, &cfg) else {
            return;
        };
        let text = pasted_text(&entry, &cfg);
        match append(&dir, &entry, kind, &text) {
            Ok(()) => debug!(
                "Atype brain: {} entry {} → {}",
                kind,
                entry.id,
                dir.display()
            ),
            Err(e) => warn!("Atype brain: failed to write to {}: {}", dir.display(), e),
        }
    });
}

/// Handy stores seconds; be tolerant of milliseconds in case that changes.
fn local_time(ts: i64) -> DateTime<Local> {
    let secs = if ts > 100_000_000_000 { ts / 1000 } else { ts };
    Local
        .timestamp_opt(secs, 0)
        .single()
        .unwrap_or_else(Local::now)
}

/// The text that was actually pasted: the LLM result when there is one.
/// What was actually pasted: the LLM result when there is one, otherwise the
/// raw transcription after the same local steps the paste got (dictionary,
/// then the Chinese layer when it is on).
pub fn pasted_text(entry: &HistoryEntry, cfg: &super::config::AtypeConfig) -> String {
    if let Some(t) = entry
        .post_processed_text
        .as_deref()
        .filter(|t| !t.trim().is_empty())
    {
        return t.to_string();
    }
    let t = super::dictionary::apply(&entry.transcription_text, &cfg.dictionary);
    if cfg.zh_post_enabled {
        super::zh_post::polish(&t)
    } else {
        t
    }
}

pub fn jsonl_line(entry: &HistoryEntry, kind: &str, text: &str) -> String {
    let when = local_time(entry.timestamp);
    serde_json::json!({
        "ts": when.to_rfc3339(),
        "event": kind,
        "id": entry.id,
        "text": text,
        "raw": entry.transcription_text,
        "polished": entry.post_processed_text.is_some(),
        "audio": entry.file_name,
    })
    .to_string()
}

pub fn markdown_block(entry: &HistoryEntry, text: &str) -> String {
    let when = local_time(entry.timestamp);
    let mut block = format!("- **{}** {}\n", when.format("%H:%M"), text.trim());
    if entry.post_processed_text.is_some() && entry.transcription_text.trim() != text.trim() {
        block.push_str(&format!("  - 原文：{}\n", entry.transcription_text.trim()));
    }
    block
}

/// Append one event to the JSONL file and (for new entries) to the daily log.
pub fn append(dir: &Path, entry: &HistoryEntry, kind: &str, text: &str) -> std::io::Result<()> {
    create_dir_all(dir)?;
    let mut jsonl = OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join("atype.jsonl"))?;
    writeln!(jsonl, "{}", jsonl_line(entry, kind, text))?;

    if kind == "added" {
        let when = local_time(entry.timestamp);
        let day_dir = dir.join(when.format("%Y").to_string());
        create_dir_all(&day_dir)?;
        let day_file = day_dir.join(format!("{}.md", when.format("%Y-%m-%d")));
        let is_new = !day_file.exists();
        let mut md = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&day_file)?;
        if is_new {
            writeln!(md, "# {}\n", when.format("%Y-%m-%d"))?;
        }
        write!(md, "{}", markdown_block(entry, text))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(raw: &str, polished: Option<&str>) -> HistoryEntry {
        HistoryEntry {
            id: 7,
            file_name: "rec.wav".into(),
            timestamp: 1_790_000_000,
            saved: false,
            title: "t".into(),
            transcription_text: raw.into(),
            post_processed_text: polished.map(str::to_string),
            post_process_prompt: None,
            post_process_requested: polished.is_some(),
        }
    }

    #[test]
    fn jsonl_prefers_polished_text_and_keeps_raw() {
        let e = entry("呃我想說", Some("我想說"));
        let line = jsonl_line(&e, "added", &pasted_text(&e, &Default::default()));
        let v: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(v["text"], "我想說");
        assert_eq!(v["raw"], "呃我想說");
        assert_eq!(v["polished"], true);
        assert_eq!(v["id"], 7);
    }

    #[test]
    fn markdown_shows_raw_only_when_it_differs() {
        assert!(
            markdown_block(&entry("一樣", Some("一樣")), "一樣")
                .lines()
                .count()
                == 1
        );
        assert!(markdown_block(&entry("呃一樣", Some("一樣")), "一樣").contains("原文：呃一樣"));
    }

    #[test]
    fn without_llm_the_brain_gets_the_pasted_text_not_the_raw() {
        let cfg = super::super::config::AtypeConfig::default();
        assert_eq!(
            pasted_text(&entry("AI沒有生效嗎?", None), &cfg),
            "AI 沒有生效嗎？"
        );
    }

    #[test]
    fn append_writes_jsonl_and_daily_markdown() {
        let dir = tempfile::tempdir().unwrap();
        let e = entry("第一句", None);
        append(dir.path(), &e, "added", "第一句").unwrap();
        append(dir.path(), &e, "updated", "第一句").unwrap();
        let jsonl = std::fs::read_to_string(dir.path().join("atype.jsonl")).unwrap();
        assert_eq!(jsonl.lines().count(), 2);
        let when = local_time(e.timestamp);
        let md_path = dir
            .path()
            .join(when.format("%Y").to_string())
            .join(format!("{}.md", when.format("%Y-%m-%d")));
        let md = std::fs::read_to_string(md_path).unwrap();
        assert!(md.starts_with("# "));
        assert_eq!(
            md.matches("第一句").count(),
            1,
            "updated must not duplicate the daily log"
        );
    }
}
