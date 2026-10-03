//! Atype-specific policy kept in one file so upstream (Handy) merges stay small.
//!
//! Everything here is a filter or default on top of Handy's own machinery.
//! Hooks into Handy code (each a one-line call):
//! - `ModelManager::get_available_models` → [`shape_model_list`]

use crate::managers::model::ModelInfo;

/// Models shown in the UI / CLI, in display order. The first entry is the
/// recommended one. Ids are Handy's: catalog entries (`handy-computer/…-gguf`,
/// run by transcribe-cpp, Metal on Apple Silicon) and legacy ONNX/ggml entries.
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

pub fn model_rank(id: &str) -> usize {
    MODELS.iter().position(|m| *m == id).unwrap_or(MODELS.len())
}

pub fn is_allowed_model(id: &str) -> bool {
    model_rank(id) < MODELS.len()
}

pub fn is_recommended_model(id: &str) -> bool {
    MODELS.first().is_some_and(|m| *m == id)
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
        assert!(is_recommended_model(MODELS[0]));
        assert!(!is_recommended_model(MODELS[1]));
        assert_eq!(model_rank("parakeet-tdt-0.6b-v3"), MODELS.len());
        assert!(!is_allowed_model("parakeet-tdt-0.6b-v3"));
        assert!(model_rank(MODELS[0]) < model_rank(MODELS[1]));
    }
}
