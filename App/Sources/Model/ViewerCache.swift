import Foundation
import LastbookRemoteKit

/// Temporary copies of documents being viewed (PDFKit needs a file or the whole data; it cannot add
/// the access header). Lives in Caches, so iOS may purge it; "Clear cache" empties it. This is not
/// Save for offline: nothing here is listed in Downloaded.
final class ViewerCache: @unchecked Sendable {
    static let shared = ViewerCache()

    let folder: URL
    /// Keep the folder under this size by deleting the oldest files.
    let limit: Int64 = 500 * 1024 * 1024

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Viewing", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func file(for item: LibraryItem, server: UUID, client: LastbookClient) async throws -> URL {
        guard let path = item.path else { throw LastbookError.notFound("This item has no file.") }
        let ext = (path as NSString).pathExtension
        let name = "\(server.uuidString)-\(Self.hash(item.id + "|" + path))" + (ext.isEmpty ? "" : ".\(ext)")
        let dest = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
            return dest
        }
        var request = client.authorizedRequest(client.fileURL(path: path))
        request.timeoutInterval = 60
        let tmp: URL
        let response: URLResponse
        do {
            (tmp, response) = try await client.session.download(for: request)
        } catch let e as URLError {
            throw e.code == .cancelled ? LastbookError.cancelled : LastbookError.unreachable(e.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LastbookError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tmp)
            switch http.statusCode {
            case 403: throw LastbookError.accessDenied
            case 404: throw LastbookError.notFound(nil)
            default: throw LastbookError.server(status: http.statusCode, message: nil)
            }
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        trim()
        return dest
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        for e in entries where total > limit {
            try? FileManager.default.removeItem(at: e.0)
            total -= e.1
        }
    }

    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 36)
    }
}
