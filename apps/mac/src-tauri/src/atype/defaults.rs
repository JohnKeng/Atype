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

pub const VERSION: u32 = 2;

/// Version 1: LLM cleanup on, Traditional output, a useful history size,
/// no upstream "what's new" notes.
pub fn apply_v1(s: &mut AppSettings) {
    s.post_process_enabled = true;
    s.chinese_script = ChineseScript::Traditional;
    s.history_limit = s.history_limit.max(300);
    s.show_whats_new_on_update = false;
}

/// Version 2: launch quietly into the menu bar (no window, no Dock icon).
/// The Dock icon appears only while the settings window is open. Only applied
/// once setup is done (a model is selected); macOS does not force the window
/// open for onboarding, so a fresh install must still start with the window.
pub fn apply_v2(s: &mut AppSettings) {
    s.start_hidden = true;
    s.show_tray_icon = true;
}

/// Setup is done once a transcription model has been chosen.
pub fn setup_done(s: &AppSettings) -> bool {
    !s.selected_model.trim().is_empty()
}

pub fn apply_once(app: &AppHandle) {
    let mut cfg = config::load(app);
    if cfg.defaults_version >= VERSION {
        return;
    }
    let mut settings = get_settings(app);
    let mut applied = cfg.defaults_version;
    if applied < 1 {
        apply_v1(&mut settings);
        applied = 1;
    }
    if applied < 2 && setup_done(&settings) {
        apply_v2(&mut settings);
        applied = 2;
    }
    if applied == cfg.defaults_version {
        return;
    }
    write_settings(app, settings);
    cfg.defaults_version = applied;
    config::save(app, &cfg);
    info!("Atype: applied one-time defaults up to v{}", applied);
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

    #[test]
    fn v2_waits_for_setup() {
        let mut s = crate::settings::get_default_settings();
        s.selected_model = String::new();
        assert!(!setup_done(&s));
        s.selected_model = "handy-computer/SenseVoiceSmall-gguf/x.gguf".into();
        assert!(setup_done(&s));
    }

    #[test]
    fn v2_starts_in_the_menu_bar() {
        let mut s = crate::settings::get_default_settings();
        s.start_hidden = false;
        s.show_tray_icon = false;
        apply_v2(&mut s);
        assert!(s.start_hidden);
        assert!(s.show_tray_icon);
    }
}
