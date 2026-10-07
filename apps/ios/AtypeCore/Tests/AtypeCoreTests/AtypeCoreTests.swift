import Foundation
import Testing
@testable import AtypeCore

// Same cases as the Mac app's Rust tests (zh_post.rs, dictionary.rs).

@Suite struct ZhPostTests {
    @Test func simplifiedIsConvertedWithTaiwanPhrases() {
        #expect(ZhPost.polish("这个软件的网络很好") == "這個軟體的網路很好")
        #expect(ZhPost.polish("用鼠标点一下") == "用滑鼠點一下")
    }

    @Test func traditionalTextIsLeftAlone() {
        for s in ["台北的軟體很好", "著名的後面裡面", "什麼時候", "我們明天開會"] {
            #expect(!ZhPost.hasSimplified(s), "\(s)")
            #expect(ZhPost.polish(s) == s)
        }
    }

    @Test func llmLeakInATraditionalSentenceIsFixed() {
        #expect(ZhPost.polish("我們的软件要更新") == "我們的軟體要更新")
    }

    @Test func punctuationAndSpacing() {
        #expect(ZhPost.polish("我们明天下午3:30开会,地点在Costco旁边的路易莎.") == "我們明天下午 3:30 開會，地點在 Costco 旁邊的路易莎。")
    }

    @Test func numbersUrlsAndEnglishAreUntouched() {
        #expect(ZhPost.polish("版本是3.5,網址是example.com") == "版本是 3.5，網址是 example.com")
        #expect(ZhPost.polish("Hello, world. How are you?") == "Hello, world. How are you?")
        #expect(ZhPost.polish("總共1,000元") == "總共 1,000 元")
    }

    @Test func chineseSentenceEndingAfterLatinWord() {
        #expect(ZhPost.polish("我今天push了code.") == "我今天 push 了 code。")
        #expect(ZhPost.polish("你用過GitHub?") == "你用過 GitHub？")
    }

    @Test func spacesAroundFullwidthPunctuationAreRemoved() {
        #expect(ZhPost.polish("好的 ， 我知道了 。") == "好的，我知道了。")
        #expect(ZhPost.polish("iPhone很好 ,  真的") == "iPhone 很好，真的")
    }

    @Test func percentAndSymbols() {
        #expect(ZhPost.polish("有10%的人用C++寫") == "有 10% 的人用 C++ 寫")
    }
}

@Suite struct DictionaryTests {
    let dict = [
        DictEntry(term: "iCloud", aliases: ["iclo", "icrow", "icl", "ic克l芯"]),
        DictEntry(term: "程式碼"),
        DictEntry(term: "Typeless"),
    ]

    @Test func listedAliasesAreReplaced() {
        #expect(PersonalDictionary.apply("測試一下錄音是否有丟在ic克l芯的位置。", dict) == "測試一下錄音是否有丟在iCloud的位置。")
        #expect(PersonalDictionary.apply("在icrow的新位置", dict) == "在iCloud的新位置")
        #expect(PersonalDictionary.apply("然後iclo上的儲存位置", dict) == "然後iCloud上的儲存位置")
        #expect(PersonalDictionary.apply("ICLO", dict) == "iCloud")
    }

    @Test func asciiAliasesRespectWordBoundaries() {
        #expect(PersonalDictionary.apply("include", dict) == "include")
        #expect(PersonalDictionary.apply("iclone", dict) == "iclone")
        #expect(PersonalDictionary.apply("可以取代typeless嗎？", dict) == "可以取代Typeless嗎？")
    }

    @Test func homophonesAreFoundByPinyin() {
        #expect(PersonalDictionary.apply("並且城市馬那邊看需不需要改", dict) == "並且程式碼那邊看需不需要改")
        #expect(PersonalDictionary.apply("成四碼", dict) == "程式碼")
    }

    @Test func unrelatedTextIsUntouched() {
        for s in ["我們明天下午開會", "城市很大", "程式", ""] {
            #expect(PersonalDictionary.apply(s, dict) == s)
        }
    }

    @Test func sanitize() {
        let got = PersonalDictionary.sanitize([
            DictEntry(term: "  iCloud ", aliases: [" iclo", "", "iclo", "iCloud"]),
            DictEntry(term: "   ", aliases: ["x"]),
        ])
        #expect(got == [DictEntry(term: "iCloud", aliases: ["iclo"])])
    }
}

@Suite struct ConfigAndPipelineTests {
    @Test func presetsLoadFromTheSharedJSON() {
        #expect(Presets.all.count == 10)
        #expect(Presets.all.first?.id == Presets.cleanupID)
        #expect(Presets.all.allSatisfy { $0.prompt.contains("${output}") })
    }

    @Test func sharedConfigRoundTripsAndKeepsEditedPrompts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var cfg = SharedConfig()
        cfg.prompts[0].prompt = "mine ${output}"
        cfg.prompts.removeLast()
        cfg.dictionary = [DictEntry(term: " iCloud ", aliases: ["iclo"])]
        try cfg.save(to: dir)
        let back = SharedConfig.load(from: dir)
        #expect(back.prompts[0].prompt == "mine ${output}")
        #expect(back.prompts.count == Presets.all.count)  // missing preset re-added
        #expect(back.dictionary == [DictEntry(term: "iCloud", aliases: ["iclo"])])
        #expect(back.updatedAt > .distantPast)
    }

    @Test func pipelineWithoutLLMRunsDictionaryAndZhLayer() async {
        var cfg = SharedConfig()
        cfg.dictionary = [DictEntry(term: "程式碼"), DictEntry(term: "iCloud", aliases: ["iclo"])]
        let r = await Pipeline(config: cfg, llm: nil).run("城市马放在iclo上", mode: .command)
        #expect(r.text == "程式碼放在 iCloud 上")
        #expect(r.polished == nil)
    }

    @Test func commandPromptCarriesKnownTerms() {
        var cfg = SharedConfig()
        cfg.dictionary = [DictEntry(term: "看門狗")]
        let p = Pipeline(config: cfg, llm: nil).prompt(for: .command)
        #expect(p?.id == Presets.smartID)
        #expect(p?.prompt.contains("<known_terms>\n看門狗") == true)
        #expect(Pipeline(config: cfg, llm: nil).prompt(for: .dictation(polish: false)) == nil)
    }

    @Test func modelFilter() {
        #expect(LLMClient.isChatModel("models/gemini-3.1-flash-lite"))
        #expect(!LLMClient.isChatModel("models/gemini-3.8-live"))
    }
}

@Suite struct MacFormatTests {
    /// What the Mac app's `atype::shared::push` writes (serde, RFC 3339 seconds).
    @Test func readsTheMacFile() throws {
        let json = #"{"version":1,"updated_at":"2026-10-07T10:14:01Z","prompts":[{"id":"atype_email","name":"正式信件","prompt":"x ${output}"}],"command_prompt_id":"atype_email","dictionary":[{"term":"看門狗","aliases":[]}]}"#
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent(SharedConfig.fileName))
        let cfg = SharedConfig.load(from: dir)
        #expect(cfg.commandPromptID == "atype_email")
        #expect(cfg.dictionary.first?.term == "看門狗")
        #expect(cfg.prompts.count == Presets.all.count)
        #expect(cfg.updatedAt > .distantPast)
    }

    @Test func readsTheRealSharedFileIfPresent() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/service-db/Atype")
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(SharedConfig.fileName).path) else { return }
        let cfg = SharedConfig.load(from: url)
        #expect(!cfg.dictionary.isEmpty)
        #expect(cfg.updatedAt > .distantPast)
    }
}
