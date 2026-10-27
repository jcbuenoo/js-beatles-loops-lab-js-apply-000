import AppKit
import PauseCore
import SwiftUI

/// The two-second urge logger that pops up on ⌥⌘U, then gives focus back to whatever you were doing.
@MainActor
final class UrgeLoggerController: NSObject, NSWindowDelegate {
    private unowned let state: AppState
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func show() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        var context = front?.localizedName
        if let last = state.tracker.lastFrontmost, last.bundleID == front?.bundleIdentifier {
            context = last.description
        }

        let view = UrgeQuickLogView(context: context) { [weak self] entry in
            if let entry { self?.state.addUrge(entry) }
            self?.panel?.close()
        }
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Log an urge"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.delegate = self
        panel.center()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        previousApp?.activate(options: [.activateIgnoringOtherApps])
        previousApp = nil
    }
}

struct UrgeQuickLogView: View {
    let context: String?
    let onDone: (UrgeEntry?) -> Void

    @State private var text = ""
    @State private var intensity = 3
    @State private var outcome: UrgeOutcome = .resisted
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("I feel an urge to…")
                .font(.headline)
            TextField("check Reddit, buy something, snack, switch tasks…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)

            LabeledContent("How strong?") {
                Picker("How strong?", selection: $intensity) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            LabeledContent("Right now I…") {
                Picker("Right now I…", selection: $outcome) {
                    ForEach(UrgeOutcome.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let context {
                Text("While in \(context)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Just noticing an urge is the skill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Log it", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(width: 460)
        .onAppear { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onDone(UrgeEntry(text: trimmed, intensity: intensity, outcome: outcome, context: context, source: .manual))
    }
}
