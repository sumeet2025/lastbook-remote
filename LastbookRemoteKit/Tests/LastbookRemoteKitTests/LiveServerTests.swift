import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LastbookRemoteKit

/// End-to-end checks against a real Lastbook share listener with the sample library.
///
///     python3 scripts/make_sample_library.py /tmp/lastbook-sample
///     (cd ../lastbook && python3 server.py --lan --no-index --data /tmp/lastbook-sample)
///     LASTBOOK_TEST_LINK='http://127.0.0.1:8890/?key=…' swift test
///
/// Skipped when LASTBOOK_TEST_LINK is not set.
final class LiveServerTests: XCTestCase {
    var link: AccessLink!
    var client: LastbookClient!

    override func setUpWithError() throws {
        guard let raw = ProcessInfo.processInfo.environment["LASTBOOK_TEST_LINK"], let l = AccessLink.parse(raw) else {
            throw XCTSkip("Set LASTBOOK_TEST_LINK to a share link to run live tests")
        }
        link = l
        client = LastbookClient(link: l)
    }

    func testConnectionAndSummary() async throws {
        let summary = try await client.testConnection()
        XCTAssertGreaterThan(summary.resources ?? 0, 0)
    }

    func testWrongKeyIsRefused() async throws {
        let bad = LastbookClient(baseURL: client.baseURL, key: "wrong-key")
        do {
            _ = try await bad.library()
            XCTFail("expected 403")
        } catch let e as LastbookError {
            XCTAssertEqual(e, .accessDenied)
        }
    }

    func testHostOnlyRoutesAreNotShared() async throws {
        do {
            let _: [String: String] = try await client.get("/api/setup/status")
            XCTFail("expected 403")
        } catch let e as LastbookError {
            XCTAssertEqual(e, .notShared)
        }
    }

    func testBrowseShelvesCollectionsAndDocs() async throws {
        let shelves = try await client.shelves()
        let water = try XCTUnwrap(shelves.first { $0.id == "water" })
        XCTAssertEqual(water.read, 1)
        let page = try await client.shelf("water")
        XCTAssertEqual(page.collections.first?.collection, "Water Basics")
        let course = try await client.collection("MIT 6.002 Circuits")
        XCTAssertEqual(Set(course.items.map(\.id)), ["circuits-notes", "vid-h264"])
        let doc = try await client.item("water-guide")
        XCTAssertEqual(doc.itemKind, .pdf)
        XCTAssertEqual(doc.pages, 3)
        do {
            _ = try await client.item("no-such-item")
            XCTFail("expected 404")
        } catch LastbookError.notFound(let m) {
            XCTAssertNotNil(m)
        }
    }

    func testSearch() async throws {
        let r = try await client.search("boil water")
        let first = try XCTUnwrap(r.results.first)
        XCTAssertEqual(first.id, "water-guide")
        XCTAssertTrue(first.hits?.contains { Snippet.parts($0.snippet ?? "").contains { $0.marked } } ?? false)
        let none = try await client.search("zzzxqv")
        XCTAssertTrue(none.results.isEmpty)
    }

    func testVideos() async throws {
        let rows = try await client.videoRows()
        XCTAssertTrue(rows.flatMap(\.items).contains { $0.id == "vid-h264" })
        let all = try await client.videos()
        XCTAssertEqual(all.total, 2)
        let card = try XCTUnwrap(all.items.first { $0.id == "vid-h264" })
        XCTAssertNil(card.path)  // cards carry no path: the app fetches /api/doc first
        let full = try await client.item(card.id)
        XCTAssertEqual(full.path, "videos/h264-sample.mp4")
    }

    func testRangeAndCodecProbe() async throws {
        let (data, total) = try await client.range(path: "videos/h264-sample.mp4", from: 0, count: 100)
        XCTAssertEqual(data.count, 100)
        XCTAssertGreaterThan(total ?? 0, 100)
        let h264 = try await client.videoFormats(path: "videos/h264-sample.mp4")
        XCTAssertTrue(h264.codecs.contains("avc1"), "\(h264.codecs)")
        XCTAssertNil(h264.unplayableFormat(av1Hardware: false))
        let av1 = try await client.videoFormats(path: "videos/av1-sample.mp4")
        XCTAssertTrue(av1.codecs.contains("av01"), "\(av1.codecs)")
        XCTAssertEqual(av1.unplayableFormat(av1Hardware: false), "AV1")
    }

    func testKeyedURLWorksWithoutHeader() async throws {
        // What AVPlayer does: no custom header, key in the query, Range requests.
        var r = URLRequest(url: client.keyedURL(path: "videos/h264-sample.mp4"))
        r.setValue("bytes=1000-1999", forHTTPHeaderField: "Range")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: r)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(data.count, 1000)
        // A fresh session (no cookie from the line above) without the key is refused.
        let (_, plain) = try await URLSession(configuration: .ephemeral).data(for: URLRequest(url: client.fileURL(path: "videos/h264-sample.mp4")))
        XCTAssertEqual((plain as? HTTPURLResponse)?.statusCode, 403)
    }

    func testWebAppLinkSetsCookie() async throws {
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: URLRequest(url: client.webAppURL))
        let http = try XCTUnwrap(resp as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue((http.value(forHTTPHeaderField: "Set-Cookie") ?? "").contains("sg_key="))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).lowercased().contains("<html"))
    }

    func testSaveForOfflineResumeDeleteAndCap() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lbr-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = ServerProfile(name: "Test", host: link.host, port: link.port)
        let store = OfflineStore(folder: dir)
        let video = try await client.item("vid-h264")
        let size = try XCTUnwrap(video.bytes)

        // A partial file from an earlier, interrupted save.
        let name = OfflineStore.fileName(server: server.id, itemID: video.id, path: video.path!)
        let (head, _) = try await client.range(path: video.path!, from: 0, count: 300_000)
        try head.write(to: dir.appendingPathComponent(name + ".part"))

        let saved = try await store.save(video, server: server, client: client)
        XCTAssertEqual(saved.bytes, size)
        let onDisk = try Data(contentsOf: await store.fileURL(for: saved))
        let (whole, _) = try await client.range(path: video.path!, from: 0, count: size)
        XCTAssertEqual(onDisk, whole, "resumed file must match the server byte for byte")
        let localReport = try await VideoCodecs.probe(fileURL: await store.fileURL(for: saved))
        XCTAssertTrue(localReport.codecs.contains("avc1"))

        let pdf = try await client.item("water-guide")
        _ = try await store.save(pdf, server: server, client: client)
        let used = await store.usedBytes()
        XCTAssertEqual(used, size + (pdf.bytes ?? 0))
        let saveCount = await store.all().count
        XCTAssertEqual(saveCount, 2)

        // Reload from disk: the index survives a relaunch.
        let reopened = OfflineStore(folder: dir)
        let reopenedCount = await reopened.all().count
        XCTAssertEqual(reopenedCount, 2)

        try await store.delete(saved.id)
        let usedAfter = await store.usedBytes()
        XCTAssertEqual(usedAfter, pdf.bytes ?? 0)
        try await store.deleteAll()
        let usedEnd = await store.usedBytes()
        XCTAssertEqual(usedEnd, 0)

        // Over the cap: refused before anything is downloaded.
        let tiny = OfflineStore(folder: dir.appendingPathComponent("tiny"), cap: 1_000)
        do {
            try await tiny.save(video, server: server, client: client)
            XCTFail("expected the cap to refuse")
        } catch LastbookError.storageCapExceeded(let needed, let available) {
            XCTAssertEqual(needed, size)
            XCTAssertEqual(available, 1_000)
        }
        let tinyUsed = await tiny.usedBytes()
        XCTAssertEqual(tinyUsed, 0)
    }

    func testTextDocuments() async throws {
        let md = try await client.data(path: "documents/notes.md")
        XCTAssertTrue(String(decoding: md, as: UTF8.self).hasPrefix("# Solar notes"))
        let txt = try await client.item("first-aid-txt")
        XCTAssertEqual(txt.itemKind, .text)
        let mdItem = try await client.item("solar-md")
        XCTAssertEqual(mdItem.itemKind, .markdown)
    }
}
