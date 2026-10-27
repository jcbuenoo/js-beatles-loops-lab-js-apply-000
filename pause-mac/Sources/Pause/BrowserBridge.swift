import AppKit

/// Reads (and closes) the current tab in Safari and Chromium-based browsers via AppleScript.
/// macOS asks for permission the first time ("Pause wants to control Safari").
/// Firefox has no AppleScript support, so it's tracked as an app only.
@MainActor
final class BrowserBridge {
    static let safariFamily: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let chromiumFamily: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    static func isSupported(_ bundleID: String) -> Bool {
        safariFamily.contains(bundleID) || chromiumFamily.contains(bundleID)
    }

    /// Set when a browser refused (usually: Automation permission denied in System Settings).
    private(set) var lastError: String?
    private var scripts: [String: NSAppleScript] = [:]

    /// Only call this for a browser that is already running (the frontmost app):
    /// `tell application` would otherwise launch it.
    func currentURL(bundleID: String) -> String? {
        let source: String
        if Self.safariFamily.contains(bundleID) {
            source = """
            tell application id "\(bundleID)"
                if (count of windows) > 0 then return URL of current tab of front window
            end tell
            return ""
            """
        } else {
            source = """
            tell application id "\(bundleID)"
                if (count of windows) > 0 then return URL of active tab of front window
            end tell
            return ""
            """
        }
        return run(source)
    }

    func closeCurrentTab(bundleID: String) {
        let source: String
        if Self.safariFamily.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to close current tab of front window"
        } else if Self.chromiumFamily.contains(bundleID) {
            source = "tell application id \"\(bundleID)\" to close active tab of front window"
        } else {
            return
        }
        _ = run(source)
    }

    private func run(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return nil }
            scripts[source] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 {
                lastError = "macOS blocked Pause from reading your browser. Allow it in System Settings → Privacy & Security → Automation."
            } else if code != -1728 && code != -1719 {
                // -1728/-1719: no window or tab right now. Not worth reporting.
                lastError = error[NSAppleScript.errorMessage] as? String
            }
            return nil
        }
        lastError = nil
        return result.stringValue
    }
}
