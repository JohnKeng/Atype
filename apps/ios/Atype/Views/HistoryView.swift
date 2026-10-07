import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.history.entries) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(e.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            if e.command { Label(e.promptName ?? "AI", systemImage: "sparkles").font(.caption2).foregroundStyle(Theme.ai[2]) }
                            else if e.polished { Image(systemName: "sparkles").font(.caption2).foregroundStyle(Theme.green) }
                        }
                        Text(e.text).lineLimit(6)
                        if e.polished, e.raw != e.text {
                            Text("原文：\(e.raw)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .contextMenu {
                        Button("複製", systemImage: "doc.on.doc") { UIPasteboard.general.string = e.text }
                        Button("複製原文", systemImage: "doc.plaintext") { UIPasteboard.general.string = e.raw }
                    }
                    .swipeActions { Button("複製") { UIPasteboard.general.string = e.text }.tint(Theme.green) }
                }
                .onDelete { idx in
                    model.history.delete(Set(idx.map { model.history.entries[$0].id }))
                    model.historyVersion += 1
                }
            }
            .id(model.historyVersion)
            .overlay {
                if model.history.entries.isEmpty {
                    ContentUnavailableView("還沒有紀錄", systemImage: "waveform", description: Text("到首頁點麥克風說一句話"))
                }
            }
            .navigationTitle("歷史")
        }
    }
}
