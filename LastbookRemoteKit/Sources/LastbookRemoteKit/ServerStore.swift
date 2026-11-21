import Foundation

/// Saved libraries (address and name only) in a JSON file; keys go to a `KeyStore`.
public final class ServerStore: @unchecked Sendable {
    public let fileURL: URL
    public let keys: KeyStore
    private let lock = NSLock()

    public init(fileURL: URL, keys: KeyStore) {
        self.fileURL = fileURL
        self.keys = keys
    }

    public func load() -> [ServerProfile] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.iso.decode([ServerProfile].self, from: data)) ?? []
    }

    public func save(_ servers: [ServerProfile]) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.iso.encode(servers).write(to: fileURL, options: .atomic)
    }

    /// Add or replace a profile and store its key.
    public func upsert(_ profile: ServerProfile, key: String) throws -> [ServerProfile] {
        try keys.setKey(key, for: profile.id)
        var all = load()
        if let i = all.firstIndex(where: { $0.id == profile.id }) {
            all[i] = profile
        } else {
            all.append(profile)
        }
        try save(all)
        return all
    }

    public func remove(_ id: UUID) throws -> [ServerProfile] {
        keys.removeKey(for: id)
        let all = load().filter { $0.id != id }
        try save(all)
        return all
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
