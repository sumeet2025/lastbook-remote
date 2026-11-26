import Foundation

/// The access link Lastbook prints or shows: `http://<ip>:<port>/?key=<key>`.
public struct AccessLink: Equatable, Sendable {
    public var scheme: String
    public var host: String
    public var port: Int
    public var key: String

    public static let defaultPort = 8890

    public init(scheme: String = "http", host: String, port: Int = AccessLink.defaultPort, key: String) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.key = key
    }

    /// Parse a pasted or scanned link. Accepts surrounding text and line breaks, a missing scheme,
    /// a `#fragment`, and a `lastbook://` link (treated as plain HTTP, the only transport today).
    public static func parse(_ text: String) -> AccessLink? {
        if case .link(let l) = inspect(text) { return l }
        return nil
    }

    /// What a scanned or pasted string turned out to be, so the scanner can say why it was not used.
    public enum Verdict: Equatable, Sendable {
        case link(AccessLink)
        /// A web address with no `key=`: probably the address bar after the redirect, not the access link.
        case missingKey
        /// Not a link at all (another QR code, Wi-Fi details, plain text).
        case notALink
    }

    public static func inspect(_ text: String) -> Verdict {
        // QR payloads can carry a byte-order mark, zero-width spaces or trailing line breaks.
        var s = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .notALink }
        if let r = s.range(of: "(https?|lastbook)://[^\\s]+", options: [.regularExpression, .caseInsensitive]) {
            s = String(s[r])
        } else if !s.contains("://") && !s.contains(where: \.isWhitespace) && (s.contains(".") || s.contains(":")) {
            s = "http://" + s
        } else {
            return .notALink
        }
        if s.lowercased().hasPrefix("lastbook://") { s = "http://" + s.dropFirst("lastbook://".count) }
        guard let comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = comps.host, !host.isEmpty else { return .notALink }
        let key = (comps.queryItems?.first(where: { $0.name == "key" })?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .missingKey }
        let port = comps.port ?? (scheme == "https" ? 443 : defaultPort)
        return .link(AccessLink(scheme: scheme, host: HostAddress.normalize(host), port: port, key: key))
    }

    /// The link without the key, for display.
    public var displayAddress: String {
        let h = host.contains(":") ? "[\(host)]" : host
        return "\(h):\(port)"
    }
}
