// Streaming on-device recognition with Apple's SpeechAnalyzer + SpeechTranscriber
// (iOS 26, zh-TW, no download beyond the system's speech assets).
// Microphone → AVAudioEngine tap → converted to the analyzer's format →
// AnalyzerInput stream. Finalized text accumulates; volatile text is shown
// live. Dictionary terms are passed as contextual strings.

import AVFoundation
import Speech

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

    /// Called with (finalized, volatile) text while recording.
    var onPartial: ((String, String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var finalized = ""
    private var volatile = ""

    /// Make sure the zh-TW speech model is on the device (downloads once).
    static func prepareAssets() async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw EngineError.localeUnsupported
        }
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        try await ensureAssets(for: t, locale: locale)
    }

    /// Reserve the locale for this app (required before asking about its
    /// assets), then download the model if it is not on the device yet.
    static func ensureAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            let ok = try await AssetInventory.reserve(locale: locale)
            NSLog("Atype speech: reserve %@ -> %d (reserved before: %@)", locale.identifier, ok ? 1 : 0, reserved.map(\.identifier).joined(separator: ","))
        }
        NSLog("Atype speech: status %@, installed %@", String(describing: await AssetInventory.status(forModules: [transcriber])), await SpeechTranscriber.installedLocales.map(\.identifier).joined(separator: ","))
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    func start(contextualStrings: [String]) async throws {
        finalized = ""
        volatile = ""
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) else {
            throw EngineError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        self.transcriber = transcriber
        try await Self.ensureAssets(for: transcriber, locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextualStrings]
            try? await analyzer.setContext(context)
        }

        let input = audioEngine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: micFormat) else {
            throw EngineError.noAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: target)
        converter = micFormat == target ? nil : AVAudioConverter(from: micFormat, to: target)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        try await analyzer.start(inputSequence: stream)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        if result.isFinal {
                            self.finalized += text
                            self.volatile = ""
                        } else {
                            self.volatile = text
                        }
                        self.onPartial?(self.finalized, self.volatile)
                    }
                }
            } catch {}
        }

        let converter = self.converter
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: target) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Stop the microphone, let the analyzer finish and return the full text.
    func stop() async -> String {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        let text = (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    func cancel() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
