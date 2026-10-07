// Streaming on-device recognition with Apple's SpeechAnalyzer + SpeechTranscriber
// (iOS 26, zh-TW, no download beyond the system's speech assets).
//
// The microphone (AVAudioEngine + one tap) and a take (one SpeechAnalyzer)
// are separate: between takes the microphone can stay open on standby, so
// the keyboard can start the next take without opening the app. Buffers
// are only forwarded while a take is running.

import AVFoundation
import Speech

/// Where the tap sends audio: the current take, or nowhere. Touched from the
/// realtime audio thread, so it is a locked box, not actor state.
final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var _level: Double = 0

    /// Smoothed input level 0…1 of the current take.
    var level: Double {
        lock.lock(); defer { lock.unlock() }
        return _level
    }

    func attach(_ c: AsyncStream<AnalyzerInput>.Continuation, converter: AVAudioConverter?, target: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        continuation = c
        self.converter = converter
        self.target = target
    }

    func detach() {
        lock.lock(); defer { lock.unlock() }
        continuation?.finish()
        continuation = nil
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let continuation, let target else { _level = 0; return }
        if let data = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            // -50 dB … -10 dB → 0 … 1, then smooth (fast attack, slow release).
            let db = 20 * log10(max(rms, 1e-6))
            let v = Double(min(max((db + 50) / 40, 0), 1))
            _level = v > _level ? v : _level * 0.75 + v * 0.25
        }
        guard let converted = Self.convert(buffer, with: converter, to: target) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }
}

@MainActor
final class AppleSpeechEngine {
    enum EngineError: LocalizedError {
        case localeUnsupported
        case noAudioFormat
        var errorDescription: String? {
            switch self {
            case .localeUnsupported: "這支 iPhone 不支援台灣中文的本機語音辨識"
            case .noAudioFormat: "無法取得語音辨識的音訊格式"
            }
        }
    }

    static let locale = Locale(identifier: "zh-TW")

    /// Which Apple recognizer runs a take.
    enum Model: String, CaseIterable, Identifiable {
        /// SpeechTranscriber: the newer long-form model.
        case speech
        /// DictationTranscriber: the model behind the system keyboard's
        /// dictation, tuned for short dictated sentences, with punctuation.
        case dictation
        var id: String { rawValue }
        var title: String {
            switch self {
            case .speech: "Apple 長篇辨識（SpeechTranscriber）"
            case .dictation: "Apple 聽寫辨識（DictationTranscriber）"
            }
        }
    }

    var model: Model = .dictation

    /// Called with (finalized, volatile) text while recording.
    var onPartial: ((String, String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let sink = AudioSink()
    private var tapInstalled = false
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var finalized = ""
    private var volatile = ""

    var level: Double { sink.level }

    /// The microphone is open (recording or on standby).
    var micOpen: Bool { audioEngine.isRunning }

    /// Reserve the locale for this app (required before asking about its
    /// assets), then download the model if it is not on the device yet.
    static func ensureAssets(for transcriber: any SpeechModule, locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            _ = try await AssetInventory.reserve(locale: locale)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Open the microphone (no-op when already open). Buffers go nowhere
    /// until a take starts.
    func openMic() throws {
        guard !audioEngine.isRunning else { return }
        let input = audioEngine.inputNode
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0), block: Self.makeTap(sink))
            tapInstalled = true
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func closeMic() {
        sink.detach()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
    }

    /// Start a take: a fresh analyzer fed by the (opened) microphone.
    func start(contextualStrings: [String]) async throws {
        finalized = ""
        volatile = ""
        let module: any SpeechModule
        let results: AsyncThrowingStream<(String, Bool), Error>
        switch model {
        case .speech:
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) else { throw EngineError.localeUnsupported }
            // No .fastResults: it trades accuracy for latency, and the
            // keyboard cannot show live text while we run in the background.
            let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
            try await Self.ensureAssets(for: t, locale: locale)
            module = t
            results = Self.stream(t.results) { (String($0.text.characters), $0.isFinal) }
        case .dictation:
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Self.locale) else { throw EngineError.localeUnsupported }
            let t = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [])
            try await Self.ensureAssets(for: t, locale: locale)
            module = t
            results = Self.stream(t.results) { (String($0.text.characters), $0.isFinal) }
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextualStrings]
            try? await analyzer.setContext(context)
        }

        let micFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: micFormat) else {
            throw EngineError.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: target)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            do {
                for try await (text, isFinal) in results {
                    guard let self else { return }
                    if isFinal {
                        self.finalized += text
                        self.volatile = ""
                    } else {
                        self.volatile = text
                    }
                    self.onPartial?(self.finalized, self.volatile)
                }
            } catch {}
        }

        sink.attach(continuation, converter: micFormat == target ? nil : AVAudioConverter(from: micFormat, to: target), target: target)
        try openMic()
    }

    /// Both transcribers' results as (text, isFinal).
    private static func stream<S: AsyncSequence & Sendable>(_ seq: S, _ map: @escaping @Sendable (S.Element) -> (String, Bool)) -> AsyncThrowingStream<(String, Bool), Error> where S.Element: Sendable {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    for try await r in seq { c.yield(map(r)) }
                    c.finish()
                } catch { c.finish(throwing: error) }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// End the take and return its text. The microphone stays open.
    func stop() async -> String {
        sink.detach()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        return (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        sink.detach()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }

    /// The tap runs on a realtime audio thread, so it must not inherit the
    /// main-actor isolation of this class (Swift 6 traps when it does).
    nonisolated private static func makeTap(_ sink: AudioSink) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in sink.push(buffer) }
    }
}
