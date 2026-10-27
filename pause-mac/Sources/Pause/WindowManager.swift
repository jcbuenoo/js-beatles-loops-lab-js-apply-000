import AppKit
import SwiftUI

/// Opens the app's regular windows from anywhere (menu, hotkey, notification).
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum Kind: String {
        case today
        case urges
        case settings
    }

    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind) {
        if let window = windows[kind] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let state = AppState.shared
        let title: String
        let root: AnyView
        let size: NSSize
        switch kind {
        case .today:
            title = "Where did my day go?"
            root = AnyView(DayReportView().environmentObject(state))
            size = NSSize(width: 720, height: 760)
        case .urges:
            title = "Urge log"
            root = AnyView(UrgeLogView().environmentObject(state))
            size = NSSize(width: 760, height: 720)
        case .settings:
            title = "Pause settings"
            root = AnyView(SettingsView().environmentObject(state))
            size = NSSize(width: 640, height: 720)
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.setContentSize(size)
        window.center()
        window.setFrameAutosaveName("Pause.\(kind.rawValue)")
        window.delegate = self
        windows[kind] = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let kind = windows.first(where: { $0.value === window })?.key
        else { return }
        // Drop the SwiftUI view tree now so a closed window gives its memory back.
        // (Deferred a moment: the close may have come from a button inside that same view.)
        Task { @MainActor in window.contentView = nil }
        windows[kind] = nil
    }
}
