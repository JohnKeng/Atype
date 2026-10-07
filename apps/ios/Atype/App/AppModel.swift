// App state: recording sessions, the text pipeline, settings, shared config.

import AtypeCore
import AVFoundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case processing
    }

    // Session
    var phase: Phase = .idle
    var commandMode = false
    var liveFinal = ""
    var liveVolatile = ""
    var lastEntry: HistoryEntry?
    var errorMessage: String?

    // Data
    var config = SharedConfig()
    let history = HistoryStore()
    var historyVersion = 0  // bump to refresh views that read `history`
    var folderName = "尚未授權（暫存在這支 iPhone）"
    var folderPicked: Bool { SharedFolder.picked() != nil }

    // Settings (UserDefaults; the API key is in the Keychain)
    var polishDictation: Bool { didSet { defaults.set(polishDictation, forKey: "polishDictation") } }
    var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: "autoCopy") } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    var baseURL: String { didSet { defaults.set(baseURL, forKey: "baseURL") } }
    var commandTimeout: Double { didSet { defaults.set(commandTimeout, forKey: "commandTimeout") } }
    var apiKey: String { didSet { Keychain.set(apiKey, for: "llm") } }

    private let defaults = UserDefaults.standard
    private let engine = AppleSpeechEngine()

    init() {
        polishDictation = defaults.object(forKey: "polishDictation") as? Bool ?? false
        autoCopy = defaults.object(forKey: "autoCopy") as? Bool ?? true
        model = defaults.string(forKey: "model") ?? LLMSettings.defaultModel
        baseURL = defaults.string(forKey: "baseURL") ?? LLMSettings.geminiBaseURL.absoluteString
        commandTimeout = defaults.object(forKey: "commandTimeout") as? Double ?? 12
        apiKey = Keychain.get("llm") ?? ""
        reloadConfig()
        engine.onPartial = { [weak self] final, volatile in
            self?.liveFinal = final
            self?.liveVolatile = volatile
        }
    }

    // MARK: Shared config

    func reloadConfig() {
        let folder = SharedFolder.current
        folderName = SharedFolder.picked() == nil ? "尚未授權（暫存在這支 iPhone）" : SharedFolder.displayPath(folder)
        config = SharedConfig.load(from: folder)
    }

    func saveConfig() {
        do {
            try config.save(to: SharedFolder.current)
            config = SharedConfig.load(from: SharedFolder.current)
        } catch {
            errorMessage = "無法儲存設定：\(error.localizedDescription)"
        }
    }

    func pickFolder(_ url: URL) {
        do {
            try SharedFolder.pick(url)
            reloadConfig()
        } catch {
            errorMessage = "無法使用這個資料夾：\(error.localizedDescription)"
        }
    }

    func resetFolder() {
        SharedFolder.reset()
        reloadConfig()
    }

    var commandPromptName: String {
        config.prompt(id: config.commandPromptID)?.name ?? "萬用口令"
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Recording

    var isBusy: Bool { phase != .idle }

    func toggle(command: Bool) {
        switch phase {
        case .idle: Task { await start(command: command) }
        case .recording: Task { await finish() }
        default: break
        }
    }

    func start(command: Bool) async {
        guard phase == .idle else { return }
        errorMessage = nil
        commandMode = command
        liveFinal = ""
        liveVolatile = ""
        phase = .preparing
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "請到「設定 → 隱私權與安全性 → 麥克風」允許 Atype"
            phase = .idle
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            try await engine.start(contextualStrings: config.dictionary.map(\.term))
            phase = .recording
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = "無法開始錄音：\(error.localizedDescription)"
            releaseAudio()
            phase = .idle
        }
    }

    func finish() async {
        guard phase == .recording else { return }
        phase = .processing
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let raw = await engine.stop()
        releaseAudio()
        guard !raw.isEmpty else {
            errorMessage = "沒有聽到內容"
            phase = .idle
            return
        }
        var pipeline = Pipeline(config: config, llm: hasKey ? LLMClient(settings: LLMSettings(baseURL: URL(string: baseURL.trimmingCharacters(in: .whitespaces)) ?? LLMSettings.geminiBaseURL, model: model, apiKey: apiKey)) : nil)
        pipeline.commandTimeout = .seconds(commandTimeout)
        let mode: DictationMode = commandMode ? .command : .dictation(polish: polishDictation)
        let result = await pipeline.run(raw, mode: mode)
        let entry = HistoryEntry(
            raw: raw,
            text: result.text,
            polished: result.polished != nil,
            command: commandMode,
            promptName: result.promptID.flatMap { config.prompt(id: $0)?.name },
            error: commandMode && !hasKey ? "沒有設定 API key，只做了本機處理" : result.llmError.map(Self.describe)
        )
        history.add(entry, brainFolder: SharedFolder.picked())
        historyVersion += 1
        lastEntry = entry
        if autoCopy { UIPasteboard.general.string = entry.text }
        phase = .idle
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func cancel() async {
        await engine.cancel()
        releaseAudio()
        phase = .idle
    }

    /// Give the microphone back right away (no lingering orange dot, no
    /// call-quality audio in the car).
    private func releaseAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func describe(_ error: String) -> String {
        if error == "timeout" { return "AI 超過時間沒回應，貼的是本機處理的版本" }
        if error.contains("noKey") { return "沒有設定 API key" }
        return "AI 失敗，貼的是本機處理的版本"
    }
}
