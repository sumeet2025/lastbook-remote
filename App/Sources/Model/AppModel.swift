import Foundation
import LastbookRemoteKit
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// A download in progress.
struct DownloadProgress: Equatable {
    var done: Int64
    var total: Int64
    var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
}

/// App-wide state: saved libraries, the open library, and things saved for offline.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var servers: [ServerProfile] = []
    @Published var session: LibrarySession?
    @Published private(set) var saved: [SavedItem] = []
    @Published private(set) var usedBytes: Int64 = 0
    @Published private(set) var downloads: [String: DownloadProgress] = [:]
    @Published var alert: AppAlert?
    @Published var storageCap: Int64 {
        didSet {
            UserDefaults.standard.set(storageCap, forKey: Self.capKey)
            let cap = storageCap
            Task { await offline.setCap(cap); await refreshSaved() }
        }
    }

    let serverStore: ServerStore
    let offline: OfflineStore
    let urlCache: URLCache
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    static let capKey = "offlineStorageCap"
    static let lastServerKey = "lastServerID"

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        serverStore = ServerStore(fileURL: support.appendingPathComponent("servers.json"), keys: KeychainKeyStore())
        let cap = (UserDefaults.standard.object(forKey: Self.capKey) as? NSNumber)?.int64Value ?? OfflineStore.defaultCap
        storageCap = cap
        offline = OfflineStore(folder: support.appendingPathComponent("Offline", isDirectory: true), cap: cap)
        urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024,
                            directory: caches.appendingPathComponent("HTTP", isDirectory: true))
        servers = serverStore.load()
        Task { await refreshSaved() }
        if let last = UserDefaults.standard.string(forKey: Self.lastServerKey),
           let p = servers.first(where: { $0.id.uuidString == last }) {
            open(p)
        }
    }

    // MARK: Libraries

    func key(for profile: ServerProfile) -> String? { serverStore.keys.key(for: profile.id) }

    func addOrUpdate(_ profile: ServerProfile, key: String) {
        do {
            servers = try serverStore.upsert(profile, key: key)
        } catch {
            alert = AppAlert(title: "Couldn't save this library", message: error.localizedDescription)
        }
    }

    func remove(_ profile: ServerProfile) {
        if session?.profile.id == profile.id { close() }
        do {
            servers = try serverStore.remove(profile.id)
        } catch {
            alert = AppAlert(title: "Couldn't remove this library", message: error.localizedDescription)
        }
    }

    func open(_ profile: ServerProfile) {
        guard let key = key(for: profile),
              let client = LastbookClient(profile: profile, key: key, session: LastbookClient.makeSession(cache: urlCache)) else {
            alert = AppAlert(title: "Access key missing", message: "Edit this library and paste its access link again.")
            return
        }
        session = LibrarySession(profile: profile, client: client)
        UserDefaults.standard.set(profile.id.uuidString, forKey: Self.lastServerKey)
    }

    func close() {
        session = nil
        UserDefaults.standard.removeObject(forKey: Self.lastServerKey)
    }

    // MARK: Save for offline

    func refreshSaved() async {
        saved = await offline.all()
        usedBytes = await offline.usedBytes()
    }

    func savedItem(server: UUID, item: String) -> SavedItem? {
        saved.first { $0.id == SavedItem.makeID(server: server, item: item) }
    }

    func isDownloading(server: UUID, item: String) -> DownloadProgress? {
        downloads[SavedItem.makeID(server: server, item: item)]
    }

    func startSave(_ item: LibraryItem, in session: LibrarySession) {
        let id = SavedItem.makeID(server: session.profile.id, item: item.id)
        guard downloadTasks[id] == nil else { return }
        downloads[id] = DownloadProgress(done: 0, total: item.bytes ?? 0)
        let store = offline
        let profile = session.profile
        let client = session.client
        downloadTasks[id] = Task { [weak self] in
            do {
                try await store.save(item, server: profile, client: client) { done, total in
                    Task { @MainActor in self?.downloads[id] = DownloadProgress(done: done, total: total) }
                }
            } catch LastbookError.cancelled {
                // Kept as a partial file; saving again resumes it.
            } catch is CancellationError {
            } catch {
                self?.alert = AppAlert(title: "Not saved", message: error.localizedDescription)
            }
            self?.downloads[id] = nil
            self?.downloadTasks[id] = nil
            await self?.refreshSaved()
        }
    }

    func cancelSave(server: UUID, item: LibraryItem) {
        let id = SavedItem.makeID(server: server, item: item.id)
        downloadTasks[id]?.cancel()
        downloadTasks[id] = nil
        downloads[id] = nil
        let store = offline
        Task {
            await store.discardPartial(server: server, item: item)
            await refreshSaved()
        }
    }

    func delete(_ item: SavedItem) {
        Task {
            do { try await offline.delete(item.id) } catch {
                alert = AppAlert(title: "Couldn't delete", message: error.localizedDescription)
            }
            await refreshSaved()
        }
    }

    func deleteAllSaved() {
        Task {
            do { try await offline.deleteAll() } catch {
                alert = AppAlert(title: "Couldn't delete", message: error.localizedDescription)
            }
            await refreshSaved()
        }
    }

    func localURL(for item: SavedItem) -> URL {
        offline.folder.appendingPathComponent(item.fileName)
    }

    // MARK: Cache

    func clearCache() {
        urlCache.removeAllCachedResponses()
        ViewerCache.shared.clear()
        WebViewSupport.clearCaches()
    }
}
