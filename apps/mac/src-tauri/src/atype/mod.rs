//! Atype-specific policy kept in one file so upstream (Handy) merges stay small.
//!
//! Everything here is a filter or default on top of Handy's own machinery.
//! Hooks into Handy code (each a one-line call):
//! - `ModelManager::get_available_models` → [`shape_model_list`]
//! - `actions::process_transcription_output` → [`zh_post::polish`] and the
//!   LLM time budget from [`config::AtypeConfig::llm_timeout_ms`]
//! - `lib.rs` setup → [`init`] (second-brain listener)
//! - `--polish TEXT` on the CLI → [`zh_post::polish`]

pub mod brain;
pub mod config;
pub mod defaults;
pub mod zh_post;

use crate::managers::model::ModelInfo;
use tauri::AppHandle;

/// Whether the plain "transcribe" hotkey should also run LLM post-processing.
pub fn main_hotkey_polishes(app: &AppHandle) -> bool {
    crate::settings::get_settings(app).post_process_enabled && config::load(app).llm_on_main_hotkey
}

/// Everything Atype wires up at runtime. Called once after Handy's managers
/// are registered.
pub fn init(app: &AppHandle) {
    defaults::apply_once(app);
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
