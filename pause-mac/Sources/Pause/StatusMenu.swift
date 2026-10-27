import AppKit
import PauseCore

/// The ⏸ menu bar icon and its menu. A native NSMenu, rebuilt only at the moment you open it,
/// so nothing about it sits in memory or redraws in the background.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private unowned let state: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Pause")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Opens the menu as if clicked (used by the screenshot tests).
    func open() {
        statusItem.button?.performClick(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let report = state.report(for: Date())

        menu.addItem(info("Today", bold: true))
        if report.totalActive >= 60 {
            let distracted = report.seconds(in: .distracting)
            let percent = Int((report.share(of: .distracting) * 100).rounded())
            menu.addItem(info("Active \(DayReport.format(report.totalActive))  ·  Distracted \(DayReport.format(distracted)) (\(percent)%)"))
            if report.longestFocus >= 60 {
                menu.addItem(info("Longest focus \(DayReport.format(report.longestFocus))"))
            }
        } else {
            menu.addItem(info("Nothing tracked yet today"))
        }
        if !report.urges.isEmpty {
            menu.addItem(info("Urges resisted: \(report.urgesResisted) of \(report.urges.count)"))
        }
        if state.settings.guards.isEmpty {
            menu.addItem(info("No guards yet. Add some in Guards & Settings."))
        }

        let unlocks = state.guardian.activeUnlocks
        if !unlocks.isEmpty {
            menu.addItem(.separator())
            for unlock in unlocks {
                let minutes = max(1, Int((unlock.expires.timeIntervalSinceNow / 60).rounded(.up)))
                let item = NSMenuItem(title: "Lock \(unlock.rule.displayName) now (\(minutes) min left)", action: #selector(relock(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = unlock.rule.id
                item.image = NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let log = action("Log an Urge…", "bolt.heart", #selector(logUrge))
        log.keyEquivalent = "u"
        log.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(log)
        menu.addItem(action("Where Did My Day Go?", "chart.bar.xaxis", #selector(showToday)))
        menu.addItem(action("Urge Log & Patterns", "list.bullet.rectangle", #selector(showUrges)))
        menu.addItem(action("Guards & Settings…", "hand.raised", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Pause", "power", #selector(quit)))
    }

    private func info(_ title: String, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
        }
        return item
    }

    private func action(_ title: String, _ symbol: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func relock(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { state.guardian.relock(id) }
    }

    @objc private func logUrge() { state.urgeLogger.show() }
    @objc private func showToday() { WindowManager.shared.show(.today) }
    @objc private func showUrges() { WindowManager.shared.show(.urges) }
    @objc private func showSettings() { WindowManager.shared.show(.settings) }
    @objc private func quit() { NSApp.terminate(nil) }
}
