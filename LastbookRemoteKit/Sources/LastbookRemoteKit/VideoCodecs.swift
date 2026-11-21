import Foundation

/// Video and audio formats found in an MP4/MOV file's index, read the way Lastbook's web app does
/// (`videoFormats()` in web/app.js): walk the top-level boxes with small Range reads until `moov`,
/// then read only `moov` and look for sample-entry codes. Never reads the pictures or the sound.
public struct VideoFormatReport: Equatable, Sendable {
    public var container: Container
    public var codecs: [String]

    public enum Container: String, Sendable { case mp4, webm, mkv, unknown }

    public init(container: Container, codecs: [String]) {
        self.container = container
        self.codecs = codecs
    }

    /// The first format the named device cannot decode, as a person-readable name, or nil.
    /// `av1Hardware`: true on devices with an AV1 decoder (A17 Pro, M3 and later).
    public func unplayableFormat(av1Hardware: Bool) -> String? {
        switch container {
        case .webm: return "WebM"
        case .mkv: return "Matroska (MKV)"
        case .mp4, .unknown: break
        }
        for c in codecs {
            switch c {
            case "av01" where !av1Hardware: return "AV1"
            case "vp09", "vp08": return c == "vp09" ? "VP9" : "VP8"
            default: continue
            }
        }
        return nil
    }
}

public enum VideoCodecs {
    static let videoEntries: Set<String> = ["avc1", "avc3", "hvc1", "hev1", "av01", "vp09", "vp08", "mp4v", "dvh1", "dvhe", "apcn", "apch"]
    static let audioEntries: Set<String> = ["mp4a", "ac-3", "ec-3", "opus", "fLaC", "alac"]

    public static func container(forPath path: String) -> VideoFormatReport.Container {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v", "mov": return .mp4
        case "webm": return .webm
        case "mkv": return .mkv
        default: return .unknown
        }
    }

    /// Sample-entry codes inside a `moov` box: every `stsd` box lists its entries as
    /// `size(4) code(4) ...` after an 8-byte version/flags + entry-count header.
    public static func codes(inMoov data: Data) -> [String] {
        let b = [UInt8](data)
        var found: [String] = []
        func u32(_ at: Int) -> Int { (Int(b[at]) << 24) | (Int(b[at + 1]) << 16) | (Int(b[at + 2]) << 8) | Int(b[at + 3]) }
        var i = 4
        while i + 12 <= b.count {
            if b[i] == 0x73, b[i + 1] == 0x74, b[i + 2] == 0x73, b[i + 3] == 0x64 { // "stsd"
                let boxEnd = min(b.count, i - 4 + u32(i - 4))
                var count = u32(i + 8)
                var e = i + 12
                while count > 0, e + 8 <= boxEnd {
                    let size = u32(e)
                    if let code = String(bytes: b[(e + 4)..<(e + 8)], encoding: .ascii), !found.contains(code) {
                        found.append(code)
                    }
                    guard size >= 8 else { break }
                    e += size
                    count -= 1
                }
                i = max(i + 4, boxEnd)
                continue
            }
            i += 1
        }
        return found
    }

    /// Video codes only (drops audio such as `mp4a`).
    public static func videoCodes(_ codes: [String]) -> [String] { codes.filter { !audioEntries.contains($0) } }

    /// Read a file's formats through `read(offset, length)`, which returns at most `length` bytes
    /// (fewer at the end) and the total size when known.
    public static func probe(path: String, read: (Int64, Int64) async throws -> (Data, Int64?)) async throws -> VideoFormatReport {
        let container = container(forPath: path)
        guard container == .mp4 || container == .unknown else { return VideoFormatReport(container: container, codecs: []) }
        var offset: Int64 = 0
        var total: Int64?
        for _ in 0..<64 {
            let (head, t) = try await read(offset, 16)
            if total == nil { total = t }
            guard head.count >= 8 else { break }
            let h = [UInt8](head)
            var size = Int64(h[0]) << 24 | Int64(h[1]) << 16 | Int64(h[2]) << 8 | Int64(h[3])
            let name = String(bytes: h[4..<8], encoding: .ascii) ?? ""
            var headerLength: Int64 = 8
            if size == 1, h.count >= 16 {
                size = h[8..<16].reduce(Int64(0)) { ($0 << 8) | Int64($1) }
                headerLength = 16
            } else if size == 0, let t = total {
                size = t - offset
            }
            guard size >= headerLength else { break }
            if name == "moov" {
                let length = min(size - headerLength, 16 * 1024 * 1024)
                let (moov, _) = try await read(offset + headerLength, length)
                return VideoFormatReport(container: .mp4, codecs: codes(inMoov: moov))
            }
            offset += size
            if let t = total, offset >= t { break }
        }
        return VideoFormatReport(container: container, codecs: [])
    }

    /// Probe a local file (a saved video).
    public static func probe(fileURL: URL) async throws -> VideoFormatReport {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let total = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value
        return try await probe(path: fileURL.path) { off, len in
            try handle.seek(toOffset: UInt64(off))
            let d = try handle.read(upToCount: Int(len)) ?? Data()
            return (d, total)
        }
    }
}

extension LastbookClient {
    /// Read a library video's formats with a few small Range requests.
    public func videoFormats(path libraryPath: String) async throws -> VideoFormatReport {
        try await VideoCodecs.probe(path: libraryPath) { off, len in
            try await self.range(path: libraryPath, from: off, count: len)
        }
    }
}
