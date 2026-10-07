//! Atype-specific policy kept in one file so upstream (Handy) merges stay small.
//!
//! Everything here is a filter or default on top of Handy's own machinery.
//! Hooks into Handy code (each a one-line call):
//! - `ModelManager::get_available_models` → [`shape_model_list`]
//! - `actions::process_transcription_output` → [`zh_post::polish`] and the
//!   LLM time budget from [`config::AtypeConfig::llm_timeout_ms`]
//! - `lib.rs` setup → [`init`] (second-brain listener)
//! - `lib.rs` `collect_commands!` → [`commands`] (the 個人化 settings page)
//! - `--polish TEXT` on the CLI → [`zh_post::polish`]

pub mod brain;
pub mod commands;
pub mod config;
pub mod defaults;
pub mod dictionary;
pub mod prompts;
pub mod shared;
pub mod zh_post;

use crate::managers::model::ModelInfo;
use tauri::AppHandle;

/// Whether the plain "transcribe" hotkey should also run LLM post-processing.
pub fn main_hotkey_polishes(app: &AppHandle) -> bool {
    crate::settings::get_settings(app).post_process_enabled && config::load(app).llm_on_main_hotkey
}

/// Name fragments of models that cannot clean up text over a plain chat
/// completion: realtime/WebSocket-only (`live`), speech, image, video, music,
/// embeddings and agent previews. Matched against the lowercased model id.
const NON_CHAT_MODEL_MARKERS: &[&str] = &[
    "live",
    "realtime",
    "streaming",
    "native-audio",
    "tts",
    "transcribe",
    "whisper",
    "image",
    "imagen",
    "nano-banana",
    "veo",
    "lyria",
    "embedding",
    "aqa",
    "robotics",
    "computer-use",
    "deep-research",
    "antigravity",
    "moderation",
    "dall-e",
];

/// Drop models the post-processing call cannot use from a provider's model
/// list, so they never show up in the model picker.
pub fn chat_models_only(models: Vec<String>) -> Vec<String> {
    models.into_iter().filter(|m| is_chat_model(m)).collect()
}

pub fn is_chat_model(model: &str) -> bool {
    let id = model.to_lowercase();
    !NON_CHAT_MODEL_MARKERS
        .iter()
        .any(|marker| id.contains(marker))
}

/// Pick the prompt and time budget for this call, on a (per-call) copy of
/// the settings. The command hotkey uses the prompt selected in 後處理
/// (default 萬用口令) with the longer command budget; the main hotkey, when
/// it runs the LLM at all, always uses the plain cleanup prompt.
pub fn prompt_for_call(
    settings: &mut crate::settings::AppSettings,
    cfg: &config::AtypeConfig,
    command: bool,
) -> u64 {
    if command {
        return cfg.command_timeout_ms.max(cfg.llm_timeout_ms);
    }
    if settings
        .post_process_prompts
        .iter()
        .any(|p| p.id == prompts::CLEANUP_ID)
    {
        settings.post_process_selected_prompt_id = Some(prompts::CLEANUP_ID.to_string());
    }
    cfg.llm_timeout_ms
}

static APP: std::sync::OnceLock<AppHandle> = std::sync::OnceLock::new();
static COMMAND_UPGRADE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Start of a recording session: tell the overlay which mode it is in and
/// forget any upgrade left from the previous session.
pub fn begin_session(app: &AppHandle, command: bool) {
    COMMAND_UPGRADE.store(false, std::sync::atomic::Ordering::SeqCst);
    use tauri::Emitter;
    let _ = app.emit("atype-command-mode", command);
}

/// The command hotkey usually extends the main one (main = right ⌘ + right
/// ⌥, command = the same plus ←), so the main hotkey is already recording
/// when the command press arrives. Upgrade that session to a command session
/// instead of ignoring the press. Returns whether it upgraded.
pub fn upgrade_to_command(pressed: &str, recording: &str) -> bool {
    if pressed != "transcribe_with_post_process" || recording != "transcribe" {
        return false;
    }
    COMMAND_UPGRADE.store(true, std::sync::atomic::Ordering::SeqCst);
    if let Some(app) = APP.get() {
        use tauri::Emitter;
        let _ = app.emit("atype-command-mode", true);
    }
    true
}

/// Whether the session that is ending was upgraded to a command session.
pub fn take_command_upgrade() -> bool {
    COMMAND_UPGRADE.swap(false, std::sync::atomic::Ordering::SeqCst)
}

/// Append the dictionary's `<known_terms>` block to the selected prompt in
/// this (per-call) copy of the settings. The stored prompt is not changed.
pub fn add_known_terms(
    settings: &mut crate::settings::AppSettings,
    dictionary: &[dictionary::DictEntry],
) {
    let Some(block) = dictionary::known_terms_prompt(dictionary) else {
        return;
    };
    append_to_selected_prompt(settings, &block);
}

/// Append the user's profile as <about_me> (signature, title, company…).
pub fn add_profile(settings: &mut crate::settings::AppSettings, profile: &str) {
    let p = profile.trim();
    if p.is_empty() {
        return;
    }
    let block = format!(
        "\n<about_me>\n{p}\n</about_me>\n以上是使用者本人的資料。只在輸出格式本來就需要署名、自稱、職稱、公司或聯絡方式時使用（例如信件、公告），不要再標【待補】；不要因為有這些資料就把內容改寫成信件或加上署名。\n"
    );
    append_to_selected_prompt(settings, &block);
}

fn append_to_selected_prompt(settings: &mut crate::settings::AppSettings, block: &str) {
    let Some(id) = settings.post_process_selected_prompt_id.clone() else {
        return;
    };
    if let Some(prompt) = settings
        .post_process_prompts
        .iter_mut()
        .find(|p| p.id == id)
    {
        prompt.prompt.push_str(block);
    }
}

/// Everything Atype wires up at runtime. Called once after Handy's managers
/// are registered.
pub fn init(app: &AppHandle) {
    let _ = APP.set(app.clone());
    defaults::apply_once(app);
    shared::sync(app);
    brain::init(app);
}

/// Models shown in the UI / CLI, in display order. The first entry is the
/// recommended one. Catalog entries are matched by repo id prefix because
/// Handy's registry id is `"{repo_id}/{filename}"` (one entry per quant file
/// that exists on disk, plus the default quant); these run through
/// transcribe-cpp (Metal on Apple Silicon). The last two are legacy ONNX/ggml
/// entries matched by exact id.
pub const MODELS: &[&str] = &[
    "handy-computer/SenseVoiceSmall-gguf", // zh/yue/en/ja/ko, non-autoregressive, fastest
    "handy-computer/Qwen3-ASR-0.6B-gguf",  // 30 languages, strong Chinese; A/B against SenseVoice
    "handy-computer/Fun-ASR-Nano-2512-gguf", // zh/en/ja, newer FunAudioLLM model
    "handy-computer/Breeze-ASR-25-gguf",   // MediaTek, Taiwan Mandarin + code-switching
    "handy-computer/Qwen3-ASR-1.7B-gguf",
    "handy-computer/Fun-ASR-MLT-Nano-2512-gguf",
    "handy-computer/whisper-large-v3-turbo-gguf", // reference only
    "handy-computer/moonshine-tiny-zh-gguf",
    "handy-computer/moonshine-base-zh-gguf",
    "sense-voice-int8", // legacy ONNX SenseVoice (CPU, transcribe-rs); used by the Linux smoke test
    "breeze-asr",       // legacy ggml Breeze
];

fn matches(entry: &str, id: &str) -> bool {
    id == entry
        || id
            .strip_prefix(entry)
            .is_some_and(|rest| rest.starts_with('/'))
}

pub fn model_rank(id: &str) -> usize {
    MODELS
        .iter()
        .position(|m| matches(m, id))
        .unwrap_or(MODELS.len())
}

pub fn is_allowed_model(id: &str) -> bool {
    model_rank(id) < MODELS.len()
}

pub fn is_recommended_model(id: &str) -> bool {
    MODELS.first().is_some_and(|m| matches(m, id))
}

/// Filter, re-flag and re-order Handy's model list for Atype.
pub fn shape_model_list(list: &mut Vec<ModelInfo>) {
    list.retain(|m| is_allowed_model(&m.id) || m.is_downloaded);
    for m in list.iter_mut() {
        m.is_recommended = is_recommended_model(&m.id);
    }
    list.sort_by_key(|m| model_rank(&m.id));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_press_upgrades_a_main_session_once() {
        assert!(!upgrade_to_command(
            "transcribe",
            "transcribe_with_post_process"
        ));
        assert!(!upgrade_to_command("cancel", "transcribe"));
        assert!(upgrade_to_command(
            "transcribe_with_post_process",
            "transcribe"
        ));
        assert!(take_command_upgrade());
        assert!(!take_command_upgrade());
    }

    #[test]
    fn model_picker_hides_non_chat_models() {
        let got = chat_models_only(
            [
                "models/gemini-3.1-flash-lite",
                "models/gemini-3.8-live",
                "models/gemini-3.8-flash-tts",
                "models/gemini-3.1-flash-image",
                "models/gemini-embedding-2",
                "models/gemini-2.5-flash-native-audio-latest",
                "models/veo-3.1-generate-preview",
                "models/gemini-3.5-flash",
                "claude-haiku-4-5",
            ]
            .map(String::from)
            .to_vec(),
        );
        assert_eq!(
            got,
            [
                "models/gemini-3.1-flash-lite",
                "models/gemini-3.5-flash",
                "claude-haiku-4-5"
            ]
        );
    }

    #[test]
    fn allowlist_order_and_recommendation() {
        let sv = "handy-computer/SenseVoiceSmall-gguf/SenseVoiceSmall-Q8_0.gguf";
        let qwen = "handy-computer/Qwen3-ASR-0.6B-gguf/Qwen3-ASR-0.6B-Q8_0.gguf";
        assert!(is_recommended_model(sv));
        assert!(!is_recommended_model(qwen));
        assert!(model_rank(sv) < model_rank(qwen));
        assert!(is_allowed_model("sense-voice-int8"));
        assert_eq!(model_rank("parakeet-tdt-0.6b-v3"), MODELS.len());
        assert!(!is_allowed_model("parakeet-tdt-0.6b-v3"));
        assert!(!is_allowed_model(
            "handy-computer/parakeet-unified-en-0.6b-gguf/x.gguf"
        ));
        // A different repo that merely shares a prefix string must not match.
        assert!(!is_allowed_model(
            "handy-computer/SenseVoiceSmall-gguf-other/x.gguf"
        ));
    }
}
