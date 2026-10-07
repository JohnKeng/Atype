import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var command = false
    @State private var spin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .center) {
                        Text("Atype").font(.system(size: 34, weight: .bold))
                        Spacer()
                        // Same cream as the background, so no frame or cut-out.
                        Image("Logo").resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                    }
                    if model.fromKeyboard && (model.phase == .recording || model.phase == .preparing) { backHint }
                    modePicker
                    if command && !model.isBusy {
                        NavigationLink { PromptLibraryView() } label: {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(Theme.ai[2])
                                Text("提示詞").foregroundStyle(.secondary)
                                Text(model.commandPromptName).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    micButton
                    statusLine
                    if model.phase == .recording || model.phase == .processing { liveCard }
                    if let e = model.lastEntry, model.phase == .idle { resultCard(e) }
                    if let err = model.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    }
                    StatsView().id(model.historyVersion)
                }
                .padding()
            }
            .background(Color("Cream").ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Opened from the keyboard: send the user back to their app to talk.
    private var backHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.up.backward.circle.fill").font(.title).foregroundStyle(Theme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("點左上角「◀」回到原本的 App").font(.headline)
                Text("Atype 會在背景繼續聽。說完在鍵盤上點停止，字就會插進去。").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var modePicker: some View {
        Picker("模式", selection: $command) {
            Text("聽寫").tag(false)
            Text("✦ AI 指令").tag(true)
        }
        .pickerStyle(.segmented)
        .disabled(model.isBusy)
    }

    private var isAI: Bool { model.isBusy ? model.commandMode : command }

    private var micButton: some View {
        Button { model.toggle(command: command) } label: {
            ZStack {
                Circle().fill(model.phase == .recording ? Color.red.opacity(0.9) : (isAI ? Color(.systemBackground) : Theme.green))
                    .frame(width: 148, height: 148)
                if isAI {
                    Circle().strokeBorder(Theme.aiGradient, lineWidth: 6)
                        .frame(width: 148, height: 148)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: spin)
                }
                Group {
                    switch model.phase {
                    case .preparing, .processing: ProgressView().controlSize(.large).tint(isAI ? Theme.green : .white)
                    case .recording: Image(systemName: "stop.fill").font(.system(size: 48))
                    case .idle: Image(systemName: isAI ? "sparkles" : "mic.fill").font(.system(size: 54, weight: .medium))
                    }
                }
                .foregroundStyle(isAI && model.phase != .recording ? AnyShapeStyle(Theme.aiLinear) : AnyShapeStyle(.white))
            }
            .shadow(color: (isAI ? Theme.ai[2] : Theme.green).opacity(0.35), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .preparing || model.phase == .processing)
        .accessibilityLabel(model.phase == .recording ? "停止" : "開始說話")
        .onAppear { spin = true }
    }

    private var statusLine: some View {
        Group {
            switch model.phase {
            case .idle: Text(command ? "點一下說內容或大綱，開頭可以說「回信」「條列」…" : "點一下開始說話，再點一下結束")
            case .preparing: Text("準備麥克風…")
            case .recording: Text(model.commandMode ? "✦ AI 指令錄音中，再點一下結束" : "錄音中，再點一下結束")
            case .processing: Text(model.commandMode ? "✦ AI 撰寫中…" : (model.polishDictation ? "✦ AI 整理中…" : "處理中…"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var liveCard: some View {
        (Text(model.liveFinal) + Text(model.liveVolatile).foregroundStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resultCard(_ e: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if e.command {
                    Label(e.promptName ?? "AI 指令", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Theme.ai[2])
                } else {
                    Label(e.polished ? "AI 整理" : "本機", systemImage: e.polished ? "sparkles" : "iphone").font(.caption.bold()).foregroundStyle(Theme.green)
                }
                Spacer()
                if model.autoCopy { Text("已複製").font(.caption).foregroundStyle(.secondary) }
            }
            Text(e.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if let err = e.error { Text(err).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { UIPasteboard.general.string = e.text } label: { Label("複製", systemImage: "doc.on.doc") }
                ShareLink(item: e.text) { Label("分享", systemImage: "square.and.arrow.up") }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = Calendar.current
        let today = model.history.totals(since: cal.startOfDay(for: .now))
        let week = model.history.totals(since: cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now)
        let all = model.history.totals(since: .distantPast)
        HStack(spacing: 12) {
            stat("今天", today)
            stat("本週", week)
            stat("全部", all)
        }
    }

    private func stat(_ title: String, _ t: (chars: Int, entries: Int)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(t.chars)").font(.title2.bold()).foregroundStyle(Theme.green).monospacedDigit()
            Text("字 · \(t.entries) 筆").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
