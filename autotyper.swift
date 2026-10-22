// AutoTyper: types pasted text into the focused app like a human.
// Build: ./build.sh   Self-check: ./AutoTyper.app/Contents/MacOS/AutoTyper --selftest
import AppKit
import ApplicationServices

enum Action { case key(Character), backspace, wait(Double) }

// QWERTY neighbours, used to pick a believable wrong key.
let neighbors: [String: String] = [
    "q": "wa", "w": "qeas", "e": "wrsd", "r": "etdf", "t": "ryfg", "y": "tugh", "u": "yihj",
    "i": "uojk", "o": "ipkl", "p": "ol", "a": "qwsz", "s": "awedxz", "d": "serfcx", "f": "drtgvc",
    "g": "ftyhbv", "h": "gyujnb", "j": "huikmn", "k": "jiolm", "l": "kop", "z": "asx", "x": "zsdc",
    "c": "xdfv", "v": "cfgb", "b": "vghn", "n": "bhjm", "m": "njk",
]
// Common English letter pairs roll off the fingers faster.
let fastBigrams: Set<String> = [
    "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es", "or", "te", "of", "ed",
    "is", "it", "al", "ar", "st", "to", "nt", "ng", "se", "ha", "as", "ou", "io", "le", "ve", "co",
    "me", "de", "hi", "ri", "ro", "ic", "ne", "ea", "ra", "ce", "ll", "ss", "ee", "oo",
]

/// Turns text into timed keystrokes, typos and corrections: one group per character,
/// so after any whole group the screen holds an exact prefix of the text (safe pause point).
func plan(_ text: String, wpm: Double, typoRate: Double) -> [[Action]] {
    let chars = Array(text)
    let base = 60.0 / (wpm * 5)  // seconds per character, 1 word = 5 chars
    var out: [[Action]] = []

    func keyDelay(_ c: Character, after p: Character?) -> Double {
        var d = base * .random(in: 0.55...1.35)
        if p?.isLetter == true, c.isLetter { d *= 0.85 }  // mid-word burst
        if let p, fastBigrams.contains(String([p, c]).lowercased()) { d *= 0.65 }
        if c.isUppercase || c.isNumber || "~!@#$%^&*()_+{}|:\"<>?".contains(c) { d *= 1.4 }  // shift / reach
        if Double.random(in: 0..<1) < 0.04 { d *= .random(in: 1.5...3) }  // brief hesitation
        return d
    }
    func pauseAfter(_ c: Character) -> Double {
        switch c {
        case ",", ";", ":": return .random(in: 0.15...0.5)
        case ".", "!", "?": return .random(in: 0.4...1.2)
        case " ":  // gap between word bursts, sometimes a longer "thinking" pause
            return base * .random(in: 0.3...1.5) + (Double.random(in: 0..<1) < 0.03 ? .random(in: 1...3.5) : 0)
        default: return c.isNewline ? .random(in: 0.8...2.5) : 0
        }
    }

    for i in chars.indices {
        let c = chars[i]
        var g: [Action] = [.wait(keyDelay(c, after: i > 0 ? chars[i - 1] : nil))]
        if Double.random(in: 0..<1) < typoRate, let wrong = neighbors[c.lowercased()]?.randomElement() {
            g.append(.key(c.isUppercase ? Character(wrong.uppercased()) : wrong))
            // Often the mistake is noticed only after a letter or two more.
            let late = Int.random(in: 0...2)
            var n = 1
            while n <= late, i + n < chars.count, chars[i + n].isLetter {
                g += [.wait(keyDelay(chars[i + n], after: chars[i + n - 1])), .key(chars[i + n])]
                n += 1
            }
            g.append(.wait(.random(in: 0.25...0.7)))  // "oops"
            for _ in 0..<n { g += [.backspace, .wait(.random(in: 0.06...0.14))] }
        }
        out.append(g + [.key(c), .wait(pauseAfter(c))])
    }
    return out
}

let eventSource = CGEventSource(stateID: .hidSystemState)

func press(_ code: CGKeyCode, unicode: [UniChar] = []) {
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { return }
        e.flags = []
        if !unicode.isEmpty { e.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode) }
        e.post(tap: .cghidEventTap)
    }
}

func send(_ a: Action) {
    switch a {
    case .wait: break
    case .backspace: press(51)
    case .key(let c) where c.isNewline: press(36)
    case .key("\t"): press(48)
    case .key(let c): press(0, unicode: Array(String(c).utf16))  // unicode works with any keyboard layout
    }
}

/// Sleeps in small slices so Esc stops long pauses immediately.
func nap(_ seconds: Double) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if Thread.current.isCancelled { return false }
        Thread.sleep(forTimeInterval: max(0, min(0.05, end.timeIntervalSinceNow)))
    }
    return !Thread.current.isCancelled
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var speed: NSSlider!, typos: NSSlider!
    var speedLabel: NSTextField!, typoLabel: NSTextField!, status: NSTextField!
    var startButton: NSButton!, resetButton: NSButton!
    var worker: Thread?
    var escMonitor: Any?
    var resumeAt = 0  // letters fully typed; Resume continues from here
    var resumeTail: [Action]?  // rest of a letter interrupted mid-typo, done first on Resume
    var accessTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AutoTyper"
        let v = window.contentView!

        func label(_ s: String, _ f: NSRect) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.frame = f
            v.addSubview(l)
            return l
        }
        func slider(_ y: CGFloat, _ min: Double, _ max: Double, _ value: Double) -> NSSlider {
            let s = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(slidersChanged))
            s.frame = NSRect(x: 85, y: y, width: 320, height: 22)
            v.addSubview(s)
            return s
        }

        _ = label("Paste text to type:", NSRect(x: 20, y: 400, width: 480, height: 18))
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 20, y: 170, width: 480, height: 225)
        scroll.borderType = .bezelBorder
        textView = scroll.documentView as? NSTextView
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = self
        v.addSubview(scroll)

        _ = label("Speed", NSRect(x: 20, y: 132, width: 60, height: 18))
        speed = slider(130, 20, 150, 60)
        speedLabel = label("", NSRect(x: 415, y: 132, width: 90, height: 18))
        _ = label("Typos", NSRect(x: 20, y: 97, width: 60, height: 18))
        typos = slider(95, 0, 10, 3)
        typoLabel = label("", NSRect(x: 415, y: 97, width: 90, height: 18))
        slidersChanged()

        let hint = NSTextField(wrappingLabelWithString:
            "Start hides this window and returns focus to the previous app. You have 5 s to click where the text should go. Esc (or clicking AutoTyper in the Dock) pauses; Resume continues where it stopped, so leave the cursor there.")
        hint.frame = NSRect(x: 20, y: 48, width: 480, height: 34)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        v.addSubview(hint)

        status = label("Ready", NSRect(x: 20, y: 18, width: 260, height: 18))
        resetButton = NSButton(title: "Start Over", target: self, action: #selector(resetProgress))
        resetButton.frame = NSRect(x: 290, y: 12, width: 100, height: 30)
        resetButton.isEnabled = false
        v.addSubview(resetButton)
        startButton = NSButton(title: "Start", target: self, action: #selector(startOrPause))
        startButton.frame = NSRect(x: 400, y: 12, width: 100, height: 30)
        startButton.keyEquivalent = "\r"
        startButton.keyEquivalentModifierMask = .command
        v.addSubview(startButton)

        // Text carried over from the restart after access was granted.
        if let t = UserDefaults.standard.string(forKey: "pendingText") {
            UserDefaults.standard.removeObject(forKey: "pendingText")
            textView.string = t
            status.stringValue = "Access granted. Press Start."
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate()
    }

    // Ad-hoc signing ties the Accessibility entry to this exact build, so after a rebuild the
    // old entry can look switched on yet do nothing. Clearing it first makes granting work.
    func askForAccess() {
        let alert = NSAlert()
        alert.messageText = "AutoTyper needs Accessibility access"
        alert.informativeText = "This is what lets it type into other apps. Click Grant Access, then switch AutoTyper on in System Settings. AutoTyper restarts by itself once access is on and keeps your text."
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let id = Bundle.main.bundleIdentifier {
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", id]
            if (try? reset.run()) != nil { reset.waitUntilExit() }
        }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)  // adds a fresh entry
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        status.stringValue = "Waiting for access…"
        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            self?.relaunch()
        }
    }

    // A fresh process is the reliable way to have newly granted access apply to keystrokes.
    func relaunch() {
        UserDefaults.standard.set(textView.string, forKey: "pendingText")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(), editItem = NSMenuItem()
        main.addItem(appItem)
        main.addItem(editItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit AutoTyper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // Without an Edit menu, Cmd+V does nothing in a code-built AppKit app.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    @objc func slidersChanged() {
        speedLabel.stringValue = "\(Int(speed.doubleValue)) WPM"
        typoLabel.stringValue = String(format: "%.1f%%", typos.doubleValue)
    }

    @objc func resetProgress() {
        guard worker?.isFinished != false else { return }
        resumeAt = 0
        resumeTail = nil
        startButton.title = "Start"
        resetButton.isEnabled = false
        status.stringValue = "Ready"
        NSApp.dockTile.badgeLabel = nil
    }

    // Edited text no longer matches what was typed, so a resume would be wrong.
    func textDidChange(_ n: Notification) { resetProgress() }

    @objc func startOrPause() {
        if let w = worker, !w.isFinished { w.cancel(); return }
        // Posting keystrokes to other apps needs Accessibility permission.
        guard AXIsProcessTrusted() else { return askForAccess() }
        let text = textView.string
        guard !text.isEmpty else { status.stringValue = "Paste some text first"; return }

        if escMonitor == nil {
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53 { self?.worker?.cancel() }
            }
        }
        // Re-planned on every start so slider changes made while paused apply to the rest.
        let groups = plan(text, wpm: speed.doubleValue, typoRate: typos.doubleValue / 100)
        let (from, tail) = (resumeAt, resumeTail)
        startButton.title = "Pause"
        resetButton.isEnabled = false
        textView.isEditable = false  // a stray keystroke here would change the text mid-run
        NSApp.hide(nil)
        let t = Thread { [weak self] in self?.run(groups, from: from, tail: tail) }
        worker = t
        t.start()
    }

    func run(_ groups: [[Action]], from start: Int, tail: [Action]?) {
        for s in (1...5).reversed() {
            show("Starting in \(s)…", badge: "\(s)")
            if !nap(1) { return finish(at: start, tail: tail, of: groups.count) }
        }
        for i in start..<groups.count {
            let partial = i == start && tail != nil
            let g = partial ? tail! : groups[i]
            for (k, a) in g.enumerated() {
                if case .wait(let s) = a {
                    // Pause right here; if a typo is on screen, Resume fixes it first.
                    if !nap(s) { return finish(at: i, tail: k == 0 && !partial ? nil : Array(g[k...]), of: groups.count) }
                    continue
                }
                send(a)
            }
            if i % 10 == 0 { show("Typing… \(i * 100 / groups.count)%", badge: "\(i * 100 / groups.count)%") }
        }
        finish(at: groups.count, tail: nil, of: groups.count)
    }

    func finish(at n: Int, tail: [Action]?, of total: Int) {
        let resumable = n < total && (n > 0 || tail != nil)
        show(n >= total ? "Done" : resumable ? "Paused at \(n * 100 / total)%" : "Stopped", badge: resumable ? "⏸" : nil)
        DispatchQueue.main.async {
            self.resumeAt = resumable ? n : 0
            self.resumeTail = resumable ? tail : nil
            self.startButton.title = resumable ? "Resume" : "Start"
            self.resetButton.isEnabled = resumable
            self.textView.isEditable = true
        }
    }

    func show(_ text: String, badge: String?) {
        DispatchQueue.main.async {
            self.status.stringValue = text
            NSApp.dockTile.badgeLabel = badge
        }
    }

    // Coming back to AutoTyper mid-run would type into its own window, so pause.
    func applicationDidBecomeActive(_ n: Notification) { worker?.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

/// Replays plans with heavy typos into a buffer: after every letter group (a pause point)
/// the buffer must hold the exact prefix, so pause + resume never loses or duplicates text.
func selfTest() {
    let sample = "Hello, World! The quick brown fox jumps over the lazy dog.\r\nSecond line\twith tab? Yes: 42 items; done."
    let chars = Array(sample)
    for _ in 0..<500 {
        var buf: [Character] = []
        for (i, g) in plan(sample, wpm: 60, typoRate: 0.5).enumerated() {
            for a in g {
                switch a {
                case .key(let c): buf.append(c)
                case .backspace: precondition(!buf.isEmpty, "backspace on empty buffer"); buf.removeLast()
                case .wait(let s): precondition(s >= 0, "negative wait")
                }
            }
            precondition(buf == Array(chars[...i]), "pause point \(i) holds \(String(buf))")
        }
    }
    // Pause at a random keystroke (maybe mid-typo), resume with a fresh plan: same as run().
    for _ in 0..<500 {
        var buf: [Character] = []
        func apply<S: Sequence>(_ s: S) where S.Element == Action {
            for a in s {
                if case .key(let c) = a { buf.append(c) } else if case .backspace = a { buf.removeLast() }
            }
        }
        let first = plan(sample, wpm: 60, typoRate: 0.5)
        let i = Int.random(in: 0..<first.count), k = Int.random(in: 0..<first[i].count)
        apply(first[..<i].joined())
        apply(first[i][..<k])
        apply(first[i][k...])  // resumeTail
        apply(plan(sample, wpm: 90, typoRate: 0.5)[(i + 1)...].joined())
        precondition(buf == chars, "resume from \(i)/\(k) gave \(String(buf))")
    }
    let secs = plan(sample, wpm: 60, typoRate: 0.03).joined().reduce(0.0) { if case .wait(let s) = $1 { return $0 + s }; return $0 }
    print("selftest ok; slider 60 WPM gives ~\(Int(Double(sample.count) / 5 / (secs / 60))) WPM real pace incl. pauses")
}

if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) }
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(.regular)
NSApp.run()
