import Foundation

/// What kind of address a server profile points at. Lastbook's share listener accepts only
/// `localhost` or a bare IP address (`host_ok()` refuses names, including Tailscale MagicDNS).
public enum HostKind: Equatable, Sendable {
    case loopback
    /// RFC 1918 (10/8, 172.16/12, 192.168/16), IPv4 link-local, or IPv6 ULA / link-local.
    case privateNetwork
    /// Tailscale's CGNAT range 100.64.0.0/10 (also used by some other VPNs).
    case tailscale
    /// A public IP address. The server is plain HTTP and must not be reached over the internet.
    case publicAddress
    /// A host name. Lastbook refuses these today.
    case name
    case invalid
}

public enum HostAddress {
    /// Trim, drop brackets around an IPv6 literal, and lowercase.
    public static func normalize(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("[") && h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        return h.lowercased()
    }

    public static func classify(_ raw: String) -> HostKind {
        let h = normalize(raw)
        if h.isEmpty { return .invalid }
        if h == "localhost" { return .loopback }
        if let v4 = ipv4Octets(h) {
            switch (v4[0], v4[1]) {
            case (127, _): return .loopback
            case (10, _), (192, 168), (169, 254): return .privateNetwork
            case (172, 16...31): return .privateNetwork
            case (100, 64...127): return .tailscale
            case (0, _): return .invalid
            default: return .publicAddress
            }
        }
        if h.contains(":") {
            guard isIPv6(h) else { return .invalid }
            if h == "::1" { return .loopback }
            if h.hasPrefix("fd7a:115c:a1e0:") { return .tailscale }
            if h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe8") || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb") {
                return .privateNetwork
            }
            return .publicAddress
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        if h.unicodeScalars.allSatisfy({ allowed.contains($0) }) && !h.hasPrefix(".") && !h.hasPrefix("-") {
            return .name
        }
        return .invalid
    }

    /// True when the app may connect: loopback, a private network, or a VPN such as Tailscale.
    public static func isAllowed(_ kind: HostKind) -> Bool {
        switch kind {
        case .loopback, .privateNetwork, .tailscale: return true
        case .publicAddress, .name, .invalid: return false
        }
    }

    /// The text to show under the address field.
    public static func advice(for kind: HostKind) -> String {
        switch kind {
        case .loopback: return "This device itself. Useful only in the simulator."
        case .privateNetwork: return "Local network address. Works when both devices are on the same Wi-Fi."
        case .tailscale: return "Tailscale (VPN) address. Works away from home while Tailscale is on, on both devices."
        case .publicAddress: return "This is a public internet address. Lastbook sharing is plain HTTP and must not be put on the internet. Use the computer's local or Tailscale IP."
        case .name: return "Lastbook accepts only an IP address today, not a name (including Tailscale MagicDNS names). Enter the computer's IP."
        case .invalid: return "Enter an IP address such as 192.168.1.20 or 100.101.102.5."
        }
    }

    static func ipv4Octets(_ h: String) -> [Int]? {
        let parts = h.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p), n <= 255 else { return nil }
            out.append(n)
        }
        return out
    }

    static func isIPv6(_ h: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef:.")
        guard h.unicodeScalars.allSatisfy({ hex.contains($0) }) else { return false }
        let doubles = h.components(separatedBy: "::").count - 1
        guard doubles <= 1 else { return false }
        let groups = h.split(separator: ":", omittingEmptySubsequences: true)
        if groups.contains(where: { $0.count > 4 && !$0.contains(".") }) { return false }
        return doubles == 1 ? groups.count < 8 : groups.count == 8
    }
}
