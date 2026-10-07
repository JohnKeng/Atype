// The part of Atype's settings shared by the Mac and the iPhone through iCloud
// Drive: prompts, which prompt the AI command uses, and the dictionary.
// Stored as `atype-shared.json` in the second-brain folder
// (iCloud Drive/service-db/Atype by default). Secrets (API keys) never go here.

import Foundation

public struct Prompt: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public init(id: String, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

public enum Profile {
    /// Block appended to prompts, or nil when the profile is empty.
    public static func prompt(_ profile: String) -> String? {
        let p = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        return "\n<about_me>\n\(p)\n</about_me>\n以上是使用者本人的資料。需要署名、自稱、職稱、公司或聯絡方式時，直接使用這些資料，不要再標【待補】。\n"
    }
}

public enum Presets {
    public static let cleanupID = "default_improve_transcriptions"
    public static let smartID = "atype_smart"

    /// The built-in prompts, the same file the Mac app's Rust tests check.
    public static let all: [Prompt] = {
        guard let url = Bundle.module.url(forResource: "presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let prompts = try? JSONDecoder().decode([Prompt].self, from: data)
        else { return [] }
        return prompts
    }()
}

public struct SharedConfig: Codable, Equatable, Sendable {
    public static let fileName = "atype-shared.json"

    public var version: Int = 1
    public var updatedAt: Date = .distantPast
    public var prompts: [Prompt] = Presets.all
    /// Prompt used by the AI command (Mac: the one selected in 後處理).
    public var commandPromptID: String = Presets.smartID
    public var dictionary: [DictEntry] = []
    /// About the user (name to sign with, title, company…), given to every
    /// prompt so signatures and greetings are filled in, not marked 【待補】.
    public var profile: String = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, prompts, dictionary, profile
        case updatedAt = "updated_at"
        case commandPromptID = "command_prompt_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        prompts = try c.decodeIfPresent([Prompt].self, forKey: .prompts) ?? Presets.all
        commandPromptID = try c.decodeIfPresent(String.self, forKey: .commandPromptID) ?? Presets.smartID
        dictionary = try c.decodeIfPresent([DictEntry].self, forKey: .dictionary) ?? []
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? ""
    }

    /// Built-in prompts the file does not have yet (by id); edited ones stay.
    public mutating func addMissingPresets() {
        for p in Presets.all where !prompts.contains(where: { $0.id == p.id }) {
            prompts.append(p)
        }
        if !prompts.contains(where: { $0.id == commandPromptID }) {
            commandPromptID = prompts.first(where: { $0.id == Presets.smartID })?.id ?? prompts.first?.id ?? Presets.smartID
        }
    }

    public func prompt(id: String) -> Prompt? { prompts.first { $0.id == id } }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Read `atype-shared.json` from `folder`; a missing or broken file gives
    /// the defaults. Uses file coordination so iCloud sees a consistent file.
    public static func load(from folder: URL) -> SharedConfig {
        let url = folder.appendingPathComponent(fileName)
        var result = SharedConfig()
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { u in
            if let data = try? Data(contentsOf: u), let cfg = try? decoder.decode(SharedConfig.self, from: data) {
                result = cfg
            }
        }
        result.addMissingPresets()
        return result
    }

    /// Write with a fresh `updatedAt`. Throws when the folder is not writable.
    public func save(to folder: URL) throws {
        var copy = self
        copy.updatedAt = Date()
        copy.dictionary = PersonalDictionary.sanitize(copy.dictionary)
        let data = try Self.encoder.encode(copy)
        let url = folder.appendingPathComponent(Self.fileName)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }
}
