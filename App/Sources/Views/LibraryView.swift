import LastbookRemoteKit
import SwiftUI

/// Places inside a library a navigation stack can show.
enum Route: Hashable {
    case shelf(Shelf)
    case collection(String)
    case videoRow(id: String, title: String)
    case item(LibraryItem)
}

/// One open library: Browse, Search, Videos, the host's full Lastbook app, and Downloaded.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: LibrarySession
    @State private var tab: Tab = .browse

    enum Tab: Hashable { case browse, search, videos, web, downloads }

    var body: some View {
        Group {
            switch session.status {
            case .checking:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to \(session.profile.name)…").foregroundStyle(.secondary)
                    Button("Libraries") { model.close() }.padding(.top, 8)
                }
            case .failed(let error):
                ConnectionProblemView(session: session, error: error)
            case .connected:
                tabs
            }
        }
        .task { await session.connect() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack {
                BrowseView()
                    .libraryChrome(session)
            }
            .tabItem { Label("Browse", systemImage: "books.vertical") }
            .tag(Tab.browse)

            NavigationStack {
                SearchView()
                    .libraryChrome(session)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)

            NavigationStack {
                VideosView()
                    .libraryChrome(session)
            }
            .tabItem { Label("Videos", systemImage: "play.rectangle") }
            .tag(Tab.videos)

            NavigationStack {
                HostWebAppView()
                    .libraryChrome(session)
            }
            .tabItem { Label("Lastbook", systemImage: "globe") }
            .tag(Tab.web)

            NavigationStack {
                DownloadsView()
            }
            .tabItem { Label("Downloaded", systemImage: "arrow.down.circle") }
            .tag(Tab.downloads)
        }
        .environmentObject(session)
    }
}

private struct LibraryChrome: ViewModifier {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: LibrarySession

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LibrarySwitcher(current: session.profile)
                }
            }
    }
}

extension View {
    func libraryChrome(_ session: LibrarySession) -> some View {
        modifier(LibraryChrome(session: session))
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .shelf(let shelf): ShelfView(shelf: shelf)
        case .collection(let name): CollectionView(name: name)
        case .videoRow(let id, let title): VideoRowView(rowID: id, title: title)
        case .item(let item): ItemView(item: item)
        }
    }
}

/// Switch between saved libraries, or go back to the list.
struct LibrarySwitcher: View {
    @EnvironmentObject var model: AppModel
    let current: ServerProfile

    var body: some View {
        Menu {
            ForEach(model.servers) { s in
                Button {
                    if s.id != current.id { model.open(s) }
                } label: {
                    if s.id == current.id {
                        Label(s.name, systemImage: "checkmark")
                    } else {
                        Text(s.name)
                    }
                }
            }
            Divider()
            Button { model.close() } label: { Label("All libraries", systemImage: "list.bullet") }
        } label: {
            Label(current.name, systemImage: "desktopcomputer")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Library: \(current.name). Switch library")
    }
}

/// Shown when the host does not answer, refuses the key, or blocks the connection.
struct ConnectionProblemView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: LibrarySession
    let error: LastbookError
    @State private var showDownloads = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: error == .accessDenied ? "lock.slash" : "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(error == .accessDenied ? "Access key not accepted" : "Can't reach \(session.profile.name)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(error.localizedDescription)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if error == .insecureConnectionBlocked {
                    Text("This build allows plain HTTP only to local and Tailscale addresses.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(session.profile.displayAddress)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Try again") { Task { await session.connect() } }
                        .buttonStyle(.borderedProminent)
                    Button("Libraries") { model.close() }
                        .buttonStyle(.bordered)
                }
                Button("Open Downloaded") { showDownloads = true }
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .navigationDestination(isPresented: $showDownloads) { DownloadsView() }
        }
    }
}
