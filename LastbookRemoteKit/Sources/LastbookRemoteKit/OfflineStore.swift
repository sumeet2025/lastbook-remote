import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One item the person saved for offline use.
public struct SavedItem: Codable, Identifiable, Hashable, Sendable {
    /// `<server id>/<item id>`: the same item from two libraries is saved twice.
    public var id: String
    public var serverID: UUID
    public var serverName: String
    public var item: LibraryItem
    /// File name inside the store's folder.
    public var fileName: String
    public var bytes: Int64
    public var savedAt: Date

    public var kind: ItemKind { item.itemKind }

    public static func makeID(server: UUID, item: String) -> String { "\(server.uuidString)/\(item)" }
}

/// Files saved for offline use, in the app's own sandbox (Application Support, excluded from
/// iCloud backup), with a storage cap. Partial downloads are kept as `.part` files and resumed
/// with HTTP Range.
public actor OfflineStore {
    public static let defaultCap: Int64 = 5 * 1024 * 1024 * 1024  // 5 GB
    public static let chunkSize: Int64 = 8 * 1024 * 1024

    public let folder: URL
    public private(set) var cap: Int64
    private var items: [SavedItem]
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    public init(folder: URL, cap: Int64 = OfflineStore.defaultCap) {
        self.folder = folder
        self.cap = cap
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Self.excludeFromBackup(folder)
        let idx = folder.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: idx), let saved = try? JSONDecoder.iso.decode([SavedItem].self, from: data) {
            // Drop entries whose file went missing.
            items = saved.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
        } else {
            items = []
        }
    }

    public func all() -> [SavedItem] { items.sorted { $0.savedAt > $1.savedAt } }

    public func saved(server: UUID, item: String) -> SavedItem? {
        items.first { $0.id == SavedItem.makeID(server: server, item: item) }
    }

    public func fileURL(for saved: SavedItem) -> URL { folder.appendingPathComponent(saved.fileName) }

    public func setCap(_ newCap: Int64) { cap = max(0, newCap) }

    /// Bytes used by saved items and by partial downloads.
    public func usedBytes() -> Int64 {
        items.reduce(0) { $0 + $1.bytes } + partialBytes()
    }

    public func available() -> Int64 { cap - usedBytes() }

    /// Throws `.storageCapExceeded` when `bytes` more would go over the cap.
    public func checkRoom(for bytes: Int64, partialAlready: Int64 = 0) throws {
        let free = available()
        let need = bytes - partialAlready
        if need > free { throw LastbookError.storageCapExceeded(needed: need, available: free) }
    }

    /// Download one library file (resumable) and record it. `progress` gets (bytesDone, total).
    @discardableResult
    public func save(_ item: LibraryItem, server: ServerProfile, client: LastbookClient,
                     progress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> SavedItem {
        guard let path = item.path, !path.isEmpty else { throw LastbookError.notFound("This item has no file to save.") }
        if let existing = saved(server: server.id, item: item.id) { return existing }

        let fileName = Self.fileName(server: server.id, itemID: item.id, path: path)
        let final = folder.appendingPathComponent(fileName)
        let part = folder.appendingPathComponent(fileName + ".part")
        var done = Self.size(of: part)

        var total = item.bytes ?? -1
        if total <= 0 { total = try await client.contentLength(path: path) ?? -1 }
        if total > 0 { try checkRoom(for: total, partialAlready: done) }

        if !FileManager.default.fileExists(atPath: part.path) {
            _ = FileManager.default.createFile(atPath: part.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        try handle.seekToEnd()

        while total < 0 || done < total {
            try Task.checkCancellation()
            let want = total > 0 ? min(Self.chunkSize, total - done) : Self.chunkSize
            let (data, reported) = try await client.range(path: path, from: done, count: want)
            if let r = reported, r > 0, total <= 0 {
                total = r
                try checkRoom(for: total, partialAlready: done)
            }
            if data.isEmpty { break }
            try handle.write(contentsOf: data)
            done += Int64(data.count)
            progress?(done, max(total, done))
            if total < 0 && Int64(data.count) < want { break }  // size unknown and the server sent the end
        }
        try handle.synchronize()
        try handle.close()
        if total > 0 && done != total {
            throw LastbookError.server(status: 0, message: "The download ended early (\(done) of \(total) bytes). Try again to resume.")
        }
        if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
        try FileManager.default.moveItem(at: part, to: final)

        let saved = SavedItem(id: SavedItem.makeID(server: server.id, item: item.id), serverID: server.id,
                              serverName: server.name, item: item, fileName: fileName, bytes: done, savedAt: Date())
        items.append(saved)
        try writeIndex()
        return saved
    }

    public func delete(_ id: String) throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let url = folder.appendingPathComponent(items[i].fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        items.remove(at: i)
        try writeIndex()
    }

    /// Delete every saved item and every partial download.
    public func deleteAll() throws {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name != "index.json" {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        items = []
        try writeIndex()
    }

    /// Remove a partial download (the person cancelled and does not want to resume).
    public func discardPartial(server: UUID, item: LibraryItem) {
        guard let path = item.path else { return }
        let part = folder.appendingPathComponent(Self.fileName(server: server, itemID: item.id, path: path) + ".part")
        try? FileManager.default.removeItem(at: part)
    }

    private func partialBytes() -> Int64 {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".part") }.reduce(0) { $0 + Self.size(of: folder.appendingPathComponent($1)) }
    }

    private func writeIndex() throws {
        try JSONEncoder.iso.encode(items).write(to: indexURL, options: .atomic)
    }

    static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// A stable, file-system-safe name that keeps the original extension (PDFKit and AVPlayer use it).
    static func fileName(server: UUID, itemID: String, path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        let safe = itemID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        let short = String(safe.prefix(80))
        let hash = String(stableHash(server.uuidString + "/" + itemID), radix: 36)
        return "\(short)-\(hash)" + (ext.isEmpty ? "" : ".\(ext)")
    }

    /// FNV-1a, so names do not change between launches (Swift's `hashValue` does).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    static func excludeFromBackup(_ url: URL) {
        #if os(iOS) || os(macOS)
        var u = url
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        #endif
    }
}
