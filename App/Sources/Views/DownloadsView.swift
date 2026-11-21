import LastbookRemoteKit
import SwiftUI

/// Everything saved for offline, from every library. Opens with no network.
struct DownloadsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(max(0, model.usedBytes)), total: Double(max(1, model.storageCap)))
                    Text("\(Format.size(model.usedBytes) ?? "Nothing") used of \(Format.size(model.storageCap) ?? "0") offline limit")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } footer: {
                Text("Only items you saved are on this device; the library stays on the computer. Search, encyclopedia links, maps and Chat need the computer.")
            }

            if model.saved.isEmpty {
                Section {
                    Text("Nothing saved yet. Open a document or video and tap Save for offline.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groups) { group in
                    let items = group.items
                    Section(group.name) {
                        ForEach(items) { saved in
                            NavigationLink {
                                OfflineItemView(saved: saved)
                            } label: {
                                SavedRow(saved: saved)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { model.delete(items[i]) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloaded")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !model.saved.isEmpty {
                    Button(role: .destructive) { confirmDeleteAll = true } label: { Text("Delete all") }
                }
            }
        }
        .confirmationDialog("Delete everything saved for offline?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all \(model.saved.count) items", role: .destructive) { model.deleteAllSaved() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(Format.size(model.usedBytes) ?? "the space"). The items stay in the library on the computer.")
        }
        .task { await model.refreshSaved() }
    }

    /// Saved items grouped by the library they came from.
    private var groups: [SavedGroup] {
        let byServer = Dictionary(grouping: model.saved, by: { $0.serverName })
        return byServer.keys.sorted().map { SavedGroup(name: $0, items: byServer[$0] ?? []) }
    }
}

struct SavedGroup: Identifiable {
    let name: String
    let items: [SavedItem]
    var id: String { name }
}

struct SavedRow: View {
    let saved: SavedItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: saved.kind.systemImage)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.item.title).lineLimit(2)
                Text([Format.size(saved.bytes), saved.savedAt.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A saved item, opened from the file on this device.
struct OfflineItemView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let saved: SavedItem
    @State private var confirmDelete = false

    var body: some View {
        let source = DocumentSource.local(item: saved.item, file: model.localURL(for: saved))
        Group {
            switch saved.kind {
            case .pdf: PDFDocumentView(source: source)
            case .video: VideoView(source: source)
            case .text, .markdown: TextDocumentView(source: source, markdown: saved.kind == .markdown)
            case .html, .other, .encyclopedia: WebDocumentView(source: source)
            }
        }
        .navigationTitle(saved.item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .confirmationDialog("Delete this saved copy?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(Format.size(saved.bytes) ?? "")", role: .destructive) {
                model.delete(saved)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
