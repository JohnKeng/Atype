import SwiftUI

private let green = Color(red: 0.247, green: 0.498, blue: 0.227)
private let aiColors = [Color(red: 0.416, green: 0.694, blue: 0.345), Color(red: 0.184, green: 0.710, blue: 0.647),
                        Color(red: 0.545, green: 0.486, blue: 0.965), Color(red: 0.949, green: 0.702, blue: 0.294)]

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let globe: GlobeKey
    @Environment(\.colorScheme) private var scheme
    @State private var spin = false

    private var keyFill: Color { scheme == .dark ? Color(white: 0.42) : .white }
    private var softFill: Color { scheme == .dark ? Color(white: 0.28) : Color(white: 0.82) }
    /// One step darker than the keyboard background (delete, @, cancel).
    private var darkFill: Color { scheme == .dark ? Color(white: 0.33) : Color(red: 199 / 255, green: 201 / 255, blue: 206 / 255) }

    var body: some View {
        if model.phase != .idle {
            sessionView
        } else {
            idleView
        }
    }

    /// While the app records or works: one big button centred in the
    /// keyboard and one line of text under it (positions as in Typeless).
    private var sessionView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Text("Atype").font(.system(size: 18, weight: .bold))
                    .position(x: 18 + 30, y: 30)
                if model.phase == .recording || model.phase == .preparing {
                    Button(action: model.cancel) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .frame(width: 48, height: 48).background(darkFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消")
                    .position(x: w - 42, y: 34)
                }
                Button { model.mic(command: model.commandMode) } label: {
                    ZStack {
                        Circle().fill(scheme == .dark ? Color.white : Color(white: 17 / 255)).frame(width: 108, height: 108)
                        if model.commandMode {
                            Circle().strokeBorder(AngularGradient(colors: aiColors + [aiColors[0]], center: .center), lineWidth: 4)
                                .frame(width: 108, height: 108)
                                .rotationEffect(.degrees(spin ? 360 : 0))
                                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: spin)
                        }
                        if model.phase == .recording {
                            Dots(color: scheme == .dark ? .black : .white, level: model.level)
                        } else {
                            ProgressView().tint(scheme == .dark ? .black : .white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase != .recording)
                .position(x: w / 2, y: h / 2 + 4)
                Text(sessionText).font(.system(size: 16)).foregroundStyle(.secondary)
                    .position(x: w / 2, y: h / 2 + 4 + 54 + 26)
            }
        }
        .foregroundStyle(.primary)
        .onAppear { spin = true }
    }

    private var sessionText: String {
        switch model.phase {
        case .recording: model.commandMode ? "✦ AI 指令，再次點擊以完成" : "再次點擊以完成"
        case .processing: model.commandMode ? "✦ AI 撰寫中…" : (model.aiDictation ? "✦ AI 整理中…" : "整理中…")
        default: "準備中…"
        }
    }

    /// Ready: the common voice-keyboard layout (measured from Typeless on a
    /// 430 pt wide iPhone): hint and mic centered, delete and @ on the right,
    /// AI bottom-left, return bottom-center.
    private var idleView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Text("Atype").font(.system(size: 18, weight: .bold))
                    .position(x: 18 + 30, y: 30)
                if model.hasFullAccess {
                    modeSwitch.position(x: w - 70, y: 30)
                }
                if !model.hasFullAccess {
                    fullAccessNote.frame(width: w - 36).position(x: w / 2, y: 170)
                } else {
                    Text(model.message.isEmpty ? "點擊開始說話" : model.message)
                        .font(.system(size: 16))
                        .foregroundStyle(model.message.isEmpty ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .frame(width: w - 40)
                        .position(x: w / 2, y: 100)
                    micButton.position(x: w / 2, y: 155)
                    RepeatKey(action: model.backspace) {
                        Image(systemName: "delete.left").font(.system(size: 19))
                            .frame(width: 48, height: 48).background(darkFill, in: Circle())
                    }
                    .position(x: w - 42, y: 198)
                    Button { model.insert("@") } label: {
                        Text("@").font(.system(size: 21)).frame(width: 48, height: 48).background(darkFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: w - 42, y: 258)
                    Button { model.insert("\n") } label: {
                        Text("換行").font(.system(size: 18)).frame(width: 118, height: 47).background(keyFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .position(x: w / 2, y: 258)
                    aiButton.position(x: 42, y: 258)
                    historyKey("arrow.uturn.forward", enabled: !model.redoStack.isEmpty, action: model.redo)
                        .position(x: 42, y: 96)
                    historyKey("arrow.uturn.backward", enabled: !model.undoStack.isEmpty, action: model.undo)
                        .position(x: 42, y: 156)
                }
                if model.needsGlobe {
                    globe.frame(width: 44, height: 36).position(x: 42, y: geo.size.height - 22)
                }
            }
        }
        .foregroundStyle(.primary)
        .onAppear { spin = true }
    }

    private func historyKey(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(width: 48, height: 48)
                .background(darkFill.opacity(enabled ? 1 : 0.5), in: Circle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol.contains("backward") ? "復原" : "重做")
    }

    private var header: some View {
        HStack {
            Text("Atype").font(.system(size: 18, weight: .bold))
            Spacer()
        }
        .frame(height: 36)
    }

    private var statusText: String {
        switch model.phase {
        case .idle: model.warm ? "點麥克風直接說" : "點麥克風會先打開 Atype"
        case .preparing: "準備中…"
        case .recording: model.commandMode ? "✦ AI 指令聆聽中…" : "聆聽中…"
        case .processing: model.commandMode ? "✦ AI 撰寫中…" : "整理中…"
        }
    }

    private var isAISession: Bool { model.phase != .idle && model.commandMode }

    private var micButton: some View {
        Button { model.mic(command: false) } label: {
            ZStack {
                Capsule()
                    .fill(model.phase == .recording ? Color.red : (scheme == .dark ? Color.white : Color(white: 17 / 255)))
                    .frame(width: 147, height: 59)
                Group {
                    switch model.phase {
                    case .recording: Image(systemName: "stop.fill")
                    case .preparing, .processing: ProgressView().tint(scheme == .dark ? .black : .white)
                    case .idle: Image(systemName: model.warm ? "mic.fill" : "mic")
                    }
                }
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(model.phase == .recording ? .white : (scheme == .dark ? .black : .white))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.phase == .recording ? "停止" : "開始說話")
    }

    /// Top-right: what the main mic does by default. 手機 = on-device only
    /// (instant); AI = also cleaned up by the AI (1–2 s slower, needs a key).
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeSegment("手機", on: !model.aiDictation) { model.setAIDictation(false) }
            modeSegment("✦ AI", on: model.aiDictation) { model.setAIDictation(true) }
        }
        .padding(3)
        .background(darkFill, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("說話預設")
    }

    private func modeSegment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .regular))
                .frame(width: 56, height: 30)
                .background(on ? keyFill : Color.clear, in: Capsule())
                .foregroundStyle(on && title.contains("AI")
                                 ? AnyShapeStyle(LinearGradient(colors: aiColors, startPoint: .leading, endPoint: .trailing))
                                 : AnyShapeStyle(on ? Color.primary : Color.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var aiButton: some View {
        Button { model.mic(command: true) } label: {
            ZStack {
                Circle().fill(keyFill).frame(width: 48, height: 48)
                Circle().strokeBorder(AngularGradient(colors: aiColors + [aiColors[0]], center: .center), lineWidth: 2)
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: aiColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .idle)
        .accessibilityLabel("AI 指令")
    }

    private var fullAccessNote: some View {
        VStack(spacing: 6) {
            Text("需要「允許完全取用」").font(.headline)
            Text("到「設定 → 一般 → 鍵盤 → 鍵盤 → Atype」打開「允許完全取用」，鍵盤才能請 Atype 錄音並把字放回來。你說的話只在這支 iPhone 上辨識。")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }
}

/// Seven dots that rise with the microphone level (a little wave across
/// them), and lie flat as dots when it is quiet: "I hear you".
struct Dots: View {
    let color: Color
    let level: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    let center = 1 - abs(Double(i) - 3) / 4          // middle dots move most
                    let wave = 0.6 + 0.4 * sin(t * 9 + Double(i) * 1.3)
                    let h = 6 + 30 * level * center * wave
                    Capsule().fill(color).frame(width: 6, height: h)
                }
            }
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

/// A key that repeats while held (delete).
struct RepeatKey<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var timer: Timer?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                if pressing {
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        Task { @MainActor in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in Task { @MainActor in action() } }
                        }
                    }
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            })
    }
}
