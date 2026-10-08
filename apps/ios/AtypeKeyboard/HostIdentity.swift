// Who is the keyboard typing into? iOS 26.4+ hides `_hostBundleID`, so this
// combines what is still reachable (private, best-effort, every step guarded
// with `responds(to:)` because KVC on a missing key raises):
//  1. `-[UIInputViewController _hostApplicationBundleIdentifier]`;
//  2. `_hostProcessIdentifier` (pid) matched against the keyboard arbiter's
//     client state (pid + sourceBundleIdentifier), after forcing
//     `+[_UIKeyboardArbiterClient enabled]` to YES (approach from
//     github.com/getdictus/dictus-ios/pull/538);
//  3. the arbiter's current sourceBundleIdentifier on its own.

import ObjectiveC
import UIKit

enum HostIdentity {
    nonisolated(unsafe) private static var pidToBundle: [Int: String] = [:]

    nonisolated(unsafe) private static var originalEnabled: IMP?

    /// Force `+[_UIKeyboardArbiterClient enabled]` to YES only while `body`
    /// reads the host, then restore it: the arbiter also carries the text
    /// input session, and leaving it forced on can stop inserted text from
    /// reaching the app.
    private static func withArbiterEnabled<T>(_ body: () -> T) -> T {
        guard let cls = NSClassFromString("_UIKeyboardArbiterClient"),
              let m = class_getClassMethod(cls, NSSelectorFromString("enabled")) else { return body() }
        let block: @convention(block) (AnyObject) -> Bool = { _ in true }
        let original = method_setImplementation(m, imp_implementationWithBlock(block))
        defer { method_setImplementation(m, original) }
        return body()
    }

    /// Kept for callers; no longer leaves the arbiter patched.
    static func enableArbiter() {}

    private static func read(_ key: String, from o: NSObject?) -> Any? {
        guard let o, o.responds(to: NSSelectorFromString(key)) else { return nil }
        let v = o.value(forKey: key)
        // iOS 26.4+ answers some of these with NSNull / the string "<null>".
        if v is NSNull { return nil }
        if let s = v as? String, s.isEmpty || s == "<null>" || s == "(null)" { return nil }
        return v
    }

    private static func arbiterState() -> NSObject? {
        guard let cls = NSClassFromString("_UIKeyboardArbiterClient") as? NSObject.Type else { return nil }
        let client = ["automaticSharedArbiterClient", "mainKeyboardArbiterClient", "sharedArbiterClient"]
            .lazy.compactMap { sel -> NSObject? in
                let s = NSSelectorFromString(sel)
                guard cls.responds(to: s) else { return nil }
                return cls.perform(s)?.takeUnretainedValue() as? NSObject
            }.first
        return (read("currentClientState", from: client) ?? read("_currentClientState", from: client)) as? NSObject
    }

    /// Remember the arbiter's (pid → bundle) pair as it is now.
    static func sample() {
        guard let state = withArbiterEnabled({ arbiterState() }) else { return }
        let bundle = (read("sourceBundleIdentifier", from: state) ?? read("_sourceBundleIdentifier", from: state)) as? String
        let pid = (read("processIdentifier", from: state) ?? read("_processIdentifier", from: state)) as? NSNumber
        if let bundle, let pid, !bundle.hasPrefix("com.atype.") { pidToBundle[pid.intValue] = bundle }
    }

    /// Best guess of the host bundle id, with a note of how it was found.
    static func host(of controller: UIInputViewController) -> (String?, String) {
        sample()
        let direct = read("_hostApplicationBundleIdentifier", from: controller) as? String
        let pid = (read("_hostProcessIdentifier", from: controller) as? NSNumber)?.intValue
        let state = withArbiterEnabled { arbiterState() }
        let arbiterBundle = (read("sourceBundleIdentifier", from: state) ?? read("_sourceBundleIdentifier", from: state)) as? String
        let arbiterPid = (read("processIdentifier", from: state) ?? read("_processIdentifier", from: state)) as? NSNumber
        let note = "direct=\(direct ?? "nil") pid=\(pid.map(String.init) ?? "nil") arbiter=\(arbiterBundle ?? "nil")/\(arbiterPid?.stringValue ?? "nil") state=\(state.map { String(describing: type(of: $0)) } ?? "nil") map=\(pidToBundle)"
        if let direct, !direct.isEmpty, !direct.hasPrefix("com.atype.") { return (direct, note) }
        if let pid, let b = pidToBundle[pid] { return (b, note) }
        if let arbiterBundle, !arbiterBundle.hasPrefix("com.atype.") { return (arbiterBundle, note) }
        return (nil, note)
    }
}
