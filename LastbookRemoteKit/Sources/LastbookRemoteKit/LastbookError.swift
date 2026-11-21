import Foundation

public enum LastbookError: Error, Equatable, Sendable, LocalizedError {
    /// 403 without the shared-scope message: wrong key, or sharing turned off and on with a new key.
    case accessDenied
    /// 403: the route exists but is not part of what the host shares (setup, update, notes...).
    case notShared
    /// 403 from `host_ok()`: the address was a name, not a bare IP.
    case hostNameRefused
    case notFound(String?)
    case server(status: Int, message: String?)
    /// The host did not answer: asleep, sharing stopped, different network, or Tailscale off.
    case unreachable(String)
    case timedOut
    /// iOS App Transport Security refused plain HTTP to this address.
    case insecureConnectionBlocked
    case badResponse
    case decoding(String)
    case cancelled
    case storageCapExceeded(needed: Int64, available: Int64)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "The computer refused the access key. Copy the current access link from Lastbook (Library and local AI → Share this library with my devices) and paste it again."
        case .notShared:
            return "This part of Lastbook stays on the host computer and is not shared with other devices."
        case .hostNameRefused:
            return "Lastbook accepts only an IP address today, not a computer name. Use the computer's IP address."
        case .notFound(let m):
            return m ?? "This item is not in the library."
        case .server(let status, let m):
            return m ?? "The computer answered with an error (\(status))."
        case .unreachable(let detail):
            return "Can't reach the computer. Check that it is awake, that Lastbook is sharing, and that this device is on the same Wi-Fi or on Tailscale. (\(detail))"
        case .timedOut:
            return "The computer took too long to answer. It may be asleep or on another network."
        case .insecureConnectionBlocked:
            return "iOS blocked a plain-HTTP connection to this address."
        case .badResponse:
            return "The computer sent an answer this app does not understand. Is this a Lastbook share link?"
        case .decoding(let d):
            return "The computer's answer could not be read (\(d)). Lastbook may be a different version."
        case .cancelled:
            return "Cancelled."
        case .storageCapExceeded(let needed, let available):
            let f = ByteCountFormatter()
            return "Not saved: this needs \(f.string(fromByteCount: needed)) but only \(f.string(fromByteCount: max(0, available))) is left under the offline storage limit. Delete something in Downloaded or raise the limit in Settings."
        }
    }

    /// True when the problem is the network or host rather than this request.
    public var isConnectivity: Bool {
        switch self {
        case .unreachable, .timedOut: return true
        default: return false
        }
    }

    static func from(urlError e: URLError) -> LastbookError {
        switch e.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .appTransportSecurityRequiresSecureConnection: return .insecureConnectionBlocked
        default: return .unreachable(e.localizedDescription)
        }
    }
}
