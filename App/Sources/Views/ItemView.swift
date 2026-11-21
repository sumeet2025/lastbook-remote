import LastbookRemoteKit
import SwiftUI

/// Opens one library item from the host: PDF, video, text, or web page.
struct ItemView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: LibrarySession
    let item: LibraryItem
    @State private var full: LibraryItem?
    @State private var error: Error?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let full {
                viewer(for: full)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try again") { attempt += 1 }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let full, full.path != nil, full.itemKind != .encyclopedia {
                    SaveForOfflineButton(item: full)
                }
            }
        }
        .task(id: attempt) {
            do {
                // Cards from lists can lack the path and size; the catalog record has both.
                let doc = try await session.client.item(item.id)
                var merged = doc
                if merged.hits == nil { merged.hits = item.hits }
                full = merged
                error = nil
            } catch {
                self.error = error
                session.report(error)
            }
        }
    }

    @ViewBuilder
    private func viewer(for item: LibraryItem) -> some View {
        let source = DocumentSource.remote(item: item, server: session.profile.id, client: session.client)
        switch item.itemKind {
        case .pdf:
            PDFDocumentView(source: source, initialPage: item.hits?.compactMap(\.page).first)
        case .video:
            VideoView(source: source)
        case .text, .markdown:
            TextDocumentView(source: source, markdown: item.itemKind == .markdown)
        case .html:
            WebDocumentView(source: source)
        case .encyclopedia:
            ContentUnavailableView("Encyclopedia", systemImage: "books.vertical",
                                   description: Text("Open encyclopedias from the Lastbook tab, which shows the computer's own reader."))
        case .other:
            WebDocumentView(source: source)
        }
    }
}

/// Where a viewer gets its file: from the host (with the key) or from Downloaded (no network).
enum DocumentSource {
    case remote(item: LibraryItem, server: UUID, client: LastbookClient)
    case local(item: LibraryItem, file: URL)

    var item: LibraryItem {
        switch self {
        case .remote(let i, _, _), .local(let i, _): return i
        }
    }

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }

    /// A file on this device: the saved copy, or a temporary viewing copy.
    func localFile() async throws -> URL {
        switch self {
        case .local(_, let url): return url
        case .remote(let item, let server, let client):
            return try await ViewerCache.shared.file(for: item, server: server, client: client)
        }
    }
}

/// Save for offline: shows the size, asks first, then downloads with progress.
struct SaveForOfflineButton: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: LibrarySession
    let item: LibraryItem
    @State private var confirming = false
    @State private var size: Int64?
    @State private var checking = false
    @State private var unplayable: String?

    var body: some View {
        if model.savedItem(server: session.profile.id, item: item.id) != nil {
            Label("Saved", systemImage: "arrow.down.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Saved for offline")
        } else if let p = model.isDownloading(server: session.profile.id, item: item.id) {
            HStack(spacing: 8) {
                ProgressView(value: p.fraction).frame(width: 60)
                Button("Cancel") { model.cancelSave(server: session.profile.id, item: item) }
            }
            .accessibilityLabel("Saving, \(Int(p.fraction * 100)) percent")
        } else {
            Button {
                Task { await prepare() }
            } label: {
                if checking { ProgressView() } else { Label("Save for offline", systemImage: "arrow.down.circle") }
            }
            .disabled(checking)
            .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
                if unplayable == nil {
                    Button("Save \(Format.size(size) ?? "")") { model.startSave(item, in: session) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
        }
    }

    private var title: String { unplayable == nil ? "Save “\(item.title)” on this device?" : "Can't save this video" }

    private var message: String {
        if let f = unplayable {
            return "It is in the \(f) format, which this device can't play, so a saved copy would not play either. Lastbook does not offer an H.264 copy of it yet."
        }
        var s = "It will use \(Format.size(size) ?? "an unknown amount of") storage."
        let left = model.storageCap - model.usedBytes
        s += " \(Format.size(max(0, left)) ?? "Nothing") is left under your offline limit."
        s += " Saved items open without a connection; search, links and Chat still need the computer."
        return s
    }

    private func prepare() async {
        checking = true
        defer { checking = false }
        size = item.bytes
        if size == nil, let path = item.path { size = try? await session.client.contentLength(path: path) }
        unplayable = nil
        if item.itemKind == .video, let path = item.path,
           let report = try? await session.client.videoFormats(path: path) {
            unplayable = report.unplayableFormat(av1Hardware: VideoSupport.hasAV1Decoder)
        }
        confirming = true
    }
}
