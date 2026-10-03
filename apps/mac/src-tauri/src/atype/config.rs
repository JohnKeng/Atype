//! Atype's own settings, kept in a separate `atype.json` next to Handy's
//! settings store so Handy's `AppSettings` struct never has to change.
//! The file is created with defaults on first use; edit it by hand or through
//! the (future) Atype settings page.

use log::warn;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tauri::AppHandle;

pub const FILE_NAME: &str = "atype.json";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct AtypeConfig {
    /// Run the deterministic Chinese layer (OpenCC s2twp gate, full-width
    /// punctuation, pangu spacing) on every result.
    pub zh_post_enabled: bool,
    /// Time budget for the LLM. When it is exceeded the deterministic result
    /// of the raw transcription is pasted instead of waiting.
    pub llm_timeout_ms: u64,
    /// Append every transcription to the second-brain folder.
    pub brain_enabled: bool,
    /// Second-brain folder. `None` = iCloud Drive/Atype/brain on macOS when
    /// iCloud Drive exists, otherwise `<app data>/brain`. `~/` is expanded.
    pub brain_dir: Option<String>,
}

impl Default for AtypeConfig {
    fn default() -> Self {
        Self {
            zh_post_enabled: true,
            llm_timeout_ms: 2500,
            brain_enabled: true,
            brain_dir: None,
        }
    }
}

pub fn path(app: &AppHandle) -> Option<PathBuf> {
    crate::portable::app_data_dir(app)
        .ok()
        .map(|dir| dir.join(FILE_NAME))
}

/// Load `atype.json`, writing the defaults when it does not exist yet. Never
/// fails: a broken file logs a warning and falls back to defaults.
pub fn load(app: &AppHandle) -> AtypeConfig {
    let Some(path) = path(app) else {
        return AtypeConfig::default();
    };
    match std::fs::read_to_string(&path) {
        Ok(text) => serde_json::from_str(&text).unwrap_or_else(|e| {
            warn!(
                "Atype: {} is not valid, using defaults: {}",
                path.display(),
                e
            );
            AtypeConfig::default()
        }),
        Err(_) => {
            let cfg = AtypeConfig::default();
            if let Some(parent) = path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            if let Ok(text) = serde_json::to_string_pretty(&cfg) {
                let _ = std::fs::write(&path, text + "\n");
            }
            cfg
        }
    }
}

fn expand_home(p: &str) -> PathBuf {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(p)
}

/// Where the second brain writes. See [`AtypeConfig::brain_dir`].
pub fn brain_dir(app: &AppHandle, cfg: &AtypeConfig) -> Option<PathBuf> {
    if let Some(dir) = cfg.brain_dir.as_deref().filter(|d| !d.trim().is_empty()) {
        return Some(expand_home(dir));
    }
    #[cfg(target_os = "macos")]
    {
        if let Some(home) = std::env::var_os("HOME") {
            let icloud = PathBuf::from(home).join("Library/Mobile Documents/com~apple~CloudDocs");
            if icloud.is_dir() {
                return Some(icloud.join("Atype/brain"));
            }
        }
    }
    crate::portable::app_data_dir(app)
        .ok()
        .map(|dir| dir.join("brain"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_round_trip_and_unknown_fields_are_ignored() {
        let cfg: AtypeConfig = serde_json::from_str("{}").unwrap();
        assert_eq!(cfg, AtypeConfig::default());
        let cfg: AtypeConfig =
            serde_json::from_str(r#"{"llm_timeout_ms": 1000, "future_field": 1}"#).unwrap();
        assert_eq!(cfg.llm_timeout_ms, 1000);
        assert!(cfg.zh_post_enabled);
    }

    #[test]
    fn home_is_expanded() {
        std::env::set_var("HOME", "/tmp/atype-home");
        assert_eq!(
            expand_home("~/Notes/brain"),
            PathBuf::from("/tmp/atype-home/Notes/brain")
        );
        assert_eq!(expand_home("/abs/path"), PathBuf::from("/abs/path"));
    }
}
