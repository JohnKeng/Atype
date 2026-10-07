import AtypeCore
import SwiftUI

struct DictionaryView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DictEntry?
    @State private var editingIndex: Int?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(filtered.enumerated()), id: \.element) { _, e in
                        Button {
                            editingIndex = model.config.dictionary.firstIndex(of: e)
                            editing = e
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.term).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(e.aliases.isEmpty ? (isChinese(e.term) ? "自動比對同音字" : "只修正大小寫") : e.aliases.joined(separator: "、"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        let remove = idx.map { filtered[$0] }
                        model.config.dictionary.removeAll { remove.contains($0) }
                        model.saveConfig()
                    }
                } footer: {
                    Text("中文詞只要填正確寫法，同音的錯字會自動修正（「程式碼」會修好「城市馬」）；英文詞把聽錯的拼法填進錯法。和 Mac 共用同一份。")
                }
            }
            .searchable(text: $search)
            .navigationTitle("詞典")
            .toolbar {
                Button { editingIndex = nil; editing = DictEntry(term: "") } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { e in
                DictEntryEditor(entry: e) { saved in
                    if let i = editingIndex { model.config.dictionary[i] = saved } else { model.config.dictionary.insert(saved, at: 0) }
                    model.saveConfig()
                }
            }
            .refreshable { model.reloadConfig() }
        }
    }

    private var filtered: [DictEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.config.dictionary }
        return model.config.dictionary.filter { $0.term.localizedCaseInsensitiveContains(q) || $0.aliases.contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    private func isChinese(_ s: String) -> Bool { s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
}

extension DictEntry: @retroactive Identifiable {
    public var id: String { term + "|" + aliases.joined(separator: ",") }
}

struct DictEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: DictEntry
    @State private var aliasText = ""
    let onSave: (DictEntry) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("正確寫法") { TextField("例如 iCloud、程式碼", text: $entry.term).autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section {
                    TextField("例如 iclo、icrow", text: $aliasText, axis: .vertical).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Text("常見錯法（用逗號或、分隔）") } footer: { Text("中文詞可以留空，會自動比對同音字。") }
            }
            .navigationTitle(entry.term.isEmpty ? "新增詞條" : entry.term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        entry.aliases = aliasText.split(whereSeparator: { ",，、;；".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(entry.term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { aliasText = entry.aliases.joined(separator: "、") }
        }
    }
}
