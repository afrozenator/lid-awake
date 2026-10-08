import AppKit

enum PowerError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

enum Power {
    // An absent SleepDisabled key is macOS's default (normal sleep).
    // Reject unexpected output instead of showing a misleading OFF state.
    static func parse(_ output: String) throws -> Bool {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled" {
                guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else {
                    throw PowerError.message("macOS returned an unrecognized sleep setting.")
                }
                return fields[1] == "1"
            }
        }
        guard output.contains("System-wide power settings:"),
              output.contains("Currently in use:"),
              lines.contains(where: { $0.split(whereSeparator: { $0.isWhitespace }).first == "sleep" }) else {
            throw PowerError.message("Could not read macOS power settings.")
        }
        return false
    }

    static func read() throws -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PowerError.message("pmset could not read the current power settings.")
        }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    // Only these two fixed commands can be executed with administrator rights.
    static func command(_ enabled: Bool) -> String {
        "/usr/bin/pmset -a disablesleep \(enabled ? 1 : 0)"
    }

    @discardableResult
    static func set(_ enabled: Bool) throws -> Bool {
        if try read() == enabled { return true }
        let source = "do shell script \"\(command(enabled))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw PowerError.message("Could not prepare the macOS authorization request.")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -128 { return false }
            throw PowerError.message(error[NSAppleScript.errorMessage] as? String ?? "macOS could not change the sleep setting.")
        }
        guard try read() == enabled else {
            throw PowerError.message("macOS did not apply the requested setting. The current state is shown in the app.")
        }
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var timer: Timer?
    private var busy = false
    private let stateLabel = NSTextField(labelWithString: "Reading status…")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let enableButton = NSButton(title: "Enable", target: nil, action: nil)
    private let disableButton = NSButton(title: "Disable", target: nil, action: nil)
    private let stateItem = NSMenuItem(title: "Reading status…", action: nil, keyEquivalent: "")
    private let enableItem = NSMenuItem(title: "Enable — keep Mac awake", action: #selector(enable), keyEquivalent: "")
    private let disableItem = NSMenuItem(title: "Disable — allow normal sleep", action: #selector(disable), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit Lid Awake", action: #selector(quit), keyEquivalent: "q")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        for item in [enableItem, disableItem] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        let showItem = NSMenuItem(title: "Show Controls…", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        refresh()
        timer = Timer(timeInterval: 5, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        showWindow()
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 335),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Lid Awake"
        window.isReleasedWhenClosed = false
        window.center()

        let title = NSTextField(labelWithString: "Keep running. Lid closed.")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        stateLabel.font = .systemFont(ofSize: 17, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 386

        enableButton.target = self; enableButton.action = #selector(enable)
        disableButton.target = self; disableButton.action = #selector(disable)
        for button in [enableButton, disableButton] {
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }
        let buttons = NSStackView(views: [enableButton, disableButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let note = NSTextField(wrappingLabelWithString:
            "Works on battery or power. Stays enabled until you disable it, including after a restart. No automatic battery cutoff.\n\nKeep your Mac on a ventilated surface, and disable before putting it in a bag.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 386

        let stack = NSStackView(views: [title, stateLabel, detailLabel, buttons, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func refresh() {
        guard !busy else { return }
        do {
            let enabled = try Power.read()
            stateLabel.stringValue = enabled ? "Enabled · Mac stays awake" : "Disabled · Normal sleep allowed"
            stateLabel.textColor = enabled ? .systemOrange : .labelColor
            detailLabel.stringValue = enabled
                ? "Closing the lid should keep your running tasks active. Disable restores normal sleep behavior."
                : "Enable to keep local tasks running with the lid closed. macOS will ask for administrator authorization."
            stateItem.title = enabled ? "Lid Awake is enabled" : "Lid Awake is disabled"
            statusItem.button?.title = enabled ? " Awake ON" : " Awake OFF"
            statusItem.button?.image = NSImage(systemSymbolName: enabled ? "sun.max.fill" : "moon", accessibilityDescription: stateItem.title)
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.toolTip = stateLabel.stringValue
            enableButton.isEnabled = !enabled; enableItem.isEnabled = !enabled
            disableButton.isEnabled = enabled; disableItem.isEnabled = enabled
            quitItem.title = enabled ? "Disable & Quit…" : "Quit Lid Awake"
        } catch {
            stateLabel.stringValue = "Status unavailable"
            stateLabel.textColor = .systemRed
            detailLabel.stringValue = error.localizedDescription
            stateItem.title = "Sleep status unavailable"
            statusItem.button?.title = " Awake ?"
            statusItem.button?.toolTip = error.localizedDescription
            enableButton.isEnabled = false; enableItem.isEnabled = false
            disableButton.isEnabled = false; disableItem.isEnabled = false
        }
    }

    @objc private func enable() { change(to: true) }
    @objc private func disable() { change(to: false) }

    private func change(to enabled: Bool) {
        guard !busy else { return }
        busy = true
        defer { busy = false; refresh() }
        NSApp.activate(ignoringOtherApps: true)
        do { try Power.set(enabled) }
        catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not change sleep behavior"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func showWindow() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !busy else { return .terminateCancel }
        // A normal Quit restores sleep. Force Quit/crashes cannot run this cleanup.
        do {
            guard try Power.set(false) else { return .terminateCancel }
            return .terminateNow
        } catch {
            showError(error)
            return .terminateCancel
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
}

func selfTest() throws {
    func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw PowerError.message("Test failed: \(name)") }
    }
    let baseline = "System-wide power settings:\nCurrently in use:\n sleep 1 (sleep prevented by Claude)\n"
    try check(try !Power.parse(baseline), "absent flag means normal sleep")
    try check(try Power.parse("System-wide power settings:\n SleepDisabled 1\nCurrently in use:\n sleep 1\n"), "enabled")
    try check(try !Power.parse("System-wide power settings:\n SleepDisabled 0\nCurrently in use:\n sleep 1\n"), "disabled")
    for invalid in ["", "error", "SleepDisabled 2", "SleepDisabled", "SleepDisabled 1 junk"] {
        var rejected = false
        do { _ = try Power.parse(invalid) } catch { rejected = true }
        try check(rejected, "reject malformed status: \(invalid)")
    }
    try check(Power.command(true) == "/usr/bin/pmset -a disablesleep 1", "enable command")
    try check(Power.command(false) == "/usr/bin/pmset -a disablesleep 0", "disable command")
    print("10 checks passed. No power settings changed.")
}

if CommandLine.arguments.count > 1 {
    do {
        switch CommandLine.arguments[1] {
        case "--status": print(try Power.read() ? "ENABLED — system sleep disabled" : "DISABLED — normal sleep allowed")
        case "--enable", "--disable":
            guard try Power.set(CommandLine.arguments[1] == "--enable") else { exit(2) }
            print(try Power.read() ? "ENABLED — system sleep disabled" : "DISABLED — normal sleep allowed")
        case "--self-test": try selfTest()
        default: throw PowerError.message("Usage: LidAwake [--status | --enable | --disable | --self-test]")
        }
        exit(0)
    } catch {
        fputs("Lid Awake: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
