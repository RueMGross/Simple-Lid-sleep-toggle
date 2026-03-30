import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Sleep", action: #selector(toggleSleep), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        ensureSudoersRule()
        updateStatus()
    }

    func ensureSudoersRule() {
        // Check if passwordless sudo already works
        let check = shell("sudo -n /usr/bin/pmset -a disablesleep 1 2>&1; sudo -n /usr/bin/pmset -a disablesleep 0 2>&1")
        if !check.lowercased().contains("password") && !check.lowercased().contains("terminal") {
            return
        }
        let rule = "rgross ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *"
        // Use AppleScript once to append the rule to sudoers (only if not already present)
        let script = """
        do shell script "grep -q 'pmset.*disablesleep' /etc/sudoers || echo '\(rule)' >> /etc/sudoers" with administrator privileges
        """
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
    }

    func isSleepDisabled() -> Bool {
        let result = shell("pmset -g | grep 'SleepDisabled'")
        return result.contains("SleepDisabled\t\t1") || result.contains("SleepDisabled 1")
    }

    func updateStatus() {
        let disabled = isSleepDisabled()
        if let button = statusItem.button {
            if disabled {
                button.title = "☕"
                button.toolTip = "Lid sleep is DISABLED — click to enable"
            } else {
                button.title = "🙂"
                button.toolTip = "Lid sleep is ENABLED — click to disable"
            }
        }
        // Update menu item label
        if let toggleItem = menu.item(at: 0) {
            toggleItem.title = isSleepDisabled() ? "Enable lid sleep" : "Disable lid sleep"
        }
    }

    @objc func toggleSleep() {
        let disabled = isSleepDisabled()
        let newValue = disabled ? "0" : "1"
        let result = shell("sudo /usr/bin/pmset -a disablesleep \(newValue)")
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showAlert("Failed to toggle sleep: \(result)")
        }
        updateStatus()
    }

    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SleepToggle"
        alert.informativeText = message
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
