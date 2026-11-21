import LastbookRemoteKit
import SwiftUI

/// Full-text search on the host (`/api/find`).
struct SearchView: View {
    @EnvironmentObject var session: LibrarySession
    @State private var query = ""
    @State private var kind = "all"
    @State private var results: SearchResults?
    @State private var searching = false
    @State private var error: Error?

    var body: some View {
        List {
            Picker("Kind", selection: $kind) {
                Text("Everything").tag("all")
                Text("To read").tag("read")
                Text("Videos").tag("video")
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if let error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if let r = results {
                if r.results.isEmpty {
                    Text("Nothing in this library matches “\(r.q ?? query)”.").foregroundStyle(.secondary)
                } else {
                    if r.mode == "some words" {
                        Text("No page has every word; showing pages with some of them.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(r.results) { item in
                        NavigationLink(value: Route.item(item)) { ItemRow(item: item) }
                    }
                }
            } else if !searching {
                Text("Search every manual, page and video transcript in this library. Search needs the host computer; it does not work offline.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .overlay { if searching { ProgressView() } }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "boil water, generator, splint…")
        .onSubmit(of: .search) { Task { await run() } }
        .onChange(of: kind) { _, _ in if results != nil { Task { await run() } } }
        .navigationTitle("Search")
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        do {
            results = try await session.client.search(q, kind: kind)
            error = nil
        } catch {
            self.error = error
            session.report(error)
        }
    }
}
