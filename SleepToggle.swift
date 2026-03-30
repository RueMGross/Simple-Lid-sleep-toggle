import Cocoa
import IOKit

// MARK: - M1 temperature via IOHIDEventSystem (no sudo required)

private typealias IOHIDEventSystemClientRef = OpaquePointer
private typealias IOHIDServiceClientRef = OpaquePointer
private typealias IOHIDEventRef = OpaquePointer

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
@discardableResult
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> IOHIDEventRef?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private let kHIDEventTypeTemp: Int64 = 15
private let kHIDFieldTempLevel: Int32 = Int32(truncatingIfNeeded: kHIDEventTypeTemp << 16)

private func readCPUTempFromHID() -> Double {
    guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return 0 }
    IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
    guard let services = IOHIDEventSystemClientCopyServices(client) else { return 0 }
    var temps: [Double] = []
    for i in 0..<CFArrayGetCount(services) {
        let svc = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: IOHIDServiceClientRef.self)
        guard let event = IOHIDServiceClientCopyEvent(svc, kHIDEventTypeTemp, 0, 0) else { continue }
        let temp = IOHIDEventGetFloatValue(event, kHIDFieldTempLevel)
        guard temp > 0 && temp < 200 else { continue }
        var name = ""
        if let r = IOHIDServiceClientCopyProperty(svc, "Product" as CFString) {
            name = (r.takeRetainedValue() as? String) ?? ""
        }
        // pACC = performance CPU cores, eACC = efficiency CPU cores
        if name.hasPrefix("pACC MTR") || name.hasPrefix("eACC MTR") { temps.append(temp) }
    }
    guard !temps.isEmpty else { return 0 }
    return temps.reduce(0, +) / Double(temps.count)
}

// MARK: - Inline Temperature Plot (menu item view)

class TempPlotView: NSView {
    var samples: [Double] = []          // all samples (lid open + closed)
    var sessionRange: Range<Int>?       // indices into samples for lid-closed period
    var sessionMax: Double = 0
    var isRecording: Bool = false
    var totalDuration: TimeInterval = 0 // seconds covered by all samples

    override var intrinsicContentSize: NSSize { NSSize(width: 290, height: 115) }

    override func draw(_ dirtyRect: NSRect) {
        // Use system menu background — no custom fill
        NSColor.clear.setFill()
        bounds.fill()

        let padL: CGFloat = 34, padR: CGFloat = 14, padT: CGFloat = 20, padB: CGFloat = 18
        let plotRect = NSRect(x: padL, y: padB,
                              width: bounds.width - padL - padR,
                              height: bounds.height - padT - padB)

        // Title (top-left, above plot)
        let titleStr = isRecording ? "CPU Temp — recording" : "CPU Temp — last lid-closed session"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.boldSystemFont(ofSize: 9.5)
        ]
        titleStr.draw(at: NSPoint(x: padL, y: bounds.height - padT + 3), withAttributes: titleAttrs)

        guard samples.count > 1 else {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 10)]
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

        // Plot area subtle background
        NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: plotRect, xRadius: 3, yRadius: 3).fill()

        // Y grid + labels
        for i in 0...3 {
            let frac = CGFloat(i) / 3
            let y = plotRect.minY + plotRect.height * frac
            let temp = minVal + (maxVal - minVal) * Double(frac)
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let gp = NSBezierPath(); gp.move(to: NSPoint(x: plotRect.minX, y: y)); gp.line(to: NSPoint(x: plotRect.maxX, y: y))
            gp.lineWidth = 0.5; gp.stroke()
            let la: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 8)]
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

        // Full temperature line (lid-open, secondary color)
        let fullPath = NSBezierPath()
        for i in 0..<n {
            let pt = NSPoint(x: xForIdx(i), y: yForTemp(samples[i]))
            if i == 0 { fullPath.move(to: pt) } else { fullPath.line(to: pt) }
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
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
            let lidColor: NSColor = sessionMax > 90 ? .systemRed : sessionMax > 78 ? .systemOrange : .systemOrange
            lidColor.setStroke()
            lidPath.lineWidth = 2.0
            lidPath.lineJoinStyle = .round
            lidPath.stroke()

            // Max label — top-right corner of title row (right-aligned, same row as title)
            let label = String(format: "max %.1f°C", sessionMax)
            let ma: [NSAttributedString.Key: Any] = [.foregroundColor: lidColor, .font: NSFont.boldSystemFont(ofSize: 9.5)]
            let labelSize = (label as NSString).size(withAttributes: ma)
            label.draw(at: NSPoint(x: bounds.width - padR - labelSize.width, y: bounds.height - padT + 3), withAttributes: ma)
        }

        // X-axis time labels
        let xa: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 8)]
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
    var sessionStartIdx: Int?           // index where current/last lid-closed session began
    var sessionEndIdx: Int?             // index where session ended (nil = still open)
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
            let end = isInSession ? allSamples.count : (sessionEndIdx ?? allSamples.count)
            plotView.sessionRange = si..<min(end, allSamples.count)
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

    // MARK: Sudoers (pmset only — temperature now uses IOKit directly, no sudo needed)

    func ensureSudoersRule() {
        let pmsetOK = !shell("sudo -n /usr/bin/pmset -g 2>&1").lowercased().contains("password")
        if pmsetOK { return }

        let user = NSUserName()
        let rule = "\n\(user) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *"
        let escaped = rule.replacingOccurrences(of: "'", with: "'\\''")
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
            sessionStartIdx = allSamples.count
            sessionEndIdx = nil
            sessionMax = 0
            sessionStart = Date()
            isInSession = true
        } else {
            isInSession = false
            sessionEndIdx = allSamples.count  // freeze the highlight here
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
            let temp = readCPUTempFromHID()
            DispatchQueue.main.async {
                guard temp > 0 else { return }
                self.currentTemp = temp

                if self.allSamples.count >= self.maxSamples {
                    self.allSamples.removeFirst()
                    if let si = self.sessionStartIdx { self.sessionStartIdx = max(0, si - 1) }
                    if let ei = self.sessionEndIdx   { self.sessionEndIdx   = max(0, ei - 1) }
                }
                self.allSamples.append(temp)

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
