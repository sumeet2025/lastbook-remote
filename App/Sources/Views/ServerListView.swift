import LastbookRemoteKit
import SwiftUI

/// The first screen: saved libraries, Downloaded, and Settings.
struct ServerListView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false
    @State private var editing: ServerProfile?

    var body: some View {
        NavigationStack {
            List {
                if model.servers.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect to a Lastbook library")
                                .font(.headline)
                            Text("On the computer that holds the library, open Lastbook → Library and local AI → Share this library with my devices, and copy the access link. Or run python3 server.py --lan and copy the link it prints.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Add a library") { adding = true }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section("Libraries") {
                        ForEach(model.servers) { server in
                            Button {
                                model.open(server)
                            } label: {
                                ServerRow(server: server)
                            }
                            .swipeActions {
                                Button(role: .destructive) { model.remove(server) } label: { Label("Remove", systemImage: "trash") }
                                Button { editing = server } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                            .contextMenu {
                                Button { editing = server } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { model.remove(server) } label: { Label("Remove", systemImage: "trash") }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label {
                            HStack {
                                Text("Downloaded")
                                Spacer()
                                if !model.saved.isEmpty {
                                    Text("\(model.saved.count)").foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } footer: {
                    Text("Downloaded items open without a connection. Search, encyclopedias, maps and Chat need the host computer.")
                }
            }
            .navigationTitle("Lastbook Remote")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("Add library", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $adding) {
                AddServerView(existing: nil)
            }
            .sheet(item: $editing) { server in
                AddServerView(existing: server)
            }
        }
    }
}

struct ServerRow: View {
    let server: ServerProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: server.hostKind == .tailscale ? "network.badge.shield.half.filled" : "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.body).foregroundStyle(.primary)
                Text(server.displayAddress + (server.hostKind == .tailscale ? " · Tailscale" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this library")
    }
}
