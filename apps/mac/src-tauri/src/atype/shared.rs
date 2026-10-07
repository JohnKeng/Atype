//! Prompts and dictionary shared with the iPhone through iCloud Drive.
//!
//! `atype-shared.json` lives in the second-brain folder (iCloud Drive /
//! service-db/Atype by default) and has the same shape as the iPhone's
//! `SharedConfig` (apps/ios/AtypeCore). The newest `updated_at` wins:
//! - [`sync`] (startup, before each dictation, when the settings page loads)
//!   applies a file newer than the last sync, or creates the file from the
//!   local state when it does not exist yet;
//! - [`push`] (after any local prompt or dictionary change) writes the local
//!   state with a fresh timestamp.
//!
//! Secrets (API keys) are never written here.

use super::config::{self, AtypeConfig};
use super::dictionary::{self, DictEntry};
use crate::settings::{get_settings, write_settings, AppSettings, LLMPrompt};
use chrono::{DateTime, SecondsFormat, Utc};
use log::{info, warn};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tauri::AppHandle;

pub const FILE_NAME: &str = "atype-shared.json";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SharedPrompt {
    pub id: String,
    pub name: String,
    pub prompt: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct SharedConfig {
    pub version: u32,
    pub updated_at: Option<String>,
    pub prompts: Vec<SharedPrompt>,
    pub command_prompt_id: String,
    pub dictionary: Vec<DictEntry>,
    pub profile: String,
}

impl Default for SharedConfig {
    fn default() -> Self {
        Self {
            version: 1,
            updated_at: None,
            prompts: Vec::new(),
            command_prompt_id: super::prompts::SMART_ID.to_string(),
            dictionary: Vec::new(),
            profile: String::new(),
        }
    }
}

fn parse(ts: Option<&str>) -> Option<DateTime<Utc>> {
    ts.and_then(|t| DateTime::parse_from_rfc3339(t).ok())
        .map(|t| t.with_timezone(&Utc))
}

fn file_path(app: &AppHandle, cfg: &AtypeConfig) -> Option<PathBuf> {
    config::brain_dir(app, cfg).map(|d| d.join(FILE_NAME))
}

/// The local state as a shared config (no timestamp).
pub fn from_local(settings: &AppSettings, cfg: &AtypeConfig) -> SharedConfig {
    SharedConfig {
        prompts: settings
            .post_process_prompts
            .iter()
            .map(|p| SharedPrompt {
                id: p.id.clone(),
                name: p.name.clone(),
                prompt: p.prompt.clone(),
            })
            .collect(),
        command_prompt_id: settings
            .post_process_selected_prompt_id
            .clone()
            .unwrap_or_else(|| super::prompts::SMART_ID.to_string()),
        dictionary: cfg.dictionary.clone(),
        profile: cfg.profile.clone(),
        ..SharedConfig::default()
    }
}

/// Apply a shared config onto the local state. Built-in prompts missing from
/// the file are added back; an unknown command prompt falls back to 萬用口令.
pub fn apply(shared: &SharedConfig, settings: &mut AppSettings, cfg: &mut AtypeConfig) {
    if !shared.prompts.is_empty() {
        settings.post_process_prompts = shared
            .prompts
            .iter()
            .map(|p| LLMPrompt {
                id: p.id.clone(),
                name: p.name.clone(),
                prompt: p.prompt.clone(),
            })
            .collect();
    }
    super::prompts::add_missing(&mut settings.post_process_prompts);
    let id = if settings
        .post_process_prompts
        .iter()
        .any(|p| p.id == shared.command_prompt_id)
    {
        shared.command_prompt_id.clone()
    } else {
        super::prompts::SMART_ID.to_string()
    };
    settings.post_process_selected_prompt_id = Some(id);
    cfg.dictionary = dictionary::sanitize(shared.dictionary.clone());
    cfg.profile = shared.profile.clone();
}

fn read(path: &PathBuf) -> Option<SharedConfig> {
    let text = std::fs::read_to_string(path).ok()?;
    match serde_json::from_str(&text) {
        Ok(c) => Some(c),
        Err(e) => {
            warn!("Atype shared: {} is not valid: {}", path.display(), e);
            None
        }
    }
}

/// Write the local state to the shared file and remember the timestamp.
pub fn push(app: &AppHandle) {
    let mut cfg = config::load(app);
    let Some(path) = file_path(app, &cfg) else {
        return;
    };
    let now = Utc::now().to_rfc3339_opts(SecondsFormat::Secs, true);
    let mut shared = from_local(&get_settings(app), &cfg);
    shared.updated_at = Some(now.clone());
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(text) = serde_json::to_string_pretty(&shared) else {
        return;
    };
    // Write in place (not temp file + rename): iCloud Drive reliably picks up
    // an in-place change, while a renamed-over file did not reach the iPhone.
    if let Err(e) = std::fs::write(&path, text + "\n") {
        warn!("Atype shared: could not write {}: {}", path.display(), e);
        return;
    }
    cfg.shared_synced_at = Some(now);
    config::save(app, &cfg);
}

/// Pull a newer shared file, or create it when missing. Returns whether the
/// local state changed.
pub fn sync(app: &AppHandle) -> bool {
    let mut cfg = config::load(app);
    let Some(path) = file_path(app, &cfg) else {
        return false;
    };
    let Some(shared) = read(&path) else {
        if !path.exists() {
            push(app);
        }
        return false;
    };
    let theirs = parse(shared.updated_at.as_deref());
    let ours = parse(cfg.shared_synced_at.as_deref());
    if theirs.is_none() || theirs <= ours {
        return false;
    }
    let mut settings = get_settings(app);
    apply(&shared, &mut settings, &mut cfg);
    write_settings(app, settings);
    cfg.shared_synced_at = shared.updated_at.clone();
    config::save(app, &cfg);
    info!(
        "Atype shared: applied {} from {}",
        FILE_NAME,
        path.display()
    );
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_round_trips_through_shared() {
        let mut settings = crate::settings::get_default_settings();
        let mut cfg = AtypeConfig::default();
        cfg.dictionary = vec![DictEntry {
            term: "iCloud".into(),
            aliases: vec!["iclo".into()],
        }];
        settings.post_process_prompts[0].prompt = "edited ${output}".into();
        let shared = from_local(&settings, &cfg);

        let mut s2 = crate::settings::get_default_settings();
        let mut c2 = AtypeConfig::default();
        apply(&shared, &mut s2, &mut c2);
        assert_eq!(s2.post_process_prompts[0].prompt, "edited ${output}");
        assert_eq!(c2.dictionary, cfg.dictionary);
        assert_eq!(
            s2.post_process_selected_prompt_id.as_deref(),
            Some(super::super::prompts::SMART_ID)
        );
    }

    #[test]
    fn reads_the_iphone_format() {
        // What AtypeCore's SharedConfig writes (sorted keys, ISO-8601 date).
        let json = r#"{"command_prompt_id":"atype_email","dictionary":[{"aliases":[],"term":"程式碼"}],
            "prompts":[{"id":"atype_email","name":"正式信件","prompt":"x ${output}"}],
            "updated_at":"2026-10-07T10:07:00Z","version":1}"#;
        let shared: SharedConfig = serde_json::from_str(json).unwrap();
        let mut s = crate::settings::get_default_settings();
        let mut c = AtypeConfig::default();
        apply(&shared, &mut s, &mut c);
        assert_eq!(
            s.post_process_selected_prompt_id.as_deref(),
            Some("atype_email")
        );
        // Missing built-ins come back.
        assert_eq!(
            s.post_process_prompts.len(),
            super::super::prompts::presets().len()
        );
        assert_eq!(c.dictionary[0].term, "程式碼");
        assert!(parse(shared.updated_at.as_deref()).is_some());
    }
}
