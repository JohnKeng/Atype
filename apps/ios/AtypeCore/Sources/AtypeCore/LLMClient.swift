// Calls an OpenAI-compatible chat endpoint (Gemini by default) with a prompt
// whose `${output}` is replaced by the transcription, like the Mac app's
// "legacy" post-processing path.

import Foundation

public struct LLMSettings: Codable, Equatable, Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String

    public static let geminiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
    public static let defaultModel = "models/gemini-3.5-flash-lite"
    /// Earlier default; moved to `defaultModel` once (fixes more homophones
    /// at the same ~1 s, tested 2026-10-08).
    public static let previousDefaultModel = "models/gemini-3.1-flash-lite"

    public init(baseURL: URL = geminiBaseURL, model: String = defaultModel, apiKey: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }
}

public enum LLMError: Error, Equatable {
    case noKey
    case http(Int, String)
    case emptyResponse
}

public struct LLMClient: Sendable {
    public let settings: LLMSettings
    public let session: URLSession

    public init(settings: LLMSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    /// Fill `${output}` with the transcript and return the model's answer.
    public func complete(prompt: String, transcript: String) async throws -> String {
        guard !settings.apiKey.isEmpty else { throw LLMError.noKey }
        var req = URLRequest(url: settings.baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        let content = prompt.replacingOccurrences(of: "${output}", with: transcript)
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LLMError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        struct Reply: Decodable {
            struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
            let choices: [Choice]
        }
        let text = try JSONDecoder().decode(Reply.self, from: data).choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    /// Models usable for plain chat, the same filter as the Mac model picker.
    public static func isChatModel(_ id: String) -> Bool {
        let markers = ["live", "realtime", "streaming", "native-audio", "tts", "transcribe", "whisper",
                       "image", "imagen", "nano-banana", "veo", "lyria", "embedding", "aqa", "robotics",
                       "computer-use", "deep-research", "antigravity", "moderation", "dall-e"]
        let l = id.lowercased()
        return !markers.contains { l.contains($0) }
    }
}
