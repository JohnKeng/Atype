// The link between the Atype keyboard and the Atype app.
//
// Apple does not let keyboard extensions use the microphone, so the app
// records and the keyboard is a remote control (same model as Typeless and
// Wispr Flow):
//   keyboard → app: Darwin notifications (start / start AI / stop / cancel),
//                   or opening atype://start when the app is not on standby;
//   app → keyboard: state, live text and the result in the App Group's
//                   UserDefaults, plus a "changed" Darwin notification.
// Both sides compile this file.

import Foundation

enum Bridge {
    static let group = "group.com.atype.ios"
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: group) ?? .standard

    enum Phase: String {
        case idle, preparing, recording, processing
    }

    enum Note: String, CaseIterable {
        case start = "com.atype.ios.start"
        case startCommand = "com.atype.ios.startCommand"
        case stop = "com.atype.ios.stop"
        case cancel = "com.atype.ios.cancel"
        case changed = "com.atype.ios.changed"
        case level = "com.atype.ios.level"
    }

    private enum Key {
        static let phase = "phase"
        static let commandMode = "commandMode"
        static let partial = "partial"
        static let resultID = "resultID"
        static let resultText = "resultText"
        static let consumedID = "consumedID"
        static let standbyUntil = "standbyUntil"
        static let heartbeat = "heartbeat"
        static let message = "message"
        static let hostBundleID = "hostBundleID"
        static let level = "level"
    }

    /// Microphone level 0…1, updated ~12 times a second while recording.
    static var level: Double {
        get { defaults.double(forKey: Key.level) }
        set { defaults.set(newValue, forKey: Key.level) }
    }

    /// Bundle id of the app the keyboard is typing into, when iOS tells us
    /// (used to send the user back after the app starts recording).
    static var hostBundleID: String? {
        get { defaults.string(forKey: Key.hostBundleID) }
        set { defaults.set(newValue, forKey: Key.hostBundleID) }
    }

    // MARK: State written by the app

    static var phase: Phase {
        get { Phase(rawValue: defaults.string(forKey: Key.phase) ?? "") ?? .idle }
        set { defaults.set(newValue.rawValue, forKey: Key.phase) }
    }

    static var commandMode: Bool {
        get { defaults.bool(forKey: Key.commandMode) }
        set { defaults.set(newValue, forKey: Key.commandMode) }
    }

    static var partial: String {
        get { defaults.string(forKey: Key.partial) ?? "" }
        set { defaults.set(newValue, forKey: Key.partial) }
    }

    /// A short note for the keyboard (an error, or "沒有聽到內容").
    static var message: String {
        get { defaults.string(forKey: Key.message) ?? "" }
        set { defaults.set(newValue, forKey: Key.message) }
    }

    static var standbyUntil: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: Key.standbyUntil)) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: Key.standbyUntil) }
    }

    /// Updated every second while the app holds the microphone.
    static var heartbeat: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: Key.heartbeat)) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: Key.heartbeat) }
    }

    /// The app can start recording without being opened.
    static var appIsWarm: Bool {
        Date().timeIntervalSince(heartbeat) < 3 && (standbyUntil > Date() || phase != .idle)
    }

    static func publishResult(_ text: String) {
        defaults.set(text, forKey: Key.resultText)
        defaults.set(UUID().uuidString, forKey: Key.resultID)
    }

    /// The result the keyboard has not inserted yet, if any; marks it taken.
    static func takeResult() -> String? {
        guard let id = defaults.string(forKey: Key.resultID), id != defaults.string(forKey: Key.consumedID),
              let text = defaults.string(forKey: Key.resultText) else { return nil }
        defaults.set(id, forKey: Key.consumedID)
        return text
    }

    /// Forget a pending result (a new take started).
    static func discardResult() {
        defaults.set(defaults.string(forKey: Key.resultID), forKey: Key.consumedID)
    }

    // MARK: Darwin notifications

    static func post(_ note: Note) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(note.rawValue as CFString), nil, nil, true)
    }

    /// Call `handler` on the main queue whenever `note` is posted (any process).
    static func observe(_ note: Note, handler: @escaping @Sendable () -> Void) {
        DarwinObservers.shared.add(note.rawValue, handler)
    }
}

/// Keeps closures for Darwin notifications (the C API only takes a function).
final class DarwinObservers: @unchecked Sendable {
    static let shared = DarwinObservers()
    private var handlers: [String: [@Sendable () -> Void]] = [:]
    private let lock = NSLock()

    func add(_ name: String, _ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        let first = handlers[name] == nil
        handlers[name, default: []].append(handler)
        lock.unlock()
        guard first else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let me = Unmanaged<DarwinObservers>.fromOpaque(observer).takeUnretainedValue()
                me.fire(name.rawValue as String)
            },
            name as CFString, nil, .deliverImmediately)
    }

    private func fire(_ name: String) {
        lock.lock()
        let list = handlers[name] ?? []
        lock.unlock()
        DispatchQueue.main.async { list.forEach { $0() } }
    }
}
