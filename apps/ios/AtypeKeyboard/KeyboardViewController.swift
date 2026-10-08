// The Atype keyboard: a remote control for the Atype app, which records
// (Apple does not let keyboards use the microphone). Layout follows the
// common voice-keyboard pattern: a big mic in the middle, delete and @ on
// the right, AI, space and return below, the globe key bottom-left.

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel!

    override func viewDidLoad() {
        super.viewDidLoad()
        HostIdentity.enableArbiter()
        model = KeyboardModel(controller: self)
        let host = UIHostingController(rootView: KeyboardView(model: model, globe: GlobeKey(controller: self)))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 292),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.visible = true
        _ = hostBundleID()
        model.refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.visible = false
        DebugLog.log("kb", "disappear")
    }

    /// The host app's bundle id when iOS still exposes it (see HostIdentity).
    func hostBundleID() -> String? {
        let (id, note) = HostIdentity.host(of: self)
        DebugLog.log("kb", "host \(id ?? "nil"): \(note)")
        return id
    }

    /// One-off diagnostics: which host-related selectors exist (logged once).
    private static var introspected = false
    func logHostSelectors() {
        guard !Self.introspected else { return }
        Self.introspected = true
        let objects: [NSObject?] = [self, parent, parent?.parent, extensionContext]
        for obj in objects.compactMap({ $0 }) {
            var names: [String] = []
            var cls: AnyClass? = type(of: obj)
            while let c = cls, names.count < 60 {
                var count: UInt32 = 0
                if let list = class_copyMethodList(c, &count) {
                    for i in 0..<Int(count) {
                        let n = NSStringFromSelector(method_getName(list[i]))
                        if n.localizedCaseInsensitiveContains("host") || n.localizedCaseInsensitiveContains("bundle") || n.localizedCaseInsensitiveContains("pid") {
                            names.append(n)
                        }
                    }
                    free(list)
                }
                cls = class_getSuperclass(c)
                if c == UIViewController.self { break }
            }
            // Names only: reading values can crash (e.g. _hostAuditToken).
            DebugLog.log("kb", "\(type(of: obj)): \(names.joined(separator: " ").prefix(900))")
        }
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        model.refresh()
    }

    /// Open the Atype app. Keyboards cannot call UIApplication.open directly,
    /// so find the application object in the responder chain.
    func openApp(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if NSStringFromClass(type(of: r)).hasSuffix("Application"), r.responds(to: selector) {
                typealias Open = @convention(c) (AnyObject, Selector, URL, NSDictionary, ((Bool) -> Void)?) -> Void
                let imp = r.method(for: selector)
                unsafeBitCast(imp, to: Open.self)(r, selector, url, NSDictionary(), nil)
                return
            }
            responder = r.next
        }
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published var phase: Bridge.Phase = .idle
    @Published var commandMode = false
    @Published var partial = ""
    @Published var message = ""
    @Published var warm = false
    @Published var hasFullAccess = true
    @Published var needsGlobe = false
    /// Microphone level 0…1 while recording (drives the dots).
    @Published var level: Double = 0
    /// Dictations inserted by this keyboard, newest last (for undo), and
    /// undone ones (for redo).
    @Published var undoStack: [String] = []
    @Published var redoStack: [String] = []
    /// Only the keyboard on screen inserts results (an old instance may still
    /// be alive after switching apps).
    var visible = false

    private weak var controller: KeyboardViewController?
    private var proxy: (any UITextDocumentProxy)? { controller?.textDocumentProxy }

    init(controller: KeyboardViewController) {
        self.controller = controller
        Bridge.observe(.changed) { [weak self] in Task { @MainActor in self?.refresh() } }
        Bridge.observe(.level) { [weak self] in Task { @MainActor in self?.level = Bridge.level } }
        // The "warm" icon follows the app's heartbeat. The same tick catches a
        // result whose "changed" notification was missed (the keyboard can be
        // suspended during a long take), so text is never left behind.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.warm = Bridge.appIsWarm
                if self.visible, Bridge.hasPendingResult || Bridge.phase != self.phase {
                    if Bridge.hasPendingResult { DebugLog.log("kb", "poll: pending result") }
                    self.refresh()
                }
            }
        }
        refresh()
    }

    func refresh() {
        hasFullAccess = controller?.hasFullAccess ?? false
        needsGlobe = controller?.needsInputModeSwitchKey ?? false
        phase = Bridge.phase
        commandMode = Bridge.commandMode
        partial = Bridge.partial
        message = Bridge.message
        warm = Bridge.appIsWarm
        // A result the app published while we were away (or just now).
        if visible, let proxy, let text = Bridge.takeResult() {
            let before = proxy.documentContextBeforeInput ?? ""
            proxy.insertText(text)
            let after = proxy.documentContextBeforeInput ?? ""
            DebugLog.log("kb", "insert check: before=\(before.suffix(12)) after=\(after.suffix(20))")
            undoStack.append(text)
            redoStack.removeAll()
            DebugLog.log("kb", "inserted \(text.count) chars")
            message = ""
        }
    }

    func mic(command: Bool) {
        guard hasFullAccess else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch phase {
        case .recording:
            Bridge.post(.stop)
        case .idle:
            Bridge.discardResult()
            Bridge.hostBundleID = controller?.hostBundleID()
            DebugLog.log("kb", "mic command=\(command) warm=\(Bridge.appIsWarm) host=\(Bridge.hostBundleID ?? "nil")")
            if Bridge.appIsWarm {
                Bridge.post(command ? .startCommand : .start)
            } else {
                controller?.openApp(URL(string: "atype://start?mode=\(command ? "command" : "dictation")")!)
            }
        default:
            break
        }
    }

    func cancel() { Bridge.post(.cancel) }

    /// Remove the last dictation from before the cursor (when it is still
    /// there as inserted), keeping it for redo.
    func undo() {
        guard let proxy, let text = undoStack.last else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        // The context can be truncated for long text; only check what we see.
        let visible = String(text.suffix(before.count))
        guard before.hasSuffix(visible) else {
            undoStack.removeAll()
            return
        }
        for _ in 0..<text.count { proxy.deleteBackward() }
        undoStack.removeLast()
        redoStack.append(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func redo() {
        guard let proxy, let text = redoStack.popLast() else { return }
        proxy.insertText(text)
        undoStack.append(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func insert(_ s: String) {
        UIDevice.current.playInputClick()
        proxy?.insertText(s)
    }
    func backspace() {
        UIDevice.current.playInputClick()
        proxy?.deleteBackward()
    }
}

/// The system globe key (switch keyboards / long-press for the list).
struct GlobeKey: UIViewRepresentable {
    let controller: UIInputViewController

    func makeUIView(context: Context) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22)), for: .normal)
        b.tintColor = .label
        b.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return b
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
