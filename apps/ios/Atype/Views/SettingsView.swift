import AtypeCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var showKey = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
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
                    HStack {
                        Group {
                            if showKey { TextField("Gemini API key", text: $model.apiKey) } else { SecureField("Gemini API key", text: $model.apiKey) }
                        }
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                    }
                    TextField("模型", text: $model.model).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !LLMClient.isChatModel(model.model) {
                        Text("這個模型不能用來整理文字（live、TTS、圖片…），請改用 \(LLMSettings.defaultModel)").font(.caption).foregroundStyle(.orange)
                    }
                    Link("到 Google AI Studio 建立 key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                } header: { Text("Gemini") } footer: { Text("key 只存在這支 iPhone 的鑰匙圈，不會同步到 iCloud。") }

                Section {
                    LabeledContent("資料夾", value: model.folderName)
                    Button("選擇資料夾（例如 iCloud 雲碟的 service-db/Atype）") { picking = true }
                    if model.folderName != "本機（這支 iPhone）" { Button("改回本機", role: .destructive) { model.resetFolder() } }
                } header: { Text("和 Mac 共用") } footer: {
                    Text("選和 Mac 相同的資料夾，提示詞與詞典就會兩邊共用；iPhone 的紀錄寫在 atype.iphone.jsonl 與每日的 .iphone.md。")
                }

                Section {
                    Toggle("結果自動複製", isOn: $model.autoCopy)
                }
            }
            .navigationTitle("設定")
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.pickFolder(url) }
            }
        }
    }
}
