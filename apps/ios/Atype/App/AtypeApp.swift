import SwiftUI

@main
struct AtypeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.green)
                .onChange(of: scenePhase) { _, phase in
                    // Pick up prompt/dictionary edits made on the Mac.
                    if phase == .active, !model.isBusy { model.reloadConfig() }
                }
        }
    }
}

enum Theme {
    static let green = Color(red: 0.247, green: 0.498, blue: 0.227)
    static let greenSoft = Color(red: 0.416, green: 0.694, blue: 0.345)
    static let ai = [Color(red: 0.416, green: 0.694, blue: 0.345), Color(red: 0.184, green: 0.710, blue: 0.647),
                     Color(red: 0.545, green: 0.486, blue: 0.965), Color(red: 0.949, green: 0.702, blue: 0.294)]
    static var aiGradient: AngularGradient { AngularGradient(colors: ai + [ai[0]], center: .center) }
    static var aiLinear: LinearGradient { LinearGradient(colors: ai, startPoint: .leading, endPoint: .trailing) }
}
