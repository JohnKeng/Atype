// Which app the keyboard was typing into, so the app can send the user back
// after it starts recording. iOS 26.4+ hides the host from the keyboard
// extension, but the containing app can briefly see it in UIKit's remote
// keyboard state (`_UIRemoteKeyboards.currentState.sourceBundleIdentifier`).
// Private and best-effort: the value appears ~1 s after a cold launch and
// is cleared soon after, so we observe it from launch on. Approach from
// OpenWhispr (github.com/OpenWhispr/openwhispr/pull/2365).

import UIKit

@MainActor
final class HostTracker: NSObject {
    static let shared = HostTracker()

    private(set) var lastHost: String?
    private(set) var lastSeen: Date = .distantPast
    private var observed: NSObject?

    func start() {
        guard observed == nil,
              let cls = NSClassFromString("_UIRemoteKeyboards") as? NSObject.Type else {
            DebugLog.log("app", "host tracker: _UIRemoteKeyboards unavailable")
            return
        }
        let sel = NSSelectorFromString("sharedRemoteKeyboards")
        guard cls.responds(to: sel),
              let shared = cls.perform(sel)?.takeUnretainedValue() as? NSObject,
              shared.responds(to: NSSelectorFromString("currentState")) else {
            DebugLog.log("app", "host tracker: no currentState")
            return
        }
        shared.addObserver(self, forKeyPath: "currentState", options: [.new, .initial], context: nil)
        observed = shared
        DebugLog.log("app", "host tracker: observing")
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let state = change?[.newKey] as? NSObject
        let sel = NSSelectorFromString("sourceBundleIdentifier")
        let bundle = (state?.responds(to: sel) ?? false) ? state?.perform(sel)?.takeUnretainedValue() as? String : nil
        Task { @MainActor in self.record(bundle) }
    }

    private func record(_ bundle: String?) {
        guard let bundle, !bundle.isEmpty, !bundle.hasPrefix("com.atype.") else { return }
        lastHost = bundle
        lastSeen = Date()
        DebugLog.log("app", "host tracker: \(bundle)")
    }

    /// The host seen in the last few seconds, waiting up to `wait` for it.
    func recentHost(wait: Duration = .seconds(2)) async -> String? {
        let deadline = ContinuousClock.now + wait
        while ContinuousClock.now < deadline {
            if Date().timeIntervalSince(lastSeen) < 6, let lastHost { return lastHost }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// URL that reopens an app, for the apps people type in most.
    /// Apps whose URL scheme starts something new (Claude and ChatGPT open
    /// a new chat), so returning by URL would lose the user's conversation.
    static let schemeResets: Set<String> = ["com.anthropic.claude", "com.openai.chat"]

    /// Bring an installed app to the front as it was, through the private
    /// LSApplicationWorkspace (may be refused on recent iOS; false then).
    static func activate(bundleID: String) -> Bool {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return false }
        let getDefault = NSSelectorFromString("defaultWorkspace")
        let open = NSSelectorFromString("openApplicationWithBundleID:")
        guard cls.responds(to: getDefault),
              let workspace = cls.perform(getDefault)?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: open) else { return false }
        typealias Open = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let imp = workspace.method(for: open)
        return unsafeBitCast(imp, to: Open.self)(workspace, open, bundleID as NSString)
    }

    static let schemes: [String: String] = [
        "jp.naver.line": "line://",
        "com.apple.MobileSMS": "ichat://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.mobilemail": "message://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.google.Gmail": "googlegmail://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.tinyspeck.chatlyio": "slack://",
        "net.whatsapp.WhatsApp": "whatsapp://",
        "ph.telegra.Telegraph": "tg://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.facebook.Facebook": "fb://",
        "com.burbn.instagram": "instagram://",
        "com.burbn.barcelona": "barcelona://",
        "com.atebits.Tweetie2": "twitter://",
        "com.tencent.xin": "weixin://",
        "com.hammerandchisel.discord": "discord://",
        "notion.id": "notion://",
        "md.obsidian": "obsidian://",
        "com.openai.chat": "chatgpt://",
        "com.anthropic.claude": "claude://",
        "com.google.chrome.ios": "googlechrome://",
        "com.apple.mobilesafari": "x-safari-https://",
        "com.google.GoogleMobile": "google://",
        "com.evernote.iPhone.Evernote": "evernote://",
        "com.microsoft.skype.teams": "msteams://",
    ]
}
