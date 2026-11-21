import Foundation

/// A catalog record as Lastbook's `public()` returns it (`/api/doc/<id>`, search results,
/// shelf and collection items). Video cards from `/api/videos` carry only a subset, so most
/// fields are optional.
public struct LibraryItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: String?
    public var kindLabel: String?
    public var publisher: String?
    public var collection: String?
    public var path: String?
    public var pages: Int?
    public var duration: Double?
    public var year: String?
    public var trust: String?
    public var bytes: Int64?
    public var transcript: Bool?
    public var thumb: String?
    public var imageOnly: Bool?
    public var remote: String?
    public var course: String?
    public var level: String?
    public var notes: String?
    public var license: String?
    public var sourceURL: String?
    public var hits: [SearchHit]?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, kindLabel, publisher, collection, path, pages, duration, year, trust, bytes,
             transcript, thumb, imageOnly, remote, course, level, notes, license, hits
        case sourceURL = "source_url"
    }

    public init(id: String, title: String, kind: String? = nil, path: String? = nil, bytes: Int64? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.path = path
        self.bytes = bytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        kindLabel = try? c.decodeIfPresent(String.self, forKey: .kindLabel)
        publisher = try? c.decodeIfPresent(String.self, forKey: .publisher)
        collection = try? c.decodeIfPresent(String.self, forKey: .collection)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        pages = Flexible.int(c, .pages)
        duration = Flexible.double(c, .duration)
        year = Flexible.string(c, .year)
        trust = try? c.decodeIfPresent(String.self, forKey: .trust)
        bytes = Flexible.int(c, .bytes).map(Int64.init)
        transcript = try? c.decodeIfPresent(Bool.self, forKey: .transcript)
        thumb = try? c.decodeIfPresent(String.self, forKey: .thumb)
        imageOnly = try? c.decodeIfPresent(Bool.self, forKey: .imageOnly)
        remote = try? c.decodeIfPresent(String.self, forKey: .remote)
        course = Flexible.string(c, .course)
        level = Flexible.string(c, .level)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        license = try? c.decodeIfPresent(String.self, forKey: .license)
        sourceURL = try? c.decodeIfPresent(String.self, forKey: .sourceURL)
        hits = try? c.decodeIfPresent([SearchHit].self, forKey: .hits)
    }

    public var itemKind: ItemKind { ItemKind(kind: kind, path: path) }
}

/// How the app opens an item.
public enum ItemKind: String, Codable, Sendable {
    case pdf, video, text, markdown, html, encyclopedia, other

    public init(kind: String?, path: String?) {
        let ext = (path.map { ($0 as NSString).pathExtension.lowercased() }) ?? ""
        switch kind?.lowercased() {
        case "pdf": self = .pdf
        case "video": self = .video
        case "html": self = .html
        case "zim": self = .encyclopedia
        case "transcript", "text":
            self = (ext == "md" || ext == "markdown") ? .markdown : .text
        default:
            switch ext {
            case "pdf": self = .pdf
            case "mp4", "m4v", "mov", "webm", "mkv": self = .video
            case "md", "markdown": self = .markdown
            case "txt", "vtt", "srt", "json", "csv": self = .text
            case "html", "htm", "xhtml": self = .html
            default: self = kind == nil ? .video : .other  // video cards come without kind or path
            }
        }
    }

    public var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .video: return "play.rectangle"
        case .text, .markdown: return "doc.plaintext"
        case .html: return "globe"
        case .encyclopedia: return "books.vertical"
        case .other: return "doc"
        }
    }
}

public struct SearchHit: Codable, Hashable, Sendable {
    public var page: Int?
    /// HTML-escaped text with `<mark>` around the matched words.
    public var snippet: String?
}

public struct LibrarySummary: Codable, Hashable, Sendable {
    public var resources: Int?
    public var pdfs: Int?
    public var videos: Int?
    public var collections: Int?
    public var zims: [String]?
    public var pack: Bool?

    public init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case resources, pdfs, videos, collections, zims, pack }
        let c = try decoder.container(keyedBy: K.self)
        resources = Flexible.int(c, .resources)
        pdfs = Flexible.int(c, .pdfs)
        videos = Flexible.int(c, .videos)
        collections = Flexible.int(c, .collections)
        zims = try? c.decodeIfPresent([String].self, forKey: .zims)
        pack = try? c.decodeIfPresent(Bool.self, forKey: .pack)
    }
}

public struct Health: Codable, Hashable, Sendable {
    public var service: String?
    public var offline: Bool?
}

/// `/api/shelves`: the library's subject shelves with counts.
public struct Shelf: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var read: Int
    public var video: Int

    public init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case id, title, read, video }
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? id
        read = Flexible.int(c, .read) ?? 0
        video = Flexible.int(c, .video) ?? 0
    }

    public var total: Int { read + video }
}

/// `/api/shelf/<id>`: collections on a shelf, each with up to six items.
public struct ShelfPage: Codable, Hashable, Sendable {
    public var total: Int
    public var collections: [ShelfCollection]
    public var more: Bool
}

public struct ShelfCollection: Codable, Hashable, Identifiable, Sendable {
    public var collection: String
    public var count: Int
    public var trust: String?
    public var items: [LibraryItem]
    public var id: String { collection }
}

/// `/api/collection?name=`: every item in one collection (a course, a manual's chapters, a channel).
public struct CollectionPage: Codable, Hashable, Sendable {
    public var total: Int
    public var items: [LibraryItem]
    public var more: Bool
}

/// `/api/find?q=`.
public struct SearchResults: Codable, Hashable, Sendable {
    public var q: String?
    public var mode: String?
    public var expanded: [String]?
    public var results: [LibraryItem]
}

/// One row of `/api/videos`.
public struct VideoRow: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var note: String?
    public var count: Int
    public var items: [LibraryItem]
}

/// `/api/videos/<row>`.
public struct VideoList: Codable, Hashable, Sendable {
    public var title: String?
    public var note: String?
    public var total: Int
    public var items: [LibraryItem]
    public var more: Bool
}

/// `/api/page/<id>/<n>`: the text of one page.
public struct PageText: Codable, Hashable, Sendable {
    public var page: Int
    public var pages: Int
    public var text: String
}

/// `/api/assistant/status` as the share listener answers it.
public struct AssistantStatus: Codable, Hashable, Sendable {
    public var online: Bool?
    public var available: Bool?
    public var shared: Bool?
}

/// Decoding that tolerates a number sent as a string or a float sent where an int is expected.
enum Flexible {
    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(v) }
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return Int(v) }
        return nil
    }

    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Double? {
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return Double(v) }
        return nil
    }

    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> String? {
        if let v = try? c.decodeIfPresent(String.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: k) { return String(v) }
        return nil
    }
}
