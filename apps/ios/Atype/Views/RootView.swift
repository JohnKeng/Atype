import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("首頁", systemImage: "waveform") { HomeView() }
            Tab("歷史", systemImage: "clock.arrow.circlepath") { HistoryView() }
            Tab("詞典", systemImage: "book.closed") { DictionaryView() }
            Tab("設定", systemImage: "gearshape") { SettingsView() }
        }
    }
}
