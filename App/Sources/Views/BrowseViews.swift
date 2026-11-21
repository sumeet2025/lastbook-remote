import LastbookRemoteKit
import SwiftUI

/// Loading, error, and retry around one async request.
struct Loadable<Value, Content: View>: View {
    @EnvironmentObject var session: LibrarySession
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content
    @State private var value: Value?
    @State private var error: Error?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try again") { attempt += 1 }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: attempt) {
            error = nil
            do {
                value = try await load()
            } catch is CancellationError {
            } catch LastbookError.cancelled {
            } catch {
                self.error = error
                session.report(error)
            }
        }
    }
}

/// The library's subject shelves.
struct BrowseView: View {
    @EnvironmentObject var session: LibrarySession

    var body: some View {
        Loadable(load: { try await session.client.shelves() }) { shelves in
            List {
                if case .connected(let s) = session.status {
                    Section {
                        LibrarySummaryRow(summary: s)
                    }
                }
                Section("Shelves") {
                    ForEach(shelves.filter { $0.total > 0 }) { shelf in
                        NavigationLink(value: Route.shelf(shelf)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shelf.title)
                                Text(shelfCounts(shelf)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Encyclopedias, maps, guides and Chat are in the Lastbook tab, which shows the computer's own Lastbook app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .refreshable { await session.connect() }
        }
        .navigationTitle(session.profile.name)
    }

    private func shelfCounts(_ s: Shelf) -> String {
        var p: [String] = []
        if s.read > 0 { p.append("\(s.read) to read") }
        if s.video > 0 { p.append("\(s.video) videos") }
        return p.joined(separator: " · ")
    }
}

struct LibrarySummaryRow: View {
    let summary: LibrarySummary

    var body: some View {
        HStack(spacing: 16) {
            stat(summary.resources, "items")
            stat(summary.pdfs, "PDFs")
            stat(summary.videos, "videos")
            stat(summary.zims?.count, "encyclopedias")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func stat(_ n: Int?, _ label: String) -> some View {
        if let n, n > 0 {
            VStack(alignment: .leading) {
                Text("\(n)").font(.headline)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Collections on one shelf, each with its first few items.
struct ShelfView: View {
    @EnvironmentObject var session: LibrarySession
    let shelf: Shelf
    @State private var kind = "all"

    var body: some View {
        Loadable(load: { try await session.client.shelf(shelf.id, kind: kind) }) { page in
            List {
                ForEach(page.collections) { c in
                    Section {
                        ForEach(c.items) { item in
                            NavigationLink(value: Route.item(item)) { ItemRow(item: item) }
                        }
                        if c.count > c.items.count {
                            NavigationLink(value: Route.collection(c.collection)) {
                                Text("All \(c.count) in \(c.collection)").foregroundStyle(.tint)
                            }
                        }
                    } header: {
                        NavigationLink(value: Route.collection(c.collection)) {
                            HStack {
                                Text(c.collection)
                                Spacer()
                                Text("\(c.count)")
                            }
                        }
                        .accessibilityHint("Shows the whole collection")
                    } footer: {
                        if let t = c.trust { Text(t) }
                    }
                }
                if page.more {
                    Text("More collections are on this shelf; use Search or the Lastbook tab to find them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .id(kind)
        .navigationTitle(shelf.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Show", selection: $kind) {
                    Text("All").tag("all")
                    Text("To read").tag("read")
                    Text("Videos").tag("video")
                }
                .pickerStyle(.menu)
            }
        }
    }
}

/// Every item in one collection: a course, a manual's chapters, a channel. Pages of 60.
struct CollectionView: View {
    @EnvironmentObject var session: LibrarySession
    let name: String
    @State private var items: [LibraryItem] = []
    @State private var total = 0
    @State private var more = false
    @State private var loading = false
    @State private var error: Error?

    var body: some View {
        List {
            if total > 0 {
                Text("\(total) items").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                NavigationLink(value: Route.item(item)) { ItemRow(item: item) }
            }
            if more {
                Button("Load more") { Task { await load() } }.disabled(loading)
            }
            if let error {
                Text(error.localizedDescription).foregroundStyle(.red)
                Button("Try again") { Task { await load() } }
            }
        }
        .overlay { if items.isEmpty && loading { ProgressView() } }
        .navigationTitle(name)
        .task { if items.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let page = try await session.client.collection(name, offset: items.count)
            items += page.items
            total = page.total
            more = page.more
            error = nil
        } catch {
            self.error = error
            session.report(error)
        }
    }
}
