# STT 引擎全景調查（2026-10）：給「自製 Typeless」用的語音辨識引擎選型

> 研究日期：2026-10-01。目標：桌機（macOS / Windows / Linux）＋手機（iOS / Android）的 AI 語音聽寫（voice keyboard），主要語言為 **台灣華語（zh-TW）**、普通話、以及 **中英夾雜（code-switching）**。
>
> 資料來源說明：本環境的網路代理封鎖了多個官方網域（openai.com、deepgram.com、assemblyai.com、groq.com、elevenlabs.io、huggingface.co、arxiv.org、docs.cloud.google.com、azure.microsoft.com、speechmatics.com、soniox.com、mistral.ai 等），因此這些廠商的價格與規格部分引用自搜尋摘要或第三方彙整站，並在文中標註「待官方頁面確認」。GitHub 原始碼頁面可直接讀取，相關數據可信度較高。

---

## 0. 執行摘要（Executive Summary）

1. **2026 年雲端 STT 的中文賽局已經改寫**：OpenAI 在 2026-07-28 推出 `gpt-transcribe`（批次，$0.0045/min）與 `gpt-live-transcribe`（串流，$0.017/min），並在 2026-05 推出 `gpt-realtime-whisper`；Deepgram Nova-3 於 2026-03-31 補上 `zh-TW / zh-Hant`；ElevenLabs Scribe v2 在獨立基準 GigaSpeechBench 的普通話 CER（5.24%）優於 GPT-4o（15.29%）與 Gemini 3.0 Flash（8.79%），但仍輸給 Azure（5.92%，接近）與中國系開源模型（Qwen3-ASR-1.7B 3.95%、FunASR-realtime 3.12%）。
2. **中文品質最強的仍是中國系開源 / 自研模型**：Qwen3-ASR-1.7B（Apache-2.0，2026-01-30 開源）在 AISHELL-2 WER 2.71 vs Whisper-large-v3 5.06；SenseVoice-Small 在 AISHELL-1 CER 2.96 vs Whisper-L-v3 5.14；FireRedASR-AED-L 平均 CER 3.18%。這些模型都能透過 **sherpa-onnx**（Apache-2.0，支援 Swift/Kotlin/Rust/C/Dart 等 12+ 綁定、Android/iOS/macOS/Windows/Linux）部署到端上。
3. **台灣華語＋中英夾雜的專用模型**：MediaTek Research 的 **Breeze-ASR-25**（Whisper-large-v2 微調，MIT 授權）在 CommonVoice zh-TW WER 7.97（原版 9.84）、CSZS 中英夾雜 WER 13.01（原版 29.49，降 56%），且已有 ggml / WhisperKit CoreML 轉檔可直接跑 whisper.cpp。注意 **Breeze-ASR-26 是台語（Taiwanese Hokkien）模型**，不是 25 的升級版。
4. **Apple 平台端上首選是 iOS 26 / macOS 26 的 `SpeechAnalyzer` + `SpeechTranscriber`**：完全離線、系統管理模型、支援 `zh_TW / zh_CN / zh_HK / yue_CN`（共 42 個 locale），第三方測試在中文 CER 與 Whisper-large-v3-turbo 持平（7.97），且速度遠勝 Whisper。零成本、零模型下載負擔，是手機 / Mac 版 MVP 的最佳起點。
5. **Whisper 家族對 zh-TW 有「簡繁混出」問題**：Whisper 內部只有單一 `zh` 語言碼，必須靠 `initial_prompt` 給繁體提示或事後用 OpenCC 轉換；`large-v3-turbo` 在聲調語言與幻覺（hallucination）上比 `large-v3` 明顯退步（FIC 1601 vs 124），不建議當中文主引擎。
6. **最便宜的雲端**：Groq `whisper-large-v3-turbo` $0.04/hr（免費層每日 28,800 秒音訊）；Soniox 約 $0.10–0.12/hr；Gemini 2.5 Flash 音訊輸入 $1/M tokens × 32 tokens/s ≈ $0.115/hr；Alibaba `qwen3-asr-flash-realtime` $0.000035/s ≈ $0.126/hr。
7. **最快的串流**：ElevenLabs Scribe v2 Realtime（<150 ms，$0.39/hr）、Mistral Voxtral Realtime（可調到 <200 ms，$0.006/min，且 4B 開源權重 Apache-2.0）、Gladia Solaria（103 ms partial）、Fireworks 串流（300 ms，$0.0032/min）。
8. **建議架構**：「端上優先、雲端加值」的雙引擎。Apple 平台用 SpeechAnalyzer；Windows/Linux/Android 用 sherpa-onnx + SenseVoice-Small（或 Qwen3-ASR-0.6B int8）；需要更高品質或中英夾雜時，切到雲端（首選 ElevenLabs Scribe v2 / Deepgram Nova-3 zh-TW / gpt-transcribe），再由 LLM 做後處理（標點、簡繁正規化、格式化）。

---

## 1. 雲端 STT API 總表

> 單位統一換算成 **USD / 小時**（1 hr = 60 min）。「串流」指 WebSocket 等即時 partial 結果。價格以 2026 Q3 搜尋結果為準，部分為第三方彙整，請在上線前到官方定價頁核對。

| 廠商 / 模型 | 批次價 | 串流價 | 串流延遲 | 語言數 | 中文 / zh-TW | 字詞時間戳 | 自訂詞彙 | 免費額度 | 資料保留 |
|---|---|---|---|---|---|---|---|---|---|
| OpenAI `gpt-transcribe`（2026-07-28） | $0.27/hr（$0.0045/min） | — | — | 22 語言（含中文，待確認） | 有，`languages` 可給多個 hint | segment；word 待確認 | `prompt` 自由文字 | 無 | 預設 30 天後刪除；ZDR 需企業資格 |
| OpenAI `gpt-live-transcribe` / `gpt-realtime-whisper`（2026-05/07） | — | $1.02/hr（$0.017/min） | 低（未公布數字） | 同上 | 有 | — | `prompt` | 無 | 同上 |
| OpenAI `gpt-4o-transcribe` / `-mini` | $0.36 / $0.18 per hr | Realtime API 可用（以 token 計） | 中 | ~98（Whisper 系） | 有 | 有 | `prompt` | 無 | 同上 |
| OpenAI `whisper-1` | $0.36/hr（$0.006/min） | 否 | — | 98 | 有（簡繁混出） | word | `prompt` | 無 | 同上 |
| Deepgram Nova-3 | $0.0043/min（$0.26/hr） | $0.0048–0.0077/min（$0.29–0.46/hr，來源不一） | <300 ms 等級 | 50+ | **2026-03-31 新增 zh-TW / zh-Hant**；`multi` code-switching 模式 **不含中文** | word | keyterm prompting（Nova-3 英文最佳） | $200 credit（常見） | 音訊即時處理不儲存（除非開啟儲存） |
| Deepgram Flux（對話式，2025-10） | — | $0.0065/min 英文；多語 $0.0078/min（2026-04） | EOT 1.5 s p95 | 英文 + 10 語 | 無中文 | — | — | — | — |
| AssemblyAI Universal-2（async） | $0.15/hr | Universal-Streaming $0.15/hr（英文等） | ~300 ms | 99（async） | async 有；**串流 Universal-3 Pro 僅 6 歐語**；Universal-3.5 Pro Realtime 18 語含 Mandarin，$0.45/hr | word | word boost / keyterms | $50 credit（常見） | 可設 ZDR（企業） |
| Groq `whisper-large-v3-turbo` | **$0.04/hr** | 否 | 批次極快（216×） | 98 | 有（Whisper 問題同） | segment/word | `prompt` | 免費層 20 RPM、2,000 RPD、28,800 音訊秒/日、25 MB | 第三方託管 |
| Groq `whisper-large-v3` | $0.111/hr | 否 | — | 98 | 有 | 有 | `prompt` | 同上 | — |
| ElevenLabs Scribe v2 | **$0.22/hr**（+keyterm $0.05、+entity $0.07） | Scribe v2 Realtime **$0.39/hr** | **<150 ms** | 90+ | 普通話 FLEURS WER 3.1%、粵語 5.9%（官方）；GigaSpeechBench 普通話 CER 5.24% | word | keyterm prompting | 免費方案有少量 | 企業可 ZDR |
| Google STT v2 Chirp 3 | $0.016/min（$0.96/hr）；Dynamic batch ~$0.003/min | 同價 | 中 | 125+ | 有（`cmn-Hant-TW` 傳統 locale） | word | model adaptation | 60 min/月 | 可選 data logging 折扣 |
| Google Gemini 2.5 Flash（audio in） | $1/M audio tokens ≈ **$0.115/hr**（32 tok/s） | Live API | 中 | 多 | 有；GigaSpeechBench Gemini 3.0 Flash 普通話 CER 8.79% | 無原生 | prompt | 有免費層 | 依 Gemini API 政策 |
| Azure AI Speech | $1.00/hr（標準） | $1.00/hr | 低 | 100+ | 有 `zh-TW`；GigaSpeechBench 普通話 CER **5.92%**（商用 API 中第二好） | word | Custom Speech / phrase list | **5 hr/月** | 可設 |
| Speechmatics | 標準 $0.24/hr；Enhanced $0.40/hr | 標準 $0.24/hr；Enhanced $0.43/hr（2026-07 降價） | 低 | 55+ | `cmn`、`yue` 皆支援即時 | word | custom dictionary | **50 hr/月**（20 RT + 30 batch） | 可設 |
| Gladia Solaria-1 | $0.61/hr | $0.75/hr（Growth $0.25/hr） | 103 ms partial | 100+ | 有 | word | custom vocab | €50 一次性 | 企業 ZDR |
| Soniox v5 | ~$0.10/hr（按 token） | ~$0.12/hr | token 級即時 | 60+ | Mandarin / Cantonese 同一模型；繁體輸出待確認 | word | context / keyterms | 有 | — |
| Mistral Voxtral Transcribe 2（2026-02） | **$0.003/min（$0.18/hr）** | Voxtral Realtime **$0.006/min（$0.36/hr）**，4B 開源 | 可調 <200 ms | 13（含中文） | 有 | 有 | context biasing | — | 可自架 |
| Fireworks（whisper-v3-turbo） | 依 FAU | **$0.0032/min（$0.19/hr）** | 300 ms | 98 | Whisper 系 | — | — | 2 週試用 | — |
| Alibaba `qwen3-asr-flash` / `-realtime` | $0.035/M tokens | **$0.000035/s ≈ $0.126/hr** | 低 | 52（30 語 + 22 中文方言） | 原生中文最強；GigaSpeechBench 方言 CER 34.92% | 有（ForcedAligner） | hotword | 有 | 資料在新加坡/北京區，需評估 |

來源：
- OpenAI 價格與模型：[costgoat OpenAI transcription pricing](https://costgoat.com/pricing/openai-transcription)、[gpt-transcribe model page](https://developers.openai.com/api/docs/models/gpt-transcribe)、[Artificial Analysis 推文（gpt-transcribe 3.31% AA-WER、$4.50/1000 min）](https://x.com/ArtificialAnlys/status/2082285338509418727)、[OpenAI 2026-05 語音模型公告](https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/)、[MarkTechPost 2026-05-08](https://www.marktechpost.com/2026/05/08/openai-releases-three-realtime-audio-models-gpt-realtime-2-gpt-realtime-translate-and-gpt-realtime-whisper-in-the-realtime-api/)、[orq.ai gpt-live-transcribe](https://orq.ai/models/openai-gpt-live-transcribe)
- Deepgram：[pricing 彙整](https://convertaudiototext.com/blog/deepgram-nova-3-explained)、[diyai Deepgram pricing 2026](https://diyai.io/ai-tools/speech-to-text/deepgram-pricing-2026/)、[Nova-3 multilingual 語言討論](https://github.com/orgs/deepgram/discussions/1097)、[Nova-3 APAC 擴充（含 zh-TW）](https://deepgram.com/learn/deepgram-nova-3-expands-speech-to-text-support-across-asia-pacific)、[changelog 2026-03-31](https://developers.deepgram.com/changelog/2026/3/31)、[omi issue #6382（Nova-3 支援中文）](https://github.com/BasedHardware/omi/issues/6382)、[Flux 定價](https://cloudprice.net/models/deepgram-flux)
- AssemblyAI：[models.md](https://www.assemblyai.com/llms/models.md)、[Universal-Streaming](https://www.assemblyai.com/universal-streaming)、[costbench AssemblyAI](https://www.costbench.com/software/ai-transcription-apis/assemblyai/)
- Groq：[pricing](https://groq.com/pricing)、[whisper-large-v3-turbo model page](https://console.groq.com/docs/model/whisper-large-v3-turbo)、[免費層限制](https://www.grizzlypeaksoftware.com/articles/p/groq-api-free-tier-limits-in-2026-what-you-actually-get-uwysd6mb)
- ElevenLabs：[Scribe v2 Realtime 頁](https://elevenlabs.io/realtime-speech-to-text)、[API pricing](https://elevenlabs.io/pricing/api)、[Mandarin 頁](https://elevenlabs.io/speech-to-text)、[Cantonese 頁](https://elevenlabs.io/speech-to-text/cantonese)
- Google：[STT pricing 彙整](https://convertaudiototext.com/blog/google-cloud-speech-to-text-pricing-2026)、[Chirp 3 model doc](https://docs.cloud.google.com/speech-to-text/v2/docs/chirp_3-model)、[Gemini audio token 計價討論](https://discuss.ai.google.dev/t/live-api-pricing-audio-tokens-second-silent-audio/92653)、[Gemini pricing 2026](https://www.morphllm.com/gemini-api-pricing)
- Azure：[speech-services pricing](https://azure.microsoft.com/pricing/details/cognitive-services/speech-services)、[Azure $1/hr 討論](https://learn.microsoft.com/en-us/answers/questions/2155625/speech-to-text-costing-1-hr-is-crazy-no-bulk-avail)、[apio Azure STT](https://apio.sh/apis/azure-speech-to-text)
- Speechmatics：[2026-07-06 降價紀錄](https://usagepricing.com/blueprint/activity/speechmatics-2026-07-06-realtime-stt-price-cut)、[supported languages](https://docs.speechmatics.com/introduction/supported-languages)、[Mandarin 頁](https://www.speechmatics.com/speech-to-text/mandarin)
- Gladia：[pricing 分析](https://dailyaifixs.com/blog/gladia-pricing-2026-the-real-time-premium)；Soniox：[compare 頁](https://soniox.com/compare)、[Chinese 頁](https://soniox.com/speech-translation/chinese)
- Mistral：[Voxtral Transcribe 2 公告](https://mistral.ai/news/voxtral-transcribe-2/)、[MarkTechPost 2026-02-04](https://www.marktechpost.com/2026/02/04/mistral-ai-launches-voxtral-transcribe-2-pairing-batch-diarization-and-open-realtime-asr-for-multilingual-production-workloads-at-scale/)
- Fireworks：[streaming audio launch](https://fireworks-frontend-3cs6he6vv.preview.fireworks.ai/blog/streaming-audio-launch)、[audio transcription launch](https://fireworks.ai/blog/audio-transcription-launch?rp=8)
- Alibaba：[qwen3-asr-flash-realtime 文件](https://www.alibabacloud.com/help/en/model-studio/qwen3-asr-flash-realtime)、[cloudprice qwen3-asr-flash](https://cloudprice.net/models/qwen3-asr-flash)
- 資料保留：[OpenAI API 保留政策（via meetily 彙整）](https://meetily.ai/llm-privacy/openai)、[Deepgram Model Improvement Partnership（可選資料共享）](https://developers.deepgram.com/docs/the-deepgram-model-improvement-partnership-program)

### 1.1 各家重點細節

**OpenAI**
- 2026 年內三波更新：`gpt-4o-transcribe`（2025-03）→ `gpt-realtime-whisper`（2026-05-07，Realtime API 串流，$0.017/min）→ `gpt-transcribe` + `gpt-live-transcribe`（2026-07-28）。`gpt-transcribe` 在 Artificial Analysis AA-WER 3.31%（第 9 名），比 gpt-4o-transcribe 便宜 25%。[來源](https://x.com/ArtificialAnlys/status/2082285338509418727)
- `prompt` 參數是自由文字（例如「expect words related to technology」），用來提升人名、縮寫、格式的辨識；Realtime 的 `input_audio_transcription` 可設 `language` 與 `prompt`。`gpt-transcribe` 用 `languages`（複數）取代 `language`，可給多個 hint，這對中英夾雜有用。[來源](https://developers.openai.com/api/docs/guides/speech-to-text)
- **中文弱點**：GigaSpeechBench 普通話 CER 中 GPT-4o-transcribe 15.29%，方言 62.15%，是商用 API 中最差；`gpt-transcribe` 的中文數據尚未見獨立基準。[來源](https://github.com/SpeechColab/GigaSpeechBench)
- 資料：API 預設保留最多 30 天做濫用監控，ZDR 需企業資格。[來源](https://meetily.ai/llm-privacy/openai)

**Deepgram Nova-3**
- 2026-03-31 起 Nova-3 支援 Nova-2 的全部語言（含中文、泰文），語言碼 `zh-TW` / `zh-Hant`，批次與串流都可。[來源 1](https://github.com/BasedHardware/omi/issues/6382)、[來源 2](https://deepgram.com/learn/deepgram-nova-3-expands-speech-to-text-support-across-asia-pacific)
- `language=multi`（code-switching）只支援 10 語：英、西、法、德、印地、俄、葡、日、義、荷，**不含中文**。中英夾雜要靠 `zh-TW` 單語模式「順便」辨出英文，品質未知。[來源](https://github.com/orgs/deepgram/discussions/1097)
- 串流價格各家彙整不一（$0.0048 / $0.0058 多語 / $0.0077），需官方確認。音訊預設不儲存。

**AssemblyAI**
- 串流分兩檔：Universal-Streaming $0.15/hr（主要英文）、Universal-3.5 Pro Realtime $0.45/hr（18 語含 Mandarin）。Universal-3 Pro 串流只有 6 種歐語。要做中文串流只能選 3.5 Pro。[來源](https://www.assemblyai.com/llms/models.md)

**ElevenLabs Scribe v2 / v2 Realtime**
- 官方：普通話 FLEURS WER 3.1%、Common Voice 5.5%；粵語 FLEURS 5.9%。獨立 GigaSpeechBench 普通話 CER 5.24%（商用 API 中最佳），方言 56.08%。Realtime 版 <150 ms、$0.39/hr。[來源](https://elevenlabs.io/realtime-speech-to-text)、[GigaSpeechBench](https://github.com/SpeechColab/GigaSpeechBench)

**Google / Azure / Speechmatics**
- Azure 在 GigaSpeechBench 普通話 CER 5.92%，方言 41.80%（商用中最好），但 $1/hr 偏貴；免費 5 hr/月適合開發期。
- Speechmatics 免費 50 hr/月是所有廠商中最大方的，`cmn` / `yue` 都能即時。
- Google Chirp 3 含在 $0.016/min 標準價內，有 `cmn-Hant-TW`，但 $0.96/hr 相對貴。

**Mistral Voxtral Transcribe 2（2026-02）**
- Voxtral Mini Transcribe 2（批次，$0.003/min）與 Voxtral Realtime（4B，$0.006/min，Apache-2.0 開源權重），13 語含中文，延遲可調至 <200 ms，支援 context biasing 與時間戳。這是**唯一可自架的高品質串流商用模型**，適合「雲端 fallback 自架」策略。[來源](https://mistral.ai/news/voxtral-transcribe-2/)

**Alibaba Qwen3-ASR-Flash**
- 中文品質來自 Qwen3-ASR 系列；即時版 $0.000035/s。但資料落地（新加坡 / 北京區）對台灣使用者的隱私觀感需評估。[來源](https://www.alibabacloud.com/help/en/model-studio/qwen3-asr-flash-realtime)

---

## 2. 本地 / 端上引擎

### 2.1 總表

| 引擎 / 模型 | 參數 / 檔案大小 | RAM | 速度 | 中文 | 串流 | 授權 | 綁定（Rust/Swift/Kotlin） |
|---|---|---|---|---|---|---|---|
| **whisper.cpp**（large-v3 / turbo / Breeze-ASR-25 ggml） | large 2.9 GB（~3.9 GB RAM）；turbo ggml 1.6 GB；Breeze-ASR-25 ggml ~3 GB；q5/q8 量化可減半 | tiny 273 MB → large 3.9 GB | Metal 上 turbo 14–18× 即時；M4 Pro 短句延遲 ~200 ms | 有（簡繁混出；turbo 幻覺多） | 偽串流（chunk + VAD） | MIT | Rust（whisper-rs）、Swift/ObjC、Java/Kotlin、Go、.NET、JS/RN |
| **faster-whisper**（CTranslate2） | large-v2 int8 VRAM 2.9 GB；small int8 CPU 1.5 GB | 同左 | RTX 3070 Ti large-v2 int8 13 min 音訊 59 s；batched 16 s；i7-12700K small int8 1m42s | 同 Whisper | 否（需自行 chunk） | MIT | Python 為主；Rust 可用 ct2rs |
| **whisper large-v3-turbo** | 809M（4 層 decoder） | ~1.6 GB fp16 | 比 large-v3 快 2–5× | **聲調語言退步、幻覺 FIC 1601 vs 124** | — | MIT | 同上 |
| **distil-whisper** | 756M | — | 比 large-v3 快 6× | **英文 only** | — | MIT | — |
| **mlx-whisper**（Apple Silicon） | 同 Whisper | — | M2 Ultra turbo 12 min 音訊 14 s（~50×）；RTF ~0.02 | 同 Whisper | 否 | MIT | Python；Swift 有 mlx-audio-swift |
| **WhisperKit / Argmax**（CoreML） | large-v3-turbo 壓縮版 626 MB | — | iPhone 15 Pro Max turbo RTF 2.41（8.44 tok/s，iOS 18.2）—— 即 **慢於即時** | 同 Whisper | 有（chunk 串流） | MIT | Swift（SPM）；iOS 16+/macOS 14+ |
| **Apple SpeechAnalyzer / SpeechTranscriber**（iOS 26 / macOS 26） | 系統管理、自動下載 | 系統 | 遠快於 Whisper（第三方測試） | **zh_TW / zh_CN / zh_HK / yue_CN**；中文 CER 7.97 ≈ Whisper turbo | **原生串流**（volatile results） | Apple SDK | Swift only |
| **NVIDIA Parakeet TDT 0.6B v3** | 0.6B；CoreML 版可用 | ~1 GB | M4 Pro 110× 即時 | **無中文**（25 歐語） | TDT 可串流 | CC-BY-4.0 | FluidAudio（Swift）、NeMo、sherpa-onnx |
| **NVIDIA Canary-1B-v2** | 1B | — | 比 Whisper-L-v3 快 10× | **無中文** | 否 | CC-BY-4.0 | NeMo |
| **Moonshine Voice** | 英文 tiny→medium；**Mandarin Base 58M** | 很小 | 極低延遲 | Mandarin CER **25.76%**（差） | 英文有串流版 | MIT（新模型） | Python/JS/iOS/Android |
| **Kyutai STT**（delayed streams） | 1B（en/fr）、2.6B（en） | — | 0.5 s / 2.5 s 延遲 | **無中文** | 原生串流 | CC-BY-4.0 | Rust、MLX、PyTorch |
| **sherpa-onnx**（框架） | 依模型 | 依模型 | 依模型 | 中文模型最齊 | Zipformer / Paraformer 串流；SenseVoice 非串流 | Apache-2.0 | **C++/C/Python/JS/Java/C#/Kotlin/Swift/Go/Dart/Rust/Pascal + WASM**，Android/iOS/HarmonyOS/macOS/Win/Linux |
| ├ SenseVoice-Small（zh/yue/en/ja/ko） | ~230 MB int8（ONNX） | <1 GB | 10 s 音訊 ~70 ms（GPU）；比 Whisper-L 快 15× | AISHELL-1 CER **2.96**、AISHELL-2 3.80、WenetSpeech meeting 7.44 | 非串流（VAD 切段） | 程式碼 MIT；權重商用友善（Model License） | 同 sherpa-onnx |
| ├ Paraformer-large（zh/en） | ~220 MB int8 | <1 GB | 非自迴歸極快 | AISHELL-1 CER **1.95**；SeACo 熱詞 | 有串流版 | Model License | 同上 |
| ├ Streaming Zipformer bilingual zh-en | 50–150 MB | 小 | 手機 CPU 即時 | 中英雙語 | **原生串流** | Apache-2.0 | 同上 |
| ├ Qwen3-ASR-0.6B int8（2026-03 匯出） | ~0.6B | — | 待測 | 52 語（30 + 22 中文方言） | 非串流（MLX 版有 KV-cache 串流） | Apache-2.0 | 同上；Android APK 已有 |
| **Qwen3-ASR-1.7B / 0.6B**（MLX / vLLM） | 0.6B fp16 ~1.2 GB；1.7B ~3.4 GB | 同左 | M4 Pro 0.6B RTF 0.029（4-bit 0.018）；1.7B RTF 0.077 | AISHELL-2 WER 2.71、Fleurs-zh 2.41、CV-zh 5.35 | vLLM 串流（1.7B 平均 WER 2.84） | Apache-2.0 | Python；Swift（mlx-audio-swift，iPhone 15 Pro Max 已示範即時） |
| **FireRedASR-AED-L** | 1.1B | — | ≤60 s 片段 | AISHELL-1 CER 0.55；平均 3.18% | 否 | Apache-2.0 | Python；sherpa-onnx 支援 |
| **Breeze-ASR-25**（MediaTek） | Whisper-large-v2 大小（1.55B）；ggml ~3 GB；WhisperKit CoreML 版存在 | ~4 GB | 同 whisper large | CommonVoice zh-TW WER 7.97；CSZS 中英夾雜 13.01 | 偽串流 | **MIT** | whisper.cpp 全部綁定 |
| **Vosk**（Kaldi） | cn 1.3 GB；small-cn 輕量 | 小 | 快 | SpeechIO-02 CER 13.98 / THCHS 7.43（老舊） | 原生串流 | Apache-2.0 | Java/Kotlin、Swift、C、Rust、Go… |
| **Android SpeechRecognizer（on-device）** | 系統 | 系統 | 快 | 依機型；Pixel 進階離線語音打字僅英法德義日西 | 原生 partial | Android SDK | Kotlin/Java |

來源：[whisper.cpp README](https://github.com/ggml-org/whisper.cpp)、[faster-whisper README](https://github.com/SYSTRAN/faster-whisper)、[distil-whisper](https://github.com/huggingface/distil-whisper)、[mac-whisper-speedtest](https://github.com/anvanvan/mac-whisper-speedtest)、[Simon Willison turbo 測試](https://feeds.simonwillison.net/2024/Oct/1/whisper-large-v3-turbo-model/)、[WhisperKit benchmarks](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks)、[argmax-oss-swift](https://github.com/argmaxinc/WhisperKit)、[Parakeet/Canary 論文](https://arxiv.org/abs/2509.14128)、[parakeet-tdt-0.6b-v3 CoreML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)、[Moonshine](https://github.com/moonshine-ai/moonshine)、[Moonshine 模型清單](https://www.mintlify.com/moonshine-ai/moonshine/models/available-models)、[Kyutai DSM](https://github.com/kyutai-labs/delayed-streams-modeling)、[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)、[SenseVoice](https://github.com/FunAudioLLM/SenseVoice)、[FunAudioLLM 論文 CER 表](https://arxiv.org/pdf/2407.04051)、[FireRedASR](https://github.com/FireRedTeam/FireRedASR)、[Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)、[mlx-qwen3-asr 效能](https://github.com/heyalchang/mlx-qwen3-asr)、[Qwen3-ASR → sherpa-onnx 匯出](https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/export.html)、[Qwen3-ASR 手機部署討論](https://github.com/QwenLM/Qwen3-ASR/discussions/97)、[Qwen 官方推文：iPhone 15 Pro Max 即時](https://x.com/Alibaba_Qwen/status/2021975122853474620)、[Breeze-ASR-25](https://github.com/mtkresearch/Breeze-ASR-25)、[Breeze-ASR-25 ggml](https://huggingface.co/tsuzuri-app/Breeze-ASR-25-ggml)、[Breeze-ASR-25 WhisperKit CoreML](https://huggingface.co/fredchu/breeze-asr-25-whisperkit-coreml)、[zmxmu/whisperASR（Metal 跑 Breeze）](https://github.com/zmxmu/whisperASR)、[Vosk models](https://alphacephei.com/vosk/models)、[Android SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)

### 2.2 中文基準數字彙整（CER %，越低越好）

**公開中文測試集（來自 FunAudioLLM 與 FireRedASR 論文）**

| 模型 | AISHELL-1 | AISHELL-2 (iOS) | WenetSpeech net | WenetSpeech meeting |
|---|---|---|---|---|
| Whisper-small | 10.04 | 8.78 | 16.66 | 25.62 |
| Whisper-large-v3 | 5.14 | 4.96 | 10.48 | 18.87 |
| SenseVoice-Small | **2.96** | 3.80 | 7.84 | 7.44 |
| SenseVoice-Large | 2.09 | 3.04 | 6.01 | 6.73 |
| Paraformer-large | 1.95 / 1.68 | 2.85 | 6.74 | 6.97 |
| FireRedASR-AED-L（1.1B） | 0.55 | — | — | 平均 3.18 |
| FireRedASR-LLM-L（8.3B） | 0.76 | 2.15 | 4 個 WenetSpeech 平均 3.05 | — |

來源：[FunAudioLLM 論文](https://arxiv.org/pdf/2407.04051)、[FireRedASR 論文](https://arxiv.org/html/2501.14350v1)、[FireRedASR GitHub](https://github.com/FireRedTeam/FireRedASR)

**Qwen3-ASR 官方（WER，中文以字計）**

| 測試集 | Qwen3-ASR-1.7B | Whisper-large-v3 | GPT-4o |
|---|---|---|---|
| AISHELL-2 test | **2.71** | 5.06 | 4.24 |
| WenetSpeech net / meeting | **4.97 / 5.88** | 9.86 / 19.11 | 15.30 / 32.27 |
| Fleurs-zh | **2.41** | 4.09 | 2.44 |
| Common Voice zh | **5.35** | 12.91 | 6.32 |

來源：[Qwen3-ASR GitHub](https://github.com/QwenLM/Qwen3-ASR)、[Qwen3-ASR 技術報告](https://arxiv.org/pdf/2601.21337)

**GigaSpeechBench（2026，真實場景，含商用 API）**

| 系統 | 普通話垂直領域 CER | 中文方言 CER（6 方言平均） |
|---|---|---|
| FunASR-realtime | **3.12** | **22.79** |
| Qwen3.5-Omni-Plus | 3.36 | 27.22 |
| SeedASR（ByteDance） | 3.84 | 29.41 |
| Qwen3-ASR-1.7B | 3.95 | 31.74 |
| Qwen3-ASR-Flash（API） | — | 34.92 |
| ElevenLabs Scribe v2 | 5.24 | 56.08 |
| Azure | 5.92 | 41.80 |
| Gemini 3.0 Flash | 8.79 | 70.38 |
| Whisper-large-v3 | 9.83 | 60.45 |
| GPT-4o-transcribe | 15.29 | 62.15 |

來源：[GigaSpeechBench GitHub](https://github.com/SpeechColab/GigaSpeechBench)、[論文 arXiv 2606.28884](https://arxiv.org/abs/2606.28884)

**台灣華語 / 中英夾雜（Breeze-ASR-25，WER）**

| 測試集 | Whisper-large-v2 | Breeze-ASR-25 | 改善 |
|---|---|---|---|
| CommonVoice16 zh-TW | 9.84 | **7.97** | 19% |
| ASCEND overall（中英夾雜） | 21.14 | 17.74 | 16% |
| ASCEND-MIX | ~21 | 16.38 | 22% |
| CSZS zh-en（中英夾雜） | 29.49 | **13.01** | **56%** |

來源：[Breeze-ASR-25 GitHub](https://github.com/mtkresearch/Breeze-ASR-25)、[DigiTimes 報導 2025-07-01](https://www.digitimes.com/news/a20250701PD240/mediatek-ai-language-model-openai-taiwan.html)

**Apple SpeechAnalyzer vs Whisper（第三方 WhisperNotes 測試）**：中文 CER Apple Speech 7.97 = Whisper-large-v3-turbo 7.97；在韓、日、中文 Apple 都落後榜首 1.5 點以內。[來源](https://whispernotes.app/blog/apple-speech-vs-whisper)

> 注意：以上各表測試集、文字正規化（簡繁、標點、數字）都不同，**不能跨表直接比較**；只能看同一表內的相對排名。沒有任何公開基準是「台灣口音 + 中英夾雜 + 聽寫場景」，我們必須自建測試集（見第 5 節）。

### 2.3 平台別重點

**Apple（iOS 26 / macOS 26）— `SpeechAnalyzer` + `SpeechTranscriber`**
- 完全端上、模型由系統下載管理（`AssetInventory`）、支援 volatile（暫定）結果與最終結果、附 audio time range；輸出自帶標點與大小寫。[WWDC25 Session 277](https://developer.apple.com/videos/play/wwdc2025/277/)
- `SpeechTranscriber.supportedLocales` 回傳 42 個 locale，含 `zh_TW`、`zh_CN`、`zh_HK`、`yue_CN`。[來源（ListenToMe issue #172）](https://github.com/tomqwu/ListenToMe/issues/172)
- 最小可行程式碼骨架（Swift）：

```swift
import Speech

let locale = Locale(identifier: "zh_TW")
let transcriber = SpeechTranscriber(locale: locale,
                                    transcriptionOptions: [],
                                    reportingOptions: [.volatileResults],
                                    attributeOptions: [.audioTimeRange])
// 確保模型已下載
if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    try await req.downloadAndInstall()
}
let analyzer = SpeechAnalyzer(modules: [transcriber])
let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
try await analyzer.start(inputSequence: inputSequence)
// 從 AVAudioEngine tap 餵 AnalyzerInput(buffer:)，再：
for try await result in transcriber.results {
    if result.isFinal { insertText(String(result.text.characters)) }
    else { showVolatile(result.text) }
}
```
- 限制：無自訂詞彙 / 熱詞 API（需靠 LLM 後處理）；沒有說話者分離；舊的 `SFSpeechRecognizer` 端上模式有 1 分鐘限制，新 API 無此限制。macOS 26 以前的 Mac 需 fallback 到 whisper.cpp / sherpa-onnx。[Apple 論壇討論](https://developer.apple.com/forums/thread/790108?page=2)

**Android**
- `SpeechRecognizer.createOnDeviceSpeechRecognizer()`（API 31+）、`isOnDeviceRecognitionAvailable()`、`checkRecognitionSupport()` 回傳 `RecognitionSupport`（supported / installed on-device languages）、`triggerModelDownload()`、`EXTRA_PARTIAL_RESULTS`、`EXTRA_SEGMENTED_SESSION`。[來源](https://developer.android.com/reference/android/speech/SpeechRecognizer)
- 實務問題：離線語言由 Google 語音服務決定且依機型／地區不同；Pixel「進階語音打字」只列英法德義日西。中文離線品質與可用性不保證，因此 Android 端上主力應該是 **sherpa-onnx 自帶模型**，系統 SpeechRecognizer 當備援。[Live Transcribe 離線說明](https://support.google.com/accessibility/android/answer/9158064)

**sherpa-onnx（跨平台共用核心）**
- 一套 C API 跑遍 Android / iOS / macOS / Windows / Linux / HarmonyOS；官方提供 Swift、Kotlin、Rust、Dart（Flutter）、JS/WASM 綁定與 pre-built APK；支援 Zipformer 串流、Paraformer、SenseVoice、Whisper、Moonshine、FireRedASR、Dolphin、Qwen3-ASR。[來源](https://github.com/k2-fsa/sherpa-onnx)
- 推薦的中文組合：`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`（非串流 + Silero VAD 切句）或 `sherpa-onnx-streaming-zipformer-bilingual-zh-en`（原生串流）；需要熱詞時用 Paraformer（SeACo）或 sherpa-onnx 的 `hotwords_file`（僅限 transducer 模型）。[SeACo-Paraformer 論文](https://arxiv.org/pdf/2308.03266)

**Windows 筆電（無 NVIDIA GPU）**
- SenseVoice-Small int8 在 CPU 上遠快於即時（非自迴歸，比 Whisper-Large 快 15×），RAM < 1 GB；Whisper large 在純 CPU 筆電不實用（faster-whisper small int8 處理 13 min 要 1m42s，large 更慢）。Vulkan 後端的 whisper.cpp 可用 iGPU 但品質受限於 Whisper。
- 有 NVIDIA GPU 的桌機：faster-whisper large-v2 int8 2.9 GB VRAM、13 min 音訊 59 s；或 Qwen3-ASR-1.7B via vLLM。

**Whisper 系列的 zh-TW 陷阱**
- Whisper 把簡繁都當 `zh`，輸出會隨機簡繁混用；解法是 `initial_prompt` 給一段繁體中文（例如「以下是普通話的句子，使用繁體中文。」）或事後用 OpenCC `s2twp` 轉換。[Whisper discussion #277](https://github.com/openai/whisper/discussions/277)、[FUTO VoiceInput issue](https://gitlab.futo.org/alex/voiceinput/-/issues/1)
- `large-v3-turbo` 的最終插入字數（幻覺指標）1601 vs `large-v3` 124，且在粵語 CER 是榜首的 5.6 倍。[來源](https://arxiv.org/pdf/2502.12414)、[handy.computer 模型頁](https://models.handy.computer/models/whisper-large-v3-turbo)

---

## 3. 推薦矩陣

| 需求 | 首選 | 次選 | 理由 |
|---|---|---|---|
| **zh-TW 雲端最佳品質** | ElevenLabs Scribe v2（批次 $0.22/hr）/ v2 Realtime（$0.39/hr） | Azure（$1/hr，CER 5.92%）；Deepgram Nova-3 `zh-TW`（2026-03 新增，待實測） | 獨立基準普通話 CER 5.24% 為商用 API 最佳；<150 ms；有 keyterm；但方言差、繁體輸出需實測 |
| **中英夾雜雲端** | `gpt-transcribe`（`languages: ["zh","en"]` + prompt） | Soniox v5（單模型多語切換）；Voxtral Realtime | OpenAI 新模型 AA-WER 3.31%，但中文仍是弱項，需以自建測試集驗證 |
| **Mac 本地最佳** | macOS 26 `SpeechAnalyzer`（zh_TW，零成本） | sherpa-onnx + SenseVoice-Small（macOS 14–15）；Breeze-ASR-25 ggml via whisper.cpp Metal（高品質、慢） | Apple 原生串流、免模型管理；中文 CER ≈ Whisper turbo；需更高品質時用 Qwen3-ASR-0.6B MLX（M4 Pro RTF 0.03） |
| **iPhone 本地** | iOS 26 `SpeechTranscriber` | sherpa-onnx SenseVoice-Small int8（~230 MB）；Qwen3-ASR-0.6B via mlx-audio-swift | WhisperKit large-v3-turbo 在 iPhone 15 Pro Max RTF 2.41（慢於即時），不適合聽寫 |
| **Android 本地** | sherpa-onnx + SenseVoice-Small 或 streaming Zipformer zh-en | 系統 `createOnDeviceSpeechRecognizer`（若 `RecognitionSupport` 有 zh-TW） | Google 離線中文不保證；sherpa-onnx 有 Kotlin 綁定與 APK 範例 |
| **Windows/Linux 本地** | sherpa-onnx + SenseVoice-Small（CPU）；有 NVIDIA 則 Qwen3-ASR-1.7B | whisper.cpp（Vulkan/CUDA）+ Breeze-ASR-25 | 非自迴歸模型在純 CPU 筆電才能即時 |
| **最便宜雲端** | Groq whisper-large-v3-turbo $0.04/hr（免費 8 hr/日） | Soniox ~$0.10/hr；Gemini 2.5 Flash ~$0.115/hr；Alibaba Qwen3-ASR-Flash ~$0.126/hr | Groq 品質受限於 Whisper turbo 的中文問題；Soniox / Qwen 性價比高但繁體輸出與資料落地待確認 |
| **最快串流** | ElevenLabs Scribe v2 Realtime <150 ms | Voxtral Realtime <200 ms（可自架）；Gladia 103 ms partial；Fireworks 300 ms | 聽寫場景「放開熱鍵 → 文字出現」的體感延遲主要來自最後一段的 finalize，串流可把它壓到 <300 ms |
| **可自架的雲端等級模型** | Voxtral Realtime 4B（Apache-2.0） | Qwen3-ASR-1.7B via vLLM（Apache-2.0，串流 WER 2.84） | 當用量大到雲端費用 > 一台 GPU 時切換 |
| **台灣華語專用微調基底** | Breeze-ASR-25（MIT） | 自行用 ODC Synth / NTUML2021 資料微調 Qwen3-ASR-0.6B | 唯一針對台灣口音與中英夾雜訓練的開源模型；但是 Whisper-large-v2 大小，手機跑不動 |

---

## 4. 對我們的設計意涵

1. **引擎抽象層是必要的**：至少要同時支援「Apple 原生」「sherpa-onnx」「雲端 WebSocket」三類後端，用同一個 `TranscriptionSession` 介面（start / feed(pcm16) / partial / final / stop），讓使用者或策略引擎依網路、電量、語言、隱私設定切換。Rust core + sherpa-onnx C API 是跨 Windows/Linux/Android 最省力的路；Apple 平台則由 Swift 直接呼叫 SpeechAnalyzer，不經 Rust。
2. **「放開熱鍵到文字出現」的延遲設計**：批次 API（gpt-transcribe、Groq）必須等錄音結束才上傳，延遲 = 上傳 + 推論（通常 0.5–2 s）；串流 API 在說話中就持續產生 partial，放開熱鍵只需 finalize 最後一句（<300 ms）。Typeless 體感的關鍵在這裡，因此雲端模式應優先用串流（Scribe v2 Realtime / Nova-3 / gpt-live-transcribe），本地模式用 VAD 切句 + 非串流小模型（SenseVoice）亦可達到類似效果。
3. **簡繁正規化是產品責任，不是引擎責任**：所有 Whisper 系（含 Groq、Breeze）與多數雲端 API 都可能混出簡體；在後處理管線固定接 OpenCC（`s2twp`）並加台灣用語詞表；Apple SpeechTranscriber `zh_TW` 與 Deepgram `zh-Hant` 是少數明確以繁體為輸出目標的引擎。
4. **中英夾雜要分兩層解**：引擎層選原生雙語模型（SenseVoice zh/en、Zipformer bilingual、Breeze-ASR-25、Qwen3-ASR），不要依賴 Deepgram `multi`（不含中文）或 AssemblyAI 串流（中文只在 3.5 Pro）；後處理層用 LLM 修正英文專有名詞大小寫與中英之間空格（台灣慣例：中英之間加半形空格）。
5. **自訂詞彙 / 熱詞**：雲端用 keyterm（ElevenLabs、Deepgram、AssemblyAI）或 `prompt`（OpenAI）；本地 Apple 無此功能，sherpa-onnx 只有 transducer 模型支援 `hotwords`，Paraformer 需 SeACo。實務上最穩的是 **LLM 後處理 + 使用者個人詞典**（Typeless 的「dictionary」功能本質上就是這個），引擎層熱詞當加分。
6. **成本模型**：以重度使用者每日 60 分鐘聽寫估算，每月 30 hr：Groq $1.2、Scribe v2 $6.6、Scribe Realtime $11.7、Deepgram ~$9–14、gpt-transcribe $8.1、gpt-live-transcribe $30.6、Azure $30。若訂閱定價為 NT$300–500/月（≈$10–16），**串流 OpenAI 與 Azure 會吃掉全部毛利**，所以預設應走本地引擎，雲端僅在使用者選擇「高品質模式」時啟用，並以 ElevenLabs / Deepgram / Voxtral 自架為主。
7. **隱私訴求**：本地優先架構天然滿足「語音不出裝置」；雲端模式要明示資料保留（OpenAI 30 天、Deepgram 不存、Alibaba 落地海外）並提供 ZDR 選項或自架 Voxtral。
8. **模型體積與安裝體驗**：手機端 SenseVoice-Small int8 ~230 MB、Qwen3-ASR-0.6B int8 約 600 MB+、Whisper large 系 1.6–3 GB；iOS 26 的 Apple 模型由系統下載不佔 app 體積，這是首發選 Apple 原生最大的實務理由。
9. **評測基礎設施先行**：沒有任何公開基準覆蓋「台灣口音 + 中英夾雜 + 聽寫短句」，第一週就該錄 200–500 句（含產品名、英文術語、數字、地址）建立內部測試集，用 CER（繁體正規化後）+ 英文詞 WER + 「插入幻覺字數」三指標跑所有候選引擎。
10. **2026 下半年值得追的動向**：Qwen-Audio-3.0-ASR（2026-09 技術報告，方言 CER 9.40%，有串流版與階層式熱詞，但是否開源待確認）、OpenAI `gpt-transcribe` 的中文獨立評測、Deepgram Nova-3 zh-TW 實測、Apple iOS 27 是否開放熱詞。[Qwen-Audio-3.0-ASR 報告](https://arxiv.org/abs/2609.07549)

---

## 5. 建議的驗證實驗（兩週內可完成）

| # | 實驗 | 候選 | 指標 |
|---|---|---|---|
| E1 | 台灣口音短句 CER | Apple zh_TW、SenseVoice-Small、Qwen3-ASR-0.6B/1.7B、Breeze-ASR-25、Scribe v2、Nova-3 zh-TW、gpt-transcribe、Azure | CER（OpenCC 正規化後） |
| E2 | 中英夾雜（產品名、API 名、英文句） | 同上 | 中文 CER + 英文 WER + 大小寫正確率 |
| E3 | 熱鍵放開 → 文字落地延遲 | 本地：SenseVoice+VAD、Apple；雲端：Scribe Realtime、Nova-3、gpt-live-transcribe | p50 / p95 ms |
| E4 | 手機資源 | iPhone 15 / 中階 Android（Snapdragon 7 系） | RAM 峰值、CPU%、每分鐘耗電 |
| E5 | 幻覺率 | 靜音 / 背景音樂 / 咳嗽片段 | 插入字數 |
| E6 | 繁體一致率 | 所有引擎 | 簡體字出現率 |

---

## 6. 未解問題

1. **`gpt-transcribe` 的中文與中英夾雜實際品質**：只有 AA-WER（英文為主）數據，GigaSpeechBench 尚未納入；OpenAI 官方頁面被代理封鎖，22 語清單是否含 zh-TW 需確認。
2. **Deepgram Nova-3 `zh-TW` 的真實 CER 與繁體輸出一致性**：2026-03-31 才上線，沒有獨立基準；串流價格三個來源不一致（$0.0048 / $0.0058 / $0.0077 per min）。
3. **ElevenLabs Scribe v2 是否能指定繁體輸出**：官方 Mandarin 頁只談 WER，未見 script 參數；需用 API 實測。
4. **Apple SpeechTranscriber `zh_TW` 對中英夾雜的表現**：第三方測試只有純中文 CER 7.97；且無熱詞 API，iOS 27 是否補上未知。
5. **Qwen3-ASR-0.6B 在中階 Android 的 RTF 與記憶體**：只有 M4 Pro（RTF 0.029）與 iPhone 15 Pro Max 示範，缺 Snapdragon 7 系實測；sherpa-onnx int8 匯出為 2026-03 社群版本，品質損失未知。
6. **SenseVoice / Paraformer 權重授權的商用細節**：GitHub 說「商用友善的 Model License」，需閱讀 ModelScope 上的完整條款確認可否隨 app 分發。
7. **Breeze-ASR-25 的長音訊與手機可行性**：它是 Whisper-large-v2 大小（~3 GB ggml），手機跑不動；是否有人做 int4 / distil 版本待查；長音訊基準改善「marginal」。
8. **Voxtral Realtime 4B 自架成本**：需要多大 GPU 才能服務 N 個並發串流，Mistral 公告頁被封鎖未能讀取硬體建議。
9. **Alibaba Qwen3-ASR-Flash 的資料落地與台灣法規觀感**：價格極低但資料走新加坡 / 北京區，對隱私敏感客群可能是負面訴求。
10. **Android 系統離線辨識對 zh-TW 的覆蓋率**：各品牌 / 地區差異大，需用 `checkRecognitionSupport()` 在真機上掃一輪（Pixel、Samsung、小米、OPPO）。
11. **Qwen-Audio-3.0-ASR 是否開源**：2026-09 技術報告顯示方言 CER 9.40% 與串流版，若開源會改寫本地端中文最佳選擇。
