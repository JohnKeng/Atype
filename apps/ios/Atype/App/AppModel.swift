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
        standbyMinutes = defaults.object(forKey: "standbyMinutes") as? Int ?? 3
        reloadConfig()
        engine.onPartial = { [weak self] final, volatile in
            guard let self else { return }
            self.liveFinal = final
            self.liveVolatile = volatile
            Bridge.partial = final + volatile
            Bridge.post(.changed)
            DebugLog.log("app", "partial final=\(final.count) volatile=\(volatile.count) bg=\(UIApplication.shared.applicationState != .active)")
        }
        listenToKeyboard()
        HostTracker.shared.start()
    }

    // MARK: Shared config

    /// The shared file exists in iCloud but is not on this phone yet; saving
    /// now would overwrite the Mac's prompts and dictionary with defaults.
    var sharedFileDownloading = false
    private var downloadRetry: Task<Void, Never>?

    func reloadConfig() {
        let folder = SharedFolder.current
        folderName = SharedFolder.picked() == nil ? "尚未授權（暫存在這支 iPhone）" : SharedFolder.displayPath(folder)
        sharedFileDownloading = !SharedFolder.ensureDownloaded(folder.appendingPathComponent(SharedConfig.fileName))
        config = SharedConfig.load(from: folder)
        Self.diagnose(folder)
        DebugLog.log("app", "config loaded from \(folderName): dict=\(config.dictionary.count) downloading=\(sharedFileDownloading)")
        if sharedFileDownloading { retryUntilDownloaded() }
    }

    /// Log why the shared file can or cannot be read (temporary diagnostics).
    static func diagnose(_ folder: URL) {
        let file = folder.appendingPathComponent(SharedConfig.fileName)
        let fm = FileManager.default
        let listing = (try? fm.contentsOfDirectory(atPath: folder.path))?.joined(separator: ",") ?? "list failed"
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey, .fileSizeKey]
        let values = try? file.resourceValues(forKeys: keys)
        var readResult = "ok"
        do { let d = try Data(contentsOf: file); readResult = "\(d.count) bytes" } catch { readResult = "\(error)" }
        DebugLog.log("app", "diag path=\(folder.path) exists=\(fm.fileExists(atPath: file.path)) ubiq=\(String(describing: values?.isUbiquitousItem)) status=\(String(describing: values?.ubiquitousItemDownloadingStatus)) size=\(String(describing: values?.fileSize)) read=\(readResult.prefix(200)) list=\(listing.prefix(200))")
    }

    /// Poll for a few seconds while iCloud brings the shared file down.
    private func retryUntilDownloaded() {
        downloadRetry?.cancel()
        downloadRetry = Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let url = SharedFolder.current.appendingPathComponent(SharedConfig.fileName)
                if SharedFolder.ensureDownloaded(url) {
                    self.sharedFileDownloading = false
                    self.config = SharedConfig.load(from: SharedFolder.current)
                    DebugLog.log("app", "shared file downloaded: dict=\(self.config.dictionary.count)")
                    return
                }
            }
        }
    }

    func saveConfig() {
        guard !sharedFileDownloading else {
            errorMessage = "iCloud 還在下載和 Mac 共用的設定，請稍後再改"
            return
        }
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
    /// The current take was started from the keyboard (show the "go back" hint).
    var fromKeyboard = false
    /// Minutes the microphone stays open after a take so the keyboard can
    /// start the next one without opening the app. 0 = close right away.
    var standbyMinutes: Int { didSet { defaults.set(standbyMinutes, forKey: "standbyMinutes") } }
    private var standbyTimer: Timer?
    private var heartbeatTimer: Timer?
    private var levelTimer: Timer?
    /// Microphone level 0…1 while recording (for the app's own UI too).
    var level: Double = 0

    func toggle(command: Bool) {
        switch phase {
        case .idle: Task { await start(command: command) }
        case .recording: Task { await finish() }
        default: break
        }
    }

    /// atype://start?mode=command|dictation (opened by the keyboard).
    func handle(url: URL) {
        guard url.scheme == "atype", url.host == "start" else { return }
        let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "mode" })?.value == "command"
        fromKeyboard = true
        if phase == .idle { Task { await start(command: command) } }
    }

    /// Commands the keyboard sends while the app runs in the background.
    func listenToKeyboard() {
        Bridge.observe(.start) { Task { @MainActor in await self.startFromKeyboard(command: false) } }
        Bridge.observe(.startCommand) { Task { @MainActor in await self.startFromKeyboard(command: true) } }
        Bridge.observe(.stop) { Task { @MainActor in await self.finish() } }
        Bridge.observe(.cancel) { Task { @MainActor in await self.cancel() } }
        publish()
    }

    private func startFromKeyboard(command: Bool) async {
        fromKeyboard = true
        await start(command: command)
    }

    /// Tell the keyboard what is going on.
    private func publish() {
        Bridge.phase = switch phase {
        case .idle: .idle
        case .preparing: .preparing
        case .recording: .recording
        case .processing: .processing
        }
        Bridge.commandMode = commandMode
        Bridge.partial = liveFinal + liveVolatile
        Bridge.message = errorMessage ?? ""
        Bridge.post(.changed)
    }

    func start(command: Bool) async {
        guard phase == .idle else { return }
        errorMessage = nil
        commandMode = command
        liveFinal = ""
        liveVolatile = ""
        Bridge.discardResult()
        phase = .preparing
        publish()
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "請到「設定 → 隱私權與安全性 → 麥克風」允許 Atype"
            phase = .idle
            publish()
            return
        }
        do {
            // On standby the session is already active; touching it again from
            // the background fails (OSStatus 561…), so only set it up when the
            // microphone is closed.
            if !engine.micOpen {
                let session = AVAudioSession.sharedInstance()
                // Mix with music and keep Bluetooth output on A2DP: no ducking,
                // no call-quality audio while the microphone is open.
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
                try session.setActive(true)
            }
            standbyTimer?.invalidate()
            startHeartbeat()
            try await engine.start(contextualStrings: config.dictionary.map(\.term))
            phase = .recording
            publish()
            startLevelMeter()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DebugLog.log("app", "recording fromKeyboard=\(fromKeyboard) command=\(command)")
            if fromKeyboard { returnToHost() }
        } catch {
            DebugLog.log("app", "start failed: \(error)")
            errorMessage = "無法開始錄音：\(error.localizedDescription)"
            shutdownMic()
            phase = .idle
            publish()
        }
    }

    func finish() async {
        guard phase == .recording else { return }
        phase = .processing
        publish()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Finish the work even if iOS would suspend us (no standby).
        let task = UIApplication.shared.beginBackgroundTask(withName: "atype.process")
        defer { UIApplication.shared.endBackgroundTask(task) }
        let raw = await engine.stop()
        DebugLog.log("app", "stopped raw=\(raw.count) chars: \(raw.prefix(40))")
        scheduleStandby()
        guard !raw.isEmpty else {
            errorMessage = "沒有聽到內容"
            phase = .idle
            publish()
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
        Bridge.publishResult(entry.text)
        DebugLog.log("app", "published \(entry.text.count) chars")
        if autoCopy && !fromKeyboard { UIPasteboard.general.string = entry.text }
        fromKeyboard = false
        phase = .idle
        publish()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// ✕: drop this take and close the microphone (no standby).
    func cancel() async {
        await engine.cancel()
        fromKeyboard = false
        shutdownMic()
        phase = .idle
        publish()
    }

    /// Send the user back to the app they were typing in: the host the
    /// keyboard state showed at launch/switch, reopened by its URL scheme.
    private func returnToHost() {
        Task { @MainActor in
            let fromKeyboard = Bridge.hostBundleID
            Bridge.hostBundleID = nil
            var found = fromKeyboard
            if found == nil { found = await HostTracker.shared.recentHost() }
            guard let host = found else {
                DebugLog.log("app", "return: host unknown")
                return
            }
            guard host != "<null>", let scheme = HostTracker.schemes[host], let url = URL(string: scheme) else {
                DebugLog.log("app", "return: no scheme for \(host)")
                return
            }
            let ok = await UIApplication.shared.open(url)
            DebugLog.log("app", "return: open \(scheme) for \(host) -> \(ok)")
        }
    }

    private func startLevelMeter() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            Task { @MainActor in
                guard self.phase == .recording else {
                    self.levelTimer?.invalidate()
                    self.level = 0
                    Bridge.level = 0
                    Bridge.post(.level)
                    return
                }
                self.level = self.engine.level
                Bridge.level = self.level
                Bridge.post(.level)
            }
        }
    }

    // MARK: Standby

    private func scheduleStandby() {
        standbyTimer?.invalidate()
        guard standbyMinutes > 0 else {
            shutdownMic()
            return
        }
        let until = Date().addingTimeInterval(Double(standbyMinutes) * 60)
        Bridge.standbyUntil = until
        standbyTimer = Timer.scheduledTimer(withTimeInterval: Double(standbyMinutes) * 60, repeats: false) { _ in
            Task { @MainActor in if self.phase == .idle { self.shutdownMic() } }
        }
    }

    /// Close the microphone and give audio back (no lingering orange dot).
    func shutdownMic() {
        standbyTimer?.invalidate()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        engine.closeMic()
        Bridge.standbyUntil = .distantPast
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        publish()
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        Bridge.heartbeat = Date()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in Bridge.heartbeat = Date() }
        }
    }

    var standbyActive: Bool { engine.micOpen && phase == .idle }

    static func describe(_ error: String) -> String {
        if error == "timeout" { return "AI 超過時間沒回應，貼的是本機處理的版本" }
        if error.contains("noKey") { return "沒有設定 API key" }
        return "AI 失敗，貼的是本機處理的版本"
    }
}
