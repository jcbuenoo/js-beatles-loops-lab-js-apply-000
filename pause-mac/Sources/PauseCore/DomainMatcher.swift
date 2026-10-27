import Foundation

public enum DomainMatcher {
    /// "https://www.Reddit.com/r/foo" -> "reddit.com". Returns nil for non-web URLs (about:blank, file://…).
    public static func host(from urlString: String) -> String? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return stripWWW(host.lowercased())
    }

    /// Cleans whatever the user typed into a bare domain: " https://www.YouTube.com/feed " -> "youtube.com".
    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let slash = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return stripWWW(s)
    }

    /// True when `host` is the rule's domain or one of its subdomains (m.youtube.com matches youtube.com).
    public static func matches(host: String, rule: String) -> Bool {
        let h = stripWWW(host.lowercased())
        let r = normalize(rule)
        guard !r.isEmpty else { return false }
        return h == r || h.hasSuffix("." + r)
    }

    /// "a.b.example.com" -> ["a.b.example.com", "b.example.com", "example.com"]
    public static func candidates(for host: String) -> [String] {
        var parts = host.split(separator: ".").map(String.init)
        var result: [String] = []
        while parts.count >= 2 {
            result.append(parts.joined(separator: "."))
            parts.removeFirst()
        }
        return result.isEmpty ? [host] : result
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
