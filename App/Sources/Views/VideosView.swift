import LastbookRemoteKit
import SwiftUI

/// The host's video rows (`/api/videos`).
struct VideosView: View {
    @EnvironmentObject var session: LibrarySession

    var body: some View {
        Loadable(load: { try await session.client.videoRows() }) { rows in
            List {
                Section {
                    NavigationLink(value: Route.videoRow(id: "all", title: "All videos")) {
                        Label("All videos", systemImage: "square.grid.2x2")
                    }
                }
                ForEach(rows.filter { $0.count > 0 }) { row in
                    Section {
                        ForEach(row.items.prefix(4)) { item in
                            NavigationLink(value: Route.item(item)) { ItemRow(item: item) }
                        }
                        if row.count > 4 {
                            NavigationLink(value: Route.videoRow(id: row.id, title: row.title)) {
                                Text("All \(row.count)").foregroundStyle(.tint)
                            }
                        }
                    } header: {
                        Text(row.title)
                    } footer: {
                        if let n = row.note { Text(n) }
                    }
                }
            }
        }
        .navigationTitle("Videos")
    }
}

struct VideoRowView: View {
    @EnvironmentObject var session: LibrarySession
    let rowID: String
    let title: String
    @State private var items: [LibraryItem] = []
    @State private var more = false
    @State private var total = 0
    @State private var loading = false
    @State private var error: Error?

    var body: some View {
        List {
            if total > 0 { Text("\(total) videos").font(.footnote).foregroundStyle(.secondary) }
            ForEach(items) { item in
                NavigationLink(value: Route.item(item)) { ItemRow(item: item) }
            }
            if more { Button("Load more") { Task { await load() } }.disabled(loading) }
            if let error {
                Text(error.localizedDescription).foregroundStyle(.red)
                Button("Try again") { Task { await load() } }
            }
        }
        .overlay { if items.isEmpty && loading { ProgressView() } }
        .navigationTitle(title)
        .task { if items.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let page = try await session.client.videos(row: rowID, offset: items.count)
            items += page.items
            more = page.more
            total = page.total
            error = nil
        } catch {
            self.error = error
            session.report(error)
        }
    }
}
