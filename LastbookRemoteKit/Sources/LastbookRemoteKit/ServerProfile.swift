import Foundation

/// One saved library. The access key is not stored here; it lives in the Keychain under `id`.
public struct ServerProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var scheme: String
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, host: String, port: Int = AccessLink.defaultPort, scheme: String = "http", addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.host = HostAddress.normalize(host)
        self.port = port
        self.scheme = scheme
        self.addedAt = addedAt
    }

    public var hostKind: HostKind { HostAddress.classify(host) }

    public var baseURL: URL? {
        URL(string: "\(scheme)://\(displayAddress)/")
    }

    public var displayAddress: String {
        let h = host.contains(":") ? "[\(host)]" : host
        return "\(h):\(port)"
    }
}
