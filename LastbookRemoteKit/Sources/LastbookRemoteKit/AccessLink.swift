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

    /// Parse a pasted link. Accepts surrounding text, a missing scheme, and a `#fragment`.
    public static func parse(_ text: String) -> AccessLink? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "https?://[^\\s]+", options: [.regularExpression, .caseInsensitive]) {
            s = String(s[r])
        } else if !s.isEmpty && !s.contains("://") {
            s = "http://" + s
        }
        guard let comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = comps.host, !host.isEmpty else { return nil }
        let key = comps.queryItems?.first(where: { $0.name == "key" })?.value ?? ""
        guard !key.isEmpty else { return nil }
        let port = comps.port ?? (scheme == "https" ? 443 : defaultPort)
        return AccessLink(scheme: scheme, host: HostAddress.normalize(host), port: port, key: key)
    }

    /// The link without the key, for display.
    public var displayAddress: String {
        let h = host.contains(":") ? "[\(host)]" : host
        return "\(h):\(port)"
    }
}
