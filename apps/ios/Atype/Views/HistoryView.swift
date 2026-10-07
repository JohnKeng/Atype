import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false

    /// Entries grouped by calendar day, newest day first.
    private var days: [(Date, [HistoryEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: model.history.entries) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private func title(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "今天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_TW")))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.0) { day, entries in
                Section(title(day)) {
                ForEach(entries) { e in
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
                    model.history.delete(Set(idx.map { entries[$0].id }))
                    model.historyVersion += 1
                }
                }
                }
            }
            .id(model.historyVersion)
            .overlay {
                if model.history.entries.isEmpty {
                    ContentUnavailableView("還沒有紀錄", systemImage: "waveform", description: Text("到首頁點麥克風說一句話"))
                }
            }
            .navigationTitle("歷史")
            .toolbar {
                if !model.history.entries.isEmpty {
                    Button("清除全部", role: .destructive) { confirmClear = true }
                }
            }
            .confirmationDialog("清除這支 iPhone 上的全部歷史紀錄？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除全部", role: .destructive) {
                    model.history.delete(Set(model.history.entries.map(\.id)))
                    model.historyVersion += 1
                }
            } message: {
                Text("只清除 App 裡的列表；已寫進 iCloud 第二大腦的紀錄不會被刪除。")
            }
        }
    }
}
