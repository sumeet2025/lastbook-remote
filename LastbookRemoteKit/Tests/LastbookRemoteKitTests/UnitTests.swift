import XCTest
@testable import LastbookRemoteKit

final class AccessLinkTests: XCTestCase {
    func testParsesPrintedLink() {
        let l = AccessLink.parse("Lastbook is sharing on this network: http://192.168.1.20:8890/?key=abc-DEF_123")
        XCTAssertEqual(l, AccessLink(host: "192.168.1.20", port: 8890, key: "abc-DEF_123"))
    }

    func testDefaultsPortAndScheme() {
        XCTAssertEqual(AccessLink.parse("100.101.102.5/?key=k")?.port, 8890)
        XCTAssertEqual(AccessLink.parse("100.101.102.5/?key=k")?.scheme, "http")
        XCTAssertEqual(AccessLink.parse("http://10.0.0.2:8893/?key=k#/videos")?.port, 8893)
    }

    func testIPv6() {
        let l = AccessLink.parse("http://[fd7a:115c:a1e0::1]:8890/?key=k")
        XCTAssertEqual(l?.host, "fd7a:115c:a1e0::1")
        XCTAssertEqual(l?.displayAddress, "[fd7a:115c:a1e0::1]:8890")
    }

    func testRejectsLinkWithoutKey() {
        XCTAssertNil(AccessLink.parse("http://192.168.1.20:8890/"))
        XCTAssertNil(AccessLink.parse(""))
        XCTAssertNil(AccessLink.parse("ftp://1.2.3.4/?key=x"))
    }
}

final class HostAddressTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(HostAddress.classify("192.168.1.20"), .privateNetwork)
        XCTAssertEqual(HostAddress.classify("10.0.0.1"), .privateNetwork)
        XCTAssertEqual(HostAddress.classify("172.20.1.1"), .privateNetwork)
        XCTAssertEqual(HostAddress.classify("172.32.1.1"), .publicAddress)
        XCTAssertEqual(HostAddress.classify("100.101.102.5"), .tailscale)
        XCTAssertEqual(HostAddress.classify("100.128.0.1"), .publicAddress)
        XCTAssertEqual(HostAddress.classify("127.0.0.1"), .loopback)
        XCTAssertEqual(HostAddress.classify("localhost"), .loopback)
        XCTAssertEqual(HostAddress.classify("8.8.8.8"), .publicAddress)
        XCTAssertEqual(HostAddress.classify("mymac.tail1234.ts.net"), .name)
        XCTAssertEqual(HostAddress.classify("fd7a:115c:a1e0::5"), .tailscale)
        XCTAssertEqual(HostAddress.classify("fe80::1"), .privateNetwork)
        XCTAssertEqual(HostAddress.classify("[::1]"), .loopback)
        XCTAssertEqual(HostAddress.classify("2001:4860::8888"), .publicAddress)
        XCTAssertEqual(HostAddress.classify("300.1.1.1"), .name) // digits and dots, not an IP: treated as a name, refused
        XCTAssertEqual(HostAddress.classify("a b"), .invalid)
        XCTAssertEqual(HostAddress.classify(""), .invalid)
    }

    func testAllowed() {
        XCTAssertTrue(HostAddress.isAllowed(.tailscale))
        XCTAssertTrue(HostAddress.isAllowed(.privateNetwork))
        XCTAssertFalse(HostAddress.isAllowed(.publicAddress))
        XCTAssertFalse(HostAddress.isAllowed(.name))
    }
}

final class URLTests: XCTestCase {
    let client = LastbookClient(baseURL: URL(string: "http://192.168.1.20:8890/")!, key: "k+y/z")

    func testFileURLEncodesSegmentsLikeTheWebApp() {
        XCTAssertEqual(client.fileURL(path: "documents/Where There Is No Doctor (2023).pdf").absoluteString,
                       "http://192.168.1.20:8890/documents/Where%20There%20Is%20No%20Doctor%20(2023).pdf")
        XCTAssertEqual(client.fileURL(path: "videos/a#b?.mp4").absoluteString, "http://192.168.1.20:8890/videos/a%23b%3F.mp4")
    }

    func testKeyedURLEscapesKey() {
        XCTAssertEqual(client.keyedURL(path: "videos/a.mp4").absoluteString, "http://192.168.1.20:8890/videos/a.mp4?key=k%2By%2Fz")
    }

    func testHeaderCarriesKey() {
        let r = client.authorizedRequest(client.fileURL(path: "x.pdf"))
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Lastbook-Key"), "k+y/z")
    }

    func testProfileBaseURL() {
        XCTAssertEqual(ServerProfile(name: "x", host: "100.64.0.8", port: 8891).baseURL?.absoluteString, "http://100.64.0.8:8891/")
        XCTAssertEqual(ServerProfile(name: "x", host: "fd7a:115c:a1e0::1").baseURL?.absoluteString, "http://[fd7a:115c:a1e0::1]:8890/")
    }
}

final class ModelTests: XCTestCase {
    func testDecodesDocAndVideoCard() throws {
        let doc = #"{"id":"vid-h264","title":"T","kind":"video","kindLabel":"Video","publisher":"MIT","collection":"C","path":"videos/a.mp4","pages":null,"duration":20.5,"year":null,"trust":"Course","bytes":2095961,"transcript":false,"thumb":null,"course":"6.002"}"#
        let item = try JSONDecoder().decode(LibraryItem.self, from: Data(doc.utf8))
        XCTAssertEqual(item.itemKind, .video)
        XCTAssertEqual(item.bytes, 2095961)
        XCTAssertEqual(item.duration, 20.5)
        XCTAssertEqual(item.course, "6.002")
        let card = try JSONDecoder().decode(LibraryItem.self, from: Data(#"{"id":"v","title":"V","publisher":"P","duration":20,"thumb":null,"transcript":false,"trust":"t","year":"2019"}"#.utf8))
        XCTAssertEqual(card.itemKind, .video)
        XCTAssertNil(card.path)
        XCTAssertEqual(card.year, "2019")
    }

    func testItemKinds() {
        XCTAssertEqual(ItemKind(kind: "pdf", path: "a.pdf"), .pdf)
        XCTAssertEqual(ItemKind(kind: "text", path: "documents/notes.md"), .markdown)
        XCTAssertEqual(ItemKind(kind: "text", path: "documents/a.txt"), .text)
        XCTAssertEqual(ItemKind(kind: "html", path: "pages/a.html"), .html)
        XCTAssertEqual(ItemKind(kind: "zim", path: "wiki.zim"), .encyclopedia)
        XCTAssertEqual(ItemKind(kind: "pptx", path: "a.pptx"), .other)
    }

    func testSavedItemRoundTrips() throws {
        let s = SavedItem(id: "a/b", serverID: UUID(), serverName: "Mac", item: LibraryItem(id: "b", title: "B", kind: "pdf", path: "documents/b.pdf", bytes: 10),
                          fileName: "b.pdf", bytes: 10, savedAt: Date(timeIntervalSince1970: 1_000))
        let back = try JSONDecoder.iso.decode(SavedItem.self, from: JSONEncoder.iso.encode(s))
        XCTAssertEqual(back, s)
    }

    func testSnippet() {
        let p = Snippet.parts("<mark>Boil</mark> water &amp; <mark>stir</mark> &lt;1 min")
        XCTAssertEqual(p, [.init(text: "Boil", marked: true), .init(text: " water & ", marked: false), .init(text: "stir", marked: true), .init(text: " <1 min", marked: false)])
        XCTAssertEqual(Snippet.plain("a <mark>b</mark>"), "a b")
    }

    func testErrorMapping() {
        XCTAssertThrowsError(try LastbookClient.check(status: 403, body: Data(#"{"error": "This is not part of what is shared from this library."}"#.utf8))) {
            XCTAssertEqual($0 as? LastbookError, .notShared)
        }
        XCTAssertThrowsError(try LastbookClient.check(status: 403, body: Data("<!doctype html>".utf8))) {
            XCTAssertEqual($0 as? LastbookError, .accessDenied)
        }
        XCTAssertThrowsError(try LastbookClient.check(status: 403, body: Data(#"{"error":"not allowed from this page"}"#.utf8))) {
            XCTAssertEqual($0 as? LastbookError, .hostNameRefused)
        }
        XCTAssertNoThrow(try LastbookClient.check(status: 206, body: Data()))
    }
}

final class CodecTests: XCTestCase {
    func box(_ name: String, _ payload: [UInt8]) -> [UInt8] {
        let size = UInt32(8 + payload.count)
        return [UInt8(size >> 24), UInt8((size >> 16) & 0xff), UInt8((size >> 8) & 0xff), UInt8(size & 0xff)] + Array(name.utf8) + payload
    }

    func syntheticMP4(video: String) -> Data {
        let stsd = box("stsd", [0, 0, 0, 0, 0, 0, 0, 2] + box(video, [UInt8](repeating: 0, count: 78)) + box("mp4a", [UInt8](repeating: 0, count: 28)))
        let moov = box("moov", box("trak", box("mdia", box("minf", box("stbl", stsd)))))
        return Data(box("ftyp", Array("isom".utf8) + [0, 0, 2, 0]) + box("mdat", [UInt8](repeating: 7, count: 5000)) + moov)
    }

    func testFindsCodesAfterMdat() async throws {
        let file = syntheticMP4(video: "av01")
        let report = try await VideoCodecs.probe(path: "x.mp4") { off, len in
            let s = Int(min(Int64(file.count), off)), e = Int(min(Int64(file.count), off + len))
            return (file.subdata(in: s..<e), Int64(file.count))
        }
        XCTAssertEqual(report.codecs, ["av01", "mp4a"])
        XCTAssertEqual(report.unplayableFormat(av1Hardware: false), "AV1")
        XCTAssertNil(report.unplayableFormat(av1Hardware: true))
    }

    func testH264Plays() {
        XCTAssertNil(VideoFormatReport(container: .mp4, codecs: ["avc1", "mp4a"]).unplayableFormat(av1Hardware: false))
        XCTAssertEqual(VideoFormatReport(container: .mp4, codecs: ["vp09"]).unplayableFormat(av1Hardware: true), "VP9")
        XCTAssertEqual(VideoFormatReport(container: .webm, codecs: []).unplayableFormat(av1Hardware: true), "WebM")
    }
}

final class StoreTests: XCTestCase {
    func testServerStoreKeepsKeyOutOfFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keys = MemoryKeyStore()
        let store = ServerStore(fileURL: dir.appendingPathComponent("servers.json"), keys: keys)
        let p = ServerProfile(name: "Studio Mac", host: "192.168.1.20")
        _ = try store.upsert(p, key: "SECRET-KEY")
        XCTAssertEqual(store.load().map(\.name), ["Studio Mac"])
        XCTAssertEqual(keys.key(for: p.id), "SECRET-KEY")
        let raw = try String(contentsOf: dir.appendingPathComponent("servers.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("SECRET-KEY"))
        _ = try store.remove(p.id)
        XCTAssertNil(keys.key(for: p.id))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testStableFileNames() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let a = OfflineStore.fileName(server: id, itemID: "water guide/1", path: "documents/x.PDF")
        XCTAssertEqual(a, OfflineStore.fileName(server: id, itemID: "water guide/1", path: "documents/x.PDF"))
        XCTAssertTrue(a.hasPrefix("water_guide_1-"))
        XCTAssertTrue(a.hasSuffix(".pdf"))
    }

    func testCapCheck() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OfflineStore(folder: dir, cap: 1000)
        try await store.checkRoom(for: 1000)
        do {
            try await store.checkRoom(for: 1001)
            XCTFail("expected cap error")
        } catch let e as LastbookError {
            XCTAssertEqual(e, .storageCapExceeded(needed: 1001, available: 1000))
        }
    }
}
