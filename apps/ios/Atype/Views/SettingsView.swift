import AtypeCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var showKey = false
    @FocusState private var editing: Bool

    /// Picking a provider fills in its URL and a sensible model.
    private var providerBinding: Binding<String> {
        Binding(
            get: { Provider.all.first { $0.url == model.baseURL }?.id ?? "custom" },
            set: { id in
                guard let p = Provider.all.first(where: { $0.id == id }), !p.url.isEmpty else { return }
                model.baseURL = p.url
                model.model = p.model
            }
        )
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("辨識引擎", selection: $model.recognizer) {
                        ForEach(AppleSpeechEngine.Model.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: { Text("語音辨識") } footer: {
                    Text("兩個都在 iPhone 本機辨識，聲音不上傳。「聽寫辨識」是系統鍵盤聽寫用的模型，短句通常比較準；可以兩個都試試。")
                }

                Section {
                    TextField("例如：\n署名：John\n職稱：技術長\n公司：樂衍", text: Binding(
                        get: { model.config.profile },
                        set: { model.config.profile = $0 }
                    ), axis: .vertical)
                    .lineLimit(3...8)
                    .focused($editing)
                    Button("儲存我的資料") {
                        editing = false
                        model.saveConfig()
                    }
                } header: { Text("我的資料") } footer: {
                    Text("AI 寫信、回訊息需要署名、職稱、公司時會直接用這裡的資料，不會再標【待補】。和 Mac 共用。")
                }

                Section {
                    NavigationLink { PromptLibraryView() } label: {
                        LabeledContent("提示詞", value: model.commandPromptName)
                    }
                    Toggle("聽寫也用 AI 整理（會慢 1～2 秒）", isOn: $model.polishDictation)
                    LabeledContent("AI 指令時間預算") {
                        Stepper("\(Int(model.commandTimeout)) 秒", value: $model.commandTimeout, in: 4...30, step: 1)
                    }
                } header: { Text("AI") } footer: {
                    Text("聽寫預設只在手機本機處理；AI 指令會依提示詞寫成信件、訊息、會議記錄等格式。")
                }

                Section {
                    Picker("服務", selection: providerBinding) {
                        ForEach(Provider.all) { Text($0.name).tag($0.id) }
                    }
                    TextField("API 網址", text: $model.baseURL).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                    HStack {
                        Group {
                            if showKey { TextField("API key", text: $model.apiKey) } else { SecureField("API key", text: $model.apiKey) }
                        }
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                    }
                    TextField("模型", text: $model.model).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !LLMClient.isChatModel(model.model) {
                        Text("這個模型不能用來整理文字（live、TTS、圖片…），請換一般的對話模型").font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("AI 模型") } footer: {
                    Text("支援 OpenAI 相容格式（/chat/completions）的 API key：Gemini、OpenAI、OpenRouter、Groq，或自架的相容代理。key 只存在這支 iPhone 的鑰匙圈，不會同步到 iCloud。")
                }

                Section {
                    LabeledContent("目前", value: model.folderName)
                    Button(model.folderPicked ? "改用其他資料夾" : "授權預設資料夾（\(SharedFolder.defaultDisplay)）") { picking = true }
                    if model.folderPicked { Button("取消授權", role: .destructive) { model.resetFolder() } }
                } header: { Text("和 Mac 共用的資料夾") } footer: {
                    Text("預設是 \(SharedFolder.defaultDisplay)，和 Mac 版相同。iOS 規定要你親手授權一次：選擇器會直接停在這個資料夾，按「打開」即可。提示詞與詞典兩邊共用；iPhone 的紀錄寫在 atype.iphone.jsonl 與每日的 .iphone.md。")
                }

                Section {
                    Picker("待命時間", selection: $model.standbyMinutes) {
                        Text("不待命").tag(0)
                        Text("1 分鐘").tag(1)
                        Text("3 分鐘").tag(3)
                        Text("10 分鐘").tag(10)
                        Text("30 分鐘").tag(30)
                    }
                    if model.standbyActive {
                        Button("現在關閉麥克風", role: .destructive) { model.shutdownMic() }
                    }
                } header: { Text("鍵盤") } footer: {
                    Text("用完後麥克風保持開啟的時間。待命中在鍵盤上點麥克風不必跳回 Atype；時間到就真的關掉麥克風。到「設定 → 一般 → 鍵盤 → 鍵盤」加入 Atype，並打開「允許完全取用」。")
                }

                Section {
                    Toggle("結果自動複製", isOn: $model.autoCopy)
                } footer: {
                    Text("每次說完都把結果放進剪貼簿；鍵盤沒把字插進去時，長按輸入框就能貼上。")
                }
            }
            .navigationTitle("設定")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        editing = false
                        model.saveConfig()
                    }
                }
            }
            .sheet(isPresented: $picking) {
                FolderPicker(initial: SharedFolder.picked() ?? SharedFolder.defaultICloudURL) { model.pickFolder($0) }
                    .ignoresSafeArea()
            }
        }
    }
}

struct Provider: Identifiable {
    let id: String
    let name: String
    let url: String
    let model: String

    static let all = [
        Provider(id: "gemini", name: "Gemini", url: LLMSettings.geminiBaseURL.absoluteString, model: LLMSettings.defaultModel),
        Provider(id: "openai", name: "OpenAI", url: "https://api.openai.com/v1", model: "gpt-5-mini"),
        Provider(id: "openrouter", name: "OpenRouter", url: "https://openrouter.ai/api/v1", model: "google/gemini-3.1-flash-lite"),
        Provider(id: "groq", name: "Groq", url: "https://api.groq.com/openai/v1", model: "llama-3.3-70b-versatile"),
        Provider(id: "custom", name: "自訂", url: "", model: ""),
    ]
}
