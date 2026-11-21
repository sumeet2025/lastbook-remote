import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to one Lastbook share listener (`server.py --lan`, or the desktop app's
/// "Share this library with my devices", Lastbook PR #343).
///
/// Every request carries the access key in the `X-Lastbook-Key` header. Only the read-only
/// routes on the listener's allowlist are used; this client never calls setup, update, notes,
/// tools or the share switch.
public struct LastbookClient: Sendable {
    public let baseURL: URL
    public let key: String
    public let session: URLSession
    public var timeout: TimeInterval

    public init(baseURL: URL, key: String, session: URLSession = .shared, timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.key = key
        self.session = session
        self.timeout = timeout
    }

    public init?(profile: ServerProfile, key: String, session: URLSession = .shared) {
        guard let url = profile.baseURL else { return nil }
        self.init(baseURL: url, key: key, session: session)
    }

    public init?(link: AccessLink, session: URLSession = .shared) {
        let h = link.host.contains(":") ? "[\(link.host)]" : link.host
        guard let url = URL(string: "\(link.scheme)://\(h):\(link.port)/") else { return nil }
        self.init(baseURL: url, key: link.key, session: session)
    }

    // MARK: URLs

    /// `path` is already percent-encoded and starts with `/`.
    public func url(encodedPath path: String, query: [URLQueryItem] = []) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.percentEncodedPath = path
        if !query.isEmpty {
            // URLQueryItem leaves '+' and '&' alone in values; encode them so the server reads them literally.
            c.percentEncodedQuery = query.map { item in
                let v = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: PathEncoding.allowed) ?? ""
                return "\(PathEncoding.encode(component: item.name))=\(v)"
            }.joined(separator: "&")
        }
        return c.url!
    }

    /// The URL of a library file (`documents/x.pdf`, `videos/y.mp4`, a thumbnail).
    public func fileURL(path libraryPath: String) -> URL {
        url(encodedPath: PathEncoding.filePath(libraryPath))
    }

    /// The same file URL with `?key=`, for players that cannot add headers to every range request
    /// (AVPlayer, AirPlay receivers). The listener accepts the key in the query and strips it before dispatch.
    public func keyedURL(path libraryPath: String) -> URL {
        url(encodedPath: PathEncoding.filePath(libraryPath), query: [URLQueryItem(name: "key", value: key)])
    }

    /// The host's own web app, opened with the access link so the web view gets the `sg_key` cookie.
    public var webAppURL: URL {
        url(encodedPath: "/", query: [URLQueryItem(name: "key", value: key)])
    }

    /// A request with the access key attached.
    public func authorizedRequest(_ url: URL, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(key, forHTTPHeaderField: "X-Lastbook-Key")
        return r
    }

    // MARK: API

    public func health() async throws -> Health { try await get("/api/health") }
    public func library() async throws -> LibrarySummary { try await get("/api/library") }
    public func shelves() async throws -> [Shelf] { try await get("/api/shelves") }

    public func shelf(_ id: String, kind: String = "all", query q: String = "", offset: Int = 0) async throws -> ShelfPage {
        var qs = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "offset", value: String(offset))]
        if !q.isEmpty { qs.append(URLQueryItem(name: "q", value: q)) }
        return try await get("/api/shelf/" + PathEncoding.encode(component: id), query: qs)
    }

    public func collection(_ name: String, offset: Int = 0) async throws -> CollectionPage {
        try await get("/api/collection", query: [URLQueryItem(name: "name", value: name), URLQueryItem(name: "offset", value: String(offset))])
    }

    /// Full-text search. `kind` is Lastbook's filter: `all`, `read`, or `video`.
    public func search(_ q: String, kind: String = "all") async throws -> SearchResults {
        try await get("/api/find", query: [URLQueryItem(name: "q", value: String(q.prefix(200))), URLQueryItem(name: "kind", value: kind)])
    }

    public func videoRows() async throws -> [VideoRow] { try await get("/api/videos") }

    public func videos(row: String = "all", query q: String = "", sort: String = "", offset: Int = 0) async throws -> VideoList {
        var qs = [URLQueryItem(name: "offset", value: String(offset))]
        if !q.isEmpty { qs.append(URLQueryItem(name: "q", value: q)) }
        if !sort.isEmpty { qs.append(URLQueryItem(name: "sort", value: sort)) }
        return try await get("/api/videos/" + PathEncoding.encode(component: row), query: qs)
    }

    public func item(_ id: String) async throws -> LibraryItem {
        try await get("/api/doc/" + PathEncoding.encode(component: id))
    }

    public func pageText(_ id: String, page: Int) async throws -> PageText {
        try await get("/api/page/\(PathEncoding.encode(component: id))/\(page)")
    }

    public func assistantStatus() async throws -> AssistantStatus { try await get("/api/assistant/status") }

    /// Size of a library file from a HEAD request, when the catalog did not say.
    public func contentLength(path libraryPath: String) async throws -> Int64? {
        let (_, resp) = try await send(authorizedRequest(fileURL(path: libraryPath), method: "HEAD"))
        let len = resp.expectedContentLength
        return len >= 0 ? len : nil
    }

    /// Bytes `[from, from+count)` of a library file (`Range` request; the listener answers 206).
    public func range(path libraryPath: String, from: Int64, count: Int64) async throws -> (Data, total: Int64?) {
        var r = authorizedRequest(fileURL(path: libraryPath))
        r.setValue("bytes=\(from)-\(from + count - 1)", forHTTPHeaderField: "Range")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await send(r)
        var total: Int64?
        if resp.statusCode == 206, let cr = resp.value(forHTTPHeaderField: "Content-Range"), let slash = cr.lastIndex(of: "/") {
            total = Int64(cr[cr.index(after: slash)...])
        } else if resp.statusCode == 200 {
            // A server that ignores Range sends the whole file.
            total = Int64(data.count)
            let start = Int(min(Int64(data.count), from))
            let end = Int(min(Int64(data.count), from + count))
            return (data.subdata(in: start..<end), total)
        }
        return (data, total)
    }

    /// Fetch raw bytes (a small document, a thumbnail).
    public func data(path libraryPath: String) async throws -> Data {
        let (data, _) = try await send(authorizedRequest(fileURL(path: libraryPath)))
        return data
    }

    /// Check the address and key: `/api/health` must answer as Lastbook and `/api/library` must accept the key.
    public func testConnection() async throws -> LibrarySummary {
        let h = try await health()
        guard h.service != nil || h.offline != nil else { throw LastbookError.badResponse }
        return try await library()
    }

    // MARK: Transport

    func get<T: Decodable>(_ encodedPath: String, query: [URLQueryItem] = []) async throws -> T {
        var r = authorizedRequest(url(encodedPath: encodedPath, query: query))
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await send(r)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let e as DecodingError {
            throw LastbookError.decoding(Self.describe(e))
        } catch {
            throw LastbookError.badResponse
        }
    }

    @discardableResult
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let e as URLError {
            throw LastbookError.from(urlError: e)
        } catch is CancellationError {
            throw LastbookError.cancelled
        }
        guard let http = response as? HTTPURLResponse else { throw LastbookError.badResponse }
        try Self.check(status: http.statusCode, body: data)
        return (data, http)
    }

    static func check(status: Int, body: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error
        switch status {
        case 403:
            if let m = message, m.lowercased().contains("not part of what is shared") { throw LastbookError.notShared }
            if let m = message, m.lowercased().contains("not allowed from this page") { throw LastbookError.hostNameRefused }
            throw LastbookError.accessDenied
        case 401: throw LastbookError.accessDenied
        case 404: throw LastbookError.notFound(message)
        default: throw LastbookError.server(status: status, message: message)
        }
    }

    struct ErrorBody: Decodable { let error: String? }

    static func describe(_ e: DecodingError) -> String {
        switch e {
        case .keyNotFound(let k, _): return "missing \(k.stringValue)"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            return c.codingPath.map(\.stringValue).joined(separator: ".")
        @unknown default: return "unknown"
        }
    }
}

extension LastbookClient {
    /// The session the app uses for API calls and downloads: the key goes in a header on every
    /// request, so no cookies are stored (turning sharing off or changing the key takes effect at once).
    /// Responses are cached in a small capped cache that "Clear cache" empties.
    public static func makeSession(cache: URLCache? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }
}
