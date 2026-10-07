import AtypeCore
import SwiftUI

struct PromptLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var newPrompt: Prompt?

    var body: some View {
        List {
            Section {
                ForEach(model.config.prompts) { p in
                    NavigationLink {
                        PromptEditor(prompt: p)
                    } label: {
                        HStack {
                            Text(p.name)
                            Spacer()
                            if p.id == model.config.commandPromptID {
                                Label("使用中", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Theme.ai[2])
                            }
                        }
                    }
                }
                .onDelete { idx in
                    guard model.config.prompts.count > idx.count else { return }
                    model.config.prompts.remove(atOffsets: idx)
                    model.config.addMissingPresets()
                    model.saveConfig()
                }
            } footer: {
                Text("AI 指令用「使用中」的那一個；聽寫打開 AI 整理時固定用「整理口語」。和 Mac 共用同一份，刪掉的內建提示詞會自動補回。")
            }
        }
        .navigationTitle("提示詞")
        .toolbar {
            Button {
                newPrompt = Prompt(id: "custom_\(UUID().uuidString.prefix(8).lowercased())", name: "", prompt: "<transcript>\n${output}\n</transcript>\n\n")
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $newPrompt) { p in
            NavigationStack { PromptEditor(prompt: p, isNew: true) }
        }
    }
}

struct PromptEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var prompt: Prompt
    var isNew = false

    var body: some View {
        Form {
            Section("名稱") { TextField("例如：週報", text: $prompt.name) }
            Section {
                TextEditor(text: $prompt.prompt)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 320)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: { Text("內容") } footer: { Text("${output} 會換成你說的話（必須有）。") }
            if !isNew, prompt.id != model.config.commandPromptID {
                Section {
                    Button("設為 AI 指令使用", systemImage: "sparkles") {
                        model.config.commandPromptID = prompt.id
                        model.saveConfig()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "新增提示詞" : prompt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") {
                    if let i = model.config.prompts.firstIndex(where: { $0.id == prompt.id }) {
                        model.config.prompts[i] = prompt
                    } else {
                        model.config.prompts.append(prompt)
                    }
                    model.saveConfig()
                    dismiss()
                }
                .disabled(prompt.name.trimmingCharacters(in: .whitespaces).isEmpty || !prompt.prompt.contains("${output}"))
            }
        }
    }
}
