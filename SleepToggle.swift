import Cocoa

// MARK: - Inline Temperature Plot (menu item view)

class TempPlotView: NSView {
    var samples: [Double] = []
    var sessionMax: Double = 0
    var isRecording: Bool = false
    var sessionDuration: TimeInterval = 0

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 110) }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let padL: CGFloat = 34, padR: CGFloat = 10, padT: CGFloat = 22, padB: CGFloat = 18
        let plotRect = NSRect(x: padL, y: padB,
                              width: bounds.width - padL - padR,
                              height: bounds.height - padT - padB)

        // Title
        let titleStr = isRecording ? "CPU Temp — recording…" : "CPU Temp — last lid-closed session"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.85, alpha: 1),
            .font: NSFont.boldSystemFont(ofSize: 9.5)
        ]
        titleStr.draw(at: NSPoint(x: padL, y: bounds.height - padT + 4), withAttributes: titleAttrs)

        guard samples.count > 1 else {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.gray,
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let msg = isRecording ? "Waiting for first sample…" : "Disable lid sleep to start recording"
            msg.draw(at: NSPoint(x: padL + 4, y: plotRect.midY - 6), withAttributes: attrs)
            return
        }

        let rawMin = samples.min()!, rawMax = samples.max()!
        let span = max(rawMax - rawMin, 8.0)
        let minVal = rawMin - span * 0.08
        let maxVal = rawMax + span * 0.08

        // Y grid + labels
        for i in 0...3 {
            let frac = CGFloat(i) / 3
            let y = plotRect.minY + plotRect.height * frac
            let temp = minVal + (maxVal - minVal) * Double(frac)
            NSColor(white: 0.25, alpha: 1).setStroke()
            let gp = NSBezierPath()
            gp.move(to: NSPoint(x: plotRect.minX, y: y))
            gp.line(to: NSPoint(x: plotRect.maxX, y: y))
            gp.lineWidth = 0.5
            gp.stroke()
            let lbl = String(format: "%.0f°", temp)
            let la: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.5, alpha: 1), .font: NSFont.systemFont(ofSize: 8)]
            lbl.draw(at: NSPoint(x: 2, y: y - 5), withAttributes: la)
        }

        // Temperature line
        let path = NSBezierPath()
        for (i, t) in samples.enumerated() {
            let x = plotRect.minX + plotRect.width * CGFloat(i) / CGFloat(max(samples.count - 1, 1))
            let y = plotRect.minY + plotRect.height * CGFloat((t - minVal) / (maxVal - minVal))
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        let lineColor: NSColor = sessionMax > 90 ? .red : sessionMax > 78 ? .orange : .systemGreen
        lineColor.setStroke()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.stroke()

        // Max label (top-right)
        let maxStr = String(format: "max %.1f°C", sessionMax)
        let ma: [NSAttributedString.Key: Any] = [.foregroundColor: lineColor, .font: NSFont.boldSystemFont(ofSize: 9)]
        maxStr.draw(at: NSPoint(x: plotRect.maxX - 58, y: plotRect.maxY + 5), withAttributes: ma)

        // X-axis time labels
        let xa: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.45, alpha: 1), .font: NSFont.systemFont(ofSize: 8)]
        "start".draw(at: NSPoint(x: plotRect.minX, y: plotRect.minY - 13), withAttributes: xa)
        let mins = Int(sessionDuration / 60)
        let durStr = mins >= 1 ? "\(mins)m" : "\(Int(sessionDuration))s"
        durStr.draw(at: NSPoint(x: plotRect.maxX - 14, y: plotRect.minY - 13), withAttributes: xa)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var toggleItem: NSMenuItem!
    var tempMenuItem: NSMenuItem!
    var plotView: TempPlotView!

    var currentTemp: Double = 0
    var sessionSamples: [Double] = []
    var sessionMax: Double = 0
    var sessionStart: Date?
    var isInSession: Bool = false
    var tempTimer: Timer?

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self

        toggleItem = NSMenuItem(title: "Disable lid sleep", action: #selector(toggleSleep), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        tempMenuItem = NSMenuItem(title: "CPU: —", action: nil, keyEquivalent: "")
        menu.addItem(tempMenuItem)

        // Inline plot item
        plotView = TempPlotView(frame: NSRect(x: 0, y: 0, width: 280, height: 110))
        let plotItem = NSMenuItem()
        plotItem.view = plotView
        menu.addItem(plotItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
        ensureSudoersRule()
        updateStatus()
        startTempSampling()
    }

    // MARK: NSMenuDelegate — refresh plot when menu opens

    func menuWillOpen(_ menu: NSMenu) {
        let dur = sessionStart.map { Date().timeIntervalSince($0) } ?? TimeInterval(sessionSamples.count * 30)
        plotView.samples = sessionSamples
        plotView.sessionMax = sessionMax
        plotView.isRecording = isInSession
        plotView.sessionDuration = dur
        plotView.needsDisplay = true
    }

    // MARK: Sudoers

    func ensureSudoersRule() {
        let pmsetOK = !shell("sudo -n /usr/bin/pmset -g 2>&1").lowercased().contains("password")
        let powerOK = !shell("sudo -n /usr/bin/powermetrics --help 2>&1").lowercased().contains("password")
        if pmsetOK && powerOK { return }

        let user = NSUserName()
        var lines = ""
        if !pmsetOK { lines += "\n\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *" }
        if !powerOK { lines += "\n\(user) ALL=(ALL) NOPASSWD: /usr/bin/powermetrics *" }

        let escaped = lines.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"printf '\(escaped)' >> /etc/sudoers\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    // MARK: Sleep toggle

    func isSleepDisabled() -> Bool {
        let r = shell("pmset -g | grep 'SleepDisabled'")
        return r.contains("SleepDisabled\t\t1") || r.contains("SleepDisabled 1")
    }

    @objc func toggleSleep() {
        let wasDisabled = isSleepDisabled()
        let result = shell("sudo /usr/bin/pmset -a disablesleep \(wasDisabled ? "0" : "1")")
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showAlert("pmset error: \(result)")
        }
        if !wasDisabled {
            sessionSamples = []
            sessionMax = 0
            sessionStart = Date()
            isInSession = true
        } else {
            isInSession = false
        }
        updateStatus()
    }

    func updateStatus() {
        let disabled = isSleepDisabled()
        isInSession = disabled
        if let btn = statusItem.button {
            btn.title = disabled ? "☕" : "🙂"
            if disabled {
                btn.toolTip = "Lid sleep DISABLED — recording CPU temps"
            } else if sessionMax > 0 {
                btn.toolTip = String(format: "Lid sleep enabled — last session max: %.1f°C", sessionMax)
            } else {
                btn.toolTip = "Lid sleep ENABLED — click to disable"
            }
        }
        toggleItem.title = disabled ? "Enable lid sleep" : "Disable lid sleep"
        refreshTempMenuItem()
    }

    func refreshTempMenuItem() {
        var text = currentTemp > 0 ? String(format: "CPU: %.1f°C", currentTemp) : "CPU: —"
        if sessionMax > 0 {
            let label = isInSession ? "  (session max: %.1f°C)" : "  (last session max: %.1f°C)"
            text += String(format: label, sessionMax)
        }
        tempMenuItem.title = text
    }

    // MARK: Temperature sampling

    func startTempSampling() {
        sampleTemp()
        tempTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sampleTemp()
        }
    }

    func sampleTemp() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let raw = self.shell("sudo /usr/bin/powermetrics -n 1 -i 500 --samplers smc 2>/dev/null")
            let temp = self.parseCPUTemp(raw)
            DispatchQueue.main.async {
                guard temp > 0 else { return }
                self.currentTemp = temp
                if self.isInSession {
                    self.sessionSamples.append(temp)
                    if temp > self.sessionMax { self.sessionMax = temp }
                    if self.sessionSamples.count > 480 { self.sessionSamples.removeFirst() }
                    if let btn = self.statusItem.button {
                        btn.toolTip = String(format: "Lid sleep DISABLED — now: %.1f°C  max: %.1f°C", temp, self.sessionMax)
                    }
                }
                self.refreshTempMenuItem()
            }
        }
    }

    func parseCPUTemp(_ output: String) -> Double {
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            guard lower.contains("cpu") && lower.contains("temperature") else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let valStr = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: " ").first ?? ""
            if let v = Double(valStr), v > 0 { return v }
        }
        return 0
    }

    // MARK: Helpers

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
        let a = NSAlert()
        a.messageText = "SleepToggle"
        a.informativeText = message
        a.runModal()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
