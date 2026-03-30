import Cocoa

// MARK: - Inline Temperature Plot (menu item view)

class TempPlotView: NSView {
    var samples: [Double] = []          // all samples (lid open + closed)
    var sessionRange: Range<Int>?       // indices into samples for lid-closed period
    var sessionMax: Double = 0
    var isRecording: Bool = false
    var totalDuration: TimeInterval = 0 // seconds covered by all samples

    override var intrinsicContentSize: NSSize { NSSize(width: 290, height: 115) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        let padL: CGFloat = 34, padR: CGFloat = 10, padT: CGFloat = 22, padB: CGFloat = 18
        let plotRect = NSRect(x: padL, y: padB,
                              width: bounds.width - padL - padR,
                              height: bounds.height - padT - padB)

        // Title
        let titleStr = isRecording ? "CPU Temp — recording (lid-closed highlighted)" : "CPU Temp — lid-closed period highlighted"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.8, alpha: 1),
            .font: NSFont.boldSystemFont(ofSize: 9.5)
        ]
        titleStr.draw(at: NSPoint(x: padL, y: bounds.height - padT + 4), withAttributes: titleAttrs)

        guard samples.count > 1 else {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.gray, .font: NSFont.systemFont(ofSize: 10)]
            "Waiting for temperature data…".draw(at: NSPoint(x: padL + 4, y: plotRect.midY - 6), withAttributes: attrs)
            return
        }

        let rawMin = samples.min()!, rawMax = samples.max()!
        let span = max(rawMax - rawMin, 8.0)
        let minVal = rawMin - span * 0.08
        let maxVal = rawMax + span * 0.08
        let n = samples.count

        func xForIdx(_ i: Int) -> CGFloat {
            plotRect.minX + plotRect.width * CGFloat(i) / CGFloat(max(n - 1, 1))
        }
        func yForTemp(_ t: Double) -> CGFloat {
            plotRect.minY + plotRect.height * CGFloat((t - minVal) / (maxVal - minVal))
        }

        // Y grid + labels
        for i in 0...3 {
            let frac = CGFloat(i) / 3
            let y = plotRect.minY + plotRect.height * frac
            let temp = minVal + (maxVal - minVal) * Double(frac)
            NSColor(white: 0.22, alpha: 1).setStroke()
            let gp = NSBezierPath(); gp.move(to: NSPoint(x: plotRect.minX, y: y)); gp.line(to: NSPoint(x: plotRect.maxX, y: y))
            gp.lineWidth = 0.5; gp.stroke()
            let la: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.5, alpha: 1), .font: NSFont.systemFont(ofSize: 8)]
            String(format: "%.0f°", temp).draw(at: NSPoint(x: 2, y: y - 5), withAttributes: la)
        }

        // Shaded lid-closed region
        if let sr = sessionRange, sr.lowerBound < n {
            let clampedEnd = min(sr.upperBound, n) - 1
            let clampedStart = sr.lowerBound
            if clampedStart <= clampedEnd {
                let rx = xForIdx(clampedStart)
                let rw = xForIdx(clampedEnd) - rx
                let shadeRect = NSRect(x: rx, y: plotRect.minY, width: max(rw, 1), height: plotRect.height)
                NSColor(red: 1, green: 0.5, blue: 0, alpha: 0.10).setFill()
                shadeRect.fill()
                // Vertical boundary lines
                NSColor(red: 1, green: 0.6, blue: 0, alpha: 0.4).setStroke()
                let vp = NSBezierPath()
                vp.move(to: NSPoint(x: rx, y: plotRect.minY)); vp.line(to: NSPoint(x: rx, y: plotRect.maxY))
                if clampedEnd < n - 1 {
                    let ex = xForIdx(clampedEnd)
                    vp.move(to: NSPoint(x: ex, y: plotRect.minY)); vp.line(to: NSPoint(x: ex, y: plotRect.maxY))
                }
                vp.lineWidth = 0.8; vp.stroke()
            }
        }

        // Full temperature line (lid-open portions, dimmed)
        let fullPath = NSBezierPath()
        for i in 0..<n {
            let pt = NSPoint(x: xForIdx(i), y: yForTemp(samples[i]))
            if i == 0 { fullPath.move(to: pt) } else { fullPath.line(to: pt) }
        }
        NSColor(white: 0.5, alpha: 1).setStroke()
        fullPath.lineWidth = 1.2
        fullPath.lineJoinStyle = .round
        fullPath.stroke()

        // Lid-closed portion of line (highlighted)
        if let sr = sessionRange, sr.lowerBound < n {
            let clampedStart = sr.lowerBound
            let clampedEnd = min(sr.upperBound, n)
            let lidPath = NSBezierPath()
            for i in clampedStart..<clampedEnd {
                let pt = NSPoint(x: xForIdx(i), y: yForTemp(samples[i]))
                if i == clampedStart { lidPath.move(to: pt) } else { lidPath.line(to: pt) }
            }
            let lidColor: NSColor = sessionMax > 90 ? .red : sessionMax > 78 ? .orange : NSColor(red: 1, green: 0.75, blue: 0.2, alpha: 1)
            lidColor.setStroke()
            lidPath.lineWidth = 2.0
            lidPath.lineJoinStyle = .round
            lidPath.stroke()

            // Max label for lid-closed period
            let label = isRecording ? String(format: "lid max: %.1f°C", sessionMax) : String(format: "lid-closed max: %.1f°C", sessionMax)
            let ma: [NSAttributedString.Key: Any] = [.foregroundColor: lidColor, .font: NSFont.boldSystemFont(ofSize: 9)]
            label.draw(at: NSPoint(x: plotRect.maxX - 88, y: plotRect.maxY + 5), withAttributes: ma)
        }

        // X-axis time labels
        let xa: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(white: 0.4, alpha: 1), .font: NSFont.systemFont(ofSize: 8)]
        "now−\(formatDuration(totalDuration))".draw(at: NSPoint(x: plotRect.minX, y: plotRect.minY - 13), withAttributes: xa)
        "now".draw(at: NSPoint(x: plotRect.maxX - 14, y: plotRect.minY - 13), withAttributes: xa)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h\(m % 60 > 0 ? "\(m % 60)m" : "")" : m >= 1 ? "\(m)m" : "\(Int(s))s"
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
    var allSamples: [Double] = []       // rolling buffer — always appended
    var sessionStartIdx: Int?           // index in allSamples where current/last session began
    var sessionMax: Double = 0
    var sessionStart: Date?
    var isInSession: Bool = false
    var appStart: Date = Date()
    var tempTimer: Timer?
    let maxSamples = 480                // 4 hours at 30s intervals

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

        plotView = TempPlotView(frame: NSRect(x: 0, y: 0, width: 290, height: 115))
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

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshPlotView()
    }

    func refreshPlotView() {
        plotView.samples = allSamples
        plotView.sessionMax = sessionMax
        plotView.isRecording = isInSession
        plotView.totalDuration = Date().timeIntervalSince(appStart)
        if let si = sessionStartIdx {
            let end = isInSession ? allSamples.count : min(si + (sessionSamples), allSamples.count)
            plotView.sessionRange = si..<end
        } else {
            plotView.sessionRange = nil
        }
        plotView.needsDisplay = true
    }

    // How many samples are in the session (from sessionStartIdx to end of allSamples)
    var sessionSamples: Int {
        guard let si = sessionStartIdx else { return 0 }
        return max(0, allSamples.count - si)
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
            sessionStartIdx = allSamples.count  // session starts at current tail
            sessionMax = 0
            sessionStart = Date()
            isInSession = true
        } else {
            isInSession = false
            // sessionStartIdx stays so we can still highlight the range in the plot
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
            let label = isInSession ? "  (lid-closed max: %.1f°C)" : "  (last lid-closed max: %.1f°C)"
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

                // Always append — roll the buffer if needed
                if self.allSamples.count >= self.maxSamples {
                    self.allSamples.removeFirst()
                    // Shift session index; if it goes below 0 the session data is scrolled off
                    if let si = self.sessionStartIdx {
                        self.sessionStartIdx = si > 0 ? si - 1 : 0
                    }
                }
                self.allSamples.append(temp)

                // Update session max if lid is closed
                if self.isInSession, temp > self.sessionMax {
                    self.sessionMax = temp
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
