// Atype's text pipeline after speech recognition, shared by the iPhone app
// and anything else in Swift. Same order as the Mac app:
// dictionary → (LLM, within a time budget) → deterministic Chinese layer.

import Foundation

public enum DictationMode: Sendable, Equatable {
    /// Plain dictation. `polish` runs the cleanup prompt.
    case dictation(polish: Bool)
    /// AI command: the command prompt (default 萬用口令).
    case command
}

public struct PipelineResult: Sendable, Equatable {
    public var raw: String
    public var text: String
    /// Set when the LLM answered in time.
    public var polished: String?
    public var llmError: String?
    public var promptID: String?
}

public struct Pipeline: Sendable {
    public var config: SharedConfig
    public var llm: LLMClient?
    public var zhPostEnabled = true
    public var cleanupTimeout: Duration = .milliseconds(2500)
    public var commandTimeout: Duration = .seconds(12)

    public init(config: SharedConfig, llm: LLMClient?) {
        self.config = config
        self.llm = llm
    }

    /// Prompt for this mode, with the dictionary's known terms appended.
    func prompt(for mode: DictationMode) -> Prompt? {
        let id: String
        switch mode {
        case .dictation(let polish):
            guard polish else { return nil }
            id = Presets.cleanupID
        case .command:
            id = config.commandPromptID
        }
        guard var p = config.prompt(id: id) else { return nil }
        if let block = PersonalDictionary.knownTermsPrompt(config.dictionary) { p.prompt += block }
        return p
    }

    public func run(_ raw: String, mode: DictationMode) async -> PipelineResult {
        var text = PersonalDictionary.apply(raw, config.dictionary)
        var result = PipelineResult(raw: raw, text: text)
        if let llm, let prompt = prompt(for: mode), !text.trimmingCharacters(in: .whitespaces).isEmpty {
            result.promptID = prompt.id
            let budget = mode == .command ? commandTimeout : cleanupTimeout
            let input = text
            do {
                let answer = try await withThrowingTaskGroup(of: String?.self) { group in
                    group.addTask { try await llm.complete(prompt: prompt.prompt, transcript: input) }
                    group.addTask { try await Task.sleep(for: budget); return nil }
                    let first = try await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                if let answer {
                    result.polished = answer
                    text = answer
                } else {
                    result.llmError = "timeout"
                }
            } catch {
                result.llmError = String(describing: error)
            }
        }
        result.text = zhPostEnabled ? ZhPost.polish(text) : text
        if let p = result.polished, zhPostEnabled { result.polished = ZhPost.polish(p) }
        return result
    }
}
