// lidawake's menu bar icon. It reads the status file bin/lidawake writes on every tick, and
// its switch runs `lidawake on|off`, so the background check keeps working with or without it.
// launchd: io.github.oli3dwards.lidawake-menubar.
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let statusPath = home + "/Library/Application Support/lidawake/status"
let logPath = home + "/Library/Application Support/lidawake/lidawake.log"
let cli = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("bin/lidawake").path

func readStatus() -> [String: String] {
    guard let text = try? String(contentsOfFile: statusPath, encoding: .utf8) else { return [:] }
    var out: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 { out[parts[0]] = parts[1] }
    }
    return out
}

final class Controller: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let headline = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let detail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let toggle = NSMenuItem(title: "Keep running with lid closed", action: #selector(flip), keyEquivalent: "")

    override init() {
        super.init()
        headline.isEnabled = false
        detail.isEnabled = false
        toggle.target = self
        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        let quit = NSMenuItem(title: "Hide icon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for i in [headline, detail, .separator(), toggle, log, .separator(), quit] { menu.addItem(i) }
        menu.delegate = self
        item.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    func refresh() {
        let s = readStatus()
        let updated = Double(s["updated"] ?? "") ?? 0
        let stale = Date().timeIntervalSince1970 - updated > 90
        let (symbol, title): (String, String)
        if s.isEmpty || stale {
            (symbol, title) = ("exclamationmark.triangle", "Background check isn't running")
        } else if s["error"] == "no-permission" {
            (symbol, title) = ("exclamationmark.triangle", "Needs one-time permission (run install.sh)")
        } else {
            switch s["reason"] ?? "" {
            case "on": (symbol, title) = ("laptopcomputer", "On: keeps running with the lid closed")
            case "off": (symbol, title) = ("moon.zzz", "Off: closing the lid sleeps the Mac")
            case "battery": (symbol, title) = ("battery.25", "Paused: battery low, lid closes to sleep")
            case "heat": (symbol, title) = ("thermometer.sun", "Paused: running hot, lid closes to sleep")
            default: (symbol, title) = ("questionmark", "Unknown state")
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.button?.image = image
        item.button?.title = image == nil ? "LA" : ""
        item.button?.toolTip = "lidawake: " + title
        headline.title = title
        let battery = s["battery"].map { $0.isEmpty ? "?" : $0 + "%" } ?? "?"
        let power = s["power"] == "ac" ? "on mains" : "on battery"
        detail.title = "Battery \(battery) \(power) · heat \(s["thermal"] ?? "?")"
        toggle.state = s["mode"] == "off" ? .off : .on
    }

    @objc func flip() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [cli, toggle.state == .on ? "off" : "on"]
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        refresh()
    }

    @objc func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: logPath)) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
