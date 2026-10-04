//! One-time Atype defaults for an existing settings store.
//!
//! Handy writes its full settings on first launch, so changing a `default_*`
//! function only affects brand-new installs. This applies Atype's choices once
//! to a store that already exists, then records the version in `atype.json`
//! so later changes the user makes in the UI are never overwritten.

use super::config;
use crate::settings::{get_settings, write_settings, AppSettings, ChineseScript};
use log::info;
use tauri::AppHandle;

pub const VERSION: u32 = 1;

/// Version 1: LLM cleanup on, Traditional output, a useful history size,
/// no upstream "what's new" notes.
pub fn apply_v1(s: &mut AppSettings) {
    s.post_process_enabled = true;
    s.chinese_script = ChineseScript::Traditional;
    s.history_limit = s.history_limit.max(300);
    s.show_whats_new_on_update = false;
}

pub fn apply_once(app: &AppHandle) {
    let mut cfg = config::load(app);
    if cfg.defaults_version >= VERSION {
        return;
    }
    let mut settings = get_settings(app);
    apply_v1(&mut settings);
    write_settings(app, settings);
    cfg.defaults_version = VERSION;
    config::save(app, &cfg);
    info!("Atype: applied one-time defaults v{}", VERSION);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v1_sets_atype_choices_and_never_shrinks_history() {
        let mut s = crate::settings::get_default_settings();
        s.post_process_enabled = false;
        s.chinese_script = ChineseScript::AsTranscribed;
        s.history_limit = 5;
        s.show_whats_new_on_update = true;
        apply_v1(&mut s);
        assert!(s.post_process_enabled);
        assert_eq!(s.chinese_script, ChineseScript::Traditional);
        assert_eq!(s.history_limit, 300);
        assert!(!s.show_whats_new_on_update);

        s.history_limit = 1000;
        apply_v1(&mut s);
        assert_eq!(s.history_limit, 1000);
    }
}
