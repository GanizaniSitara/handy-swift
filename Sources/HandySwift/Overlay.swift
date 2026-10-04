import Cocoa

/// State colours shared by the menu-bar icon and the pill, as Handy.NET's TrayIconManager.
enum Palette {
    static let idle = NSColor(srgbRed: 0x58 / 255.0, green: 0x93 / 255.0, blue: 0xDA / 255.0, alpha: 1)
    static let recording = NSColor(srgbRed: 0xE0 / 255.0, green: 0x40 / 255.0, blue: 0x3D / 255.0, alpha: 1)
    static let transcribing = NSColor(srgbRed: 0x43 / 255.0, green: 0xA0 / 255.0, blue: 0x47 / 255.0, alpha: 1)

    static func color(for state: Dictation.State) -> NSColor {
        switch state {
        case .idle: return idle
        case .recording: return recording
        case .transcribing: return transcribing
        }
    }

    /// Handy's tray glyph: a solid state-coloured disc with a bold white "H".
    static func trayIcon(_ state: Dictation.State, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let pad = max(1, size * 0.04)
            color(for: state).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: pad, dy: pad)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.62, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let h = NSAttributedString(string: "H", attributes: attrs)
            let t = h.size()
            h.draw(at: NSPoint(x: rect.midX - t.width / 2, y: rect.midY - t.height / 2))
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// The recording pill, laid out like Handy.NET's RecordingOverlay: a dark rounded box
/// (radius 10, padding 14×8) with a "Listening" label and five red level bars.
/// Non-activating and click-through, so it can never take focus from the target window.
final class Overlay {
    private let panel: NSPanel
    private let shell = NSView()
    private let label = NSTextField(labelWithString: "")
    private var bars: [NSView] = []
    private var timer: Timer?

    private enum Metric {
        static let padX: CGFloat = 14, padY: CGFloat = 8
        static let barsGap: CGFloat = 10, barWidth: CGFloat = 3, barMargin: CGFloat = 1
        static let barMin: CGFloat = 2, barMax: CGFloat = 18
        static let bottomOffset: CGFloat = 40
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        shell.wantsLayer = true
        shell.layer?.backgroundColor = NSColor(srgbRed: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 0.8).cgColor
        shell.layer?.cornerRadius = 10
        panel.contentView = shell

        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        shell.addSubview(label)

        for _ in 0..<5 {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = Palette.recording.cgColor
            bar.layer?.cornerRadius = 1.5
            shell.addSubview(bar)
            bars.append(bar)
        }
    }

    func show(_ state: Dictation.State, levels: @escaping () -> [Float]) {
        timer?.invalidate()
        timer = nil
        switch state {
        case .idle:
            panel.orderOut(nil)
            return
        case .recording:
            label.stringValue = "Listening"
            bars.forEach { $0.isHidden = false }
            timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.setLevels(levels()) }
            RunLoop.main.add(timer!, forMode: .common)
        case .transcribing:
            label.stringValue = "Transcribing"
            bars.forEach { $0.isHidden = true }
        }
        layout(showBars: state == .recording)
        setLevels([])
        panel.orderFrontRegardless()
    }

    /// Size to content, like WPF's SizeToContent, then place bottom-centre.
    private func layout(showBars: Bool) {
        label.sizeToFit()
        let text = label.frame.size
        let barsWidth = showBars ? Metric.barsGap + CGFloat(bars.count) * (Metric.barWidth + 2 * Metric.barMargin) : 0
        let contentH = max(text.height, Metric.barMax)
        let size = NSSize(width: Metric.padX * 2 + text.width + barsWidth, height: Metric.padY * 2 + contentH)

        label.setFrameOrigin(NSPoint(x: Metric.padX, y: (size.height - text.height) / 2))
        var x = Metric.padX + text.width + Metric.barsGap + Metric.barMargin
        for bar in bars {
            bar.frame = NSRect(x: x, y: (size.height - Metric.barMax) / 2, width: Metric.barWidth, height: Metric.barMin)
            x += Metric.barWidth + 2 * Metric.barMargin
        }

        // Screen with the cursor, as upstream Handy does; above the Dock/taskbar.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.minY + Metric.bottomOffset,
                              width: size.width, height: size.height), display: true)
    }

    /// Bars grow upward from a shared baseline, as in the WPF version (VerticalAlignment=Bottom).
    private func setLevels(_ levels: [Float]) {
        for (i, bar) in bars.enumerated() {
            let v = CGFloat(i < levels.count ? min(max(levels[i], 0), 1) : 0)
            bar.frame.size.height = Metric.barMin + v * (Metric.barMax - Metric.barMin)
        }
    }
}
