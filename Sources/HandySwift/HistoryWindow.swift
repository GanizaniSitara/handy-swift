import SwiftUI

final class HistoryWindowController {
    private var window: NSWindow?
    private let history: HistoryService

    init(history: HistoryService) { self.history = history }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: HistoryView(history: history, close: { [weak self] in
                self?.window?.performClose(nil)
            })))
            w.title = "Handy Swift — History"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 720, height: 560))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HistoryView: View {
    @ObservedObject var history: HistoryService
    let close: () -> Void
    @State private var selection: UUID?
    @State private var confirmingClear = false

    private var selected: HistoryEntry? { history.entries.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent transcripts").font(.title3).fontWeight(.semibold)
                Spacer()
                Text("\(history.entries.count) saved").foregroundStyle(.secondary)
            }
            if let error = history.error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            List(selection: $selection) {
                ForEach(history.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.timestampUtc.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .tag(entry.id)
                }
            }
            .overlay {
                if history.entries.isEmpty {
                    Text("No transcripts yet. Completed dictations will appear here.")
                        .foregroundStyle(.secondary).padding()
                }
            }
            HStack {
                Button("Copy selected") {
                    if let selected { Injector.copyToClipboard(selected.text) }
                }.disabled(selected == nil)
                Button("Delete selected") {
                    if let selection { history.remove(selection) }
                    selection = nil
                }.disabled(selected == nil)
                Button("Clear all") { confirmingClear = true }.disabled(history.entries.isEmpty)
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 600, minHeight: 360)
        .alert("Clear history?", isPresented: $confirmingClear) {
            Button("Delete all", role: .destructive) { history.clear(); selection = nil }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete every entry from the transcript history?")
        }
    }
}
