import Cocoa

/// The recording pill: a small panel above the Dock showing state and live mic level.
/// Non-activating and click-through, so it can never take focus from the target window.
final class Overlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private var bars: [NSView] = []
    private var timer: Timer?
    private var history = [Float](repeating: 0, count: 9)
    private let size = NSSize(width: 190, height: 36)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        bg.layer?.cornerRadius = size.height / 2
        panel.contentView = bg

        dot.frame = NSRect(x: 14, y: 13, width: 10, height: 10)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)

        label.frame = NSRect(x: 30, y: 9, width: 90, height: 18)
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        bg.addSubview(label)

        for i in 0..<history.count {
            let bar = NSView(frame: NSRect(x: 124 + CGFloat(i) * 6, y: 16, width: 3, height: 4))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.cgColor
            bar.layer?.cornerRadius = 1.5
            bg.addSubview(bar)
            bars.append(bar)
        }
    }

    func show(_ state: Dictation.State, level: @escaping () -> Float) {
        timer?.invalidate()
        timer = nil
        switch state {
        case .idle:
            panel.orderOut(nil)
            return
        case .recording:
            label.stringValue = "Listening"
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            bars.forEach { $0.isHidden = false }
            history = history.map { _ in 0 }
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.push(level())
            }
            RunLoop.main.add(timer!, forMode: .common)
        case .transcribing:
            label.stringValue = "Transcribing…"
            dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
            bars.forEach { $0.isHidden = true }
        }
        position()
        panel.orderFrontRegardless()
    }

    private func push(_ rms: Float) {
        history.removeFirst()
        // Speech RMS sits roughly in 0.005…0.2; map that range onto the bar height logarithmically.
        let db = 20 * log10(max(rms, 1e-5))
        history.append(min(max((db + 50) / 40, 0), 1))
        for (bar, v) in zip(bars, history) {
            let h = 4 + CGFloat(v) * 20
            bar.frame = NSRect(x: bar.frame.minX, y: (size.height - h) / 2, width: 3, height: h)
        }
    }

    /// Bottom-centre of the screen with the mouse, just above the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 24))
    }
}
