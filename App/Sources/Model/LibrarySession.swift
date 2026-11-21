import Foundation
import LastbookRemoteKit

/// The open library: its address, client, and whether the host is answering.
@MainActor
final class LibrarySession: ObservableObject {
    enum Status: Equatable {
        case checking
        case connected(LibrarySummary)
        case failed(LastbookError)
    }

    let profile: ServerProfile
    let client: LastbookClient
    @Published private(set) var status: Status = .checking
    @Published private(set) var chatAvailable = false

    init(profile: ServerProfile, client: LastbookClient) {
        self.profile = profile
        self.client = client
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    func connect() async {
        status = .checking
        do {
            let summary = try await client.testConnection()
            status = .connected(summary)
            chatAvailable = (try? await client.assistantStatus())?.shared ?? false
        } catch let e as LastbookError {
            status = .failed(e)
        } catch {
            status = .failed(.unreachable(error.localizedDescription))
        }
    }

    /// Call when a request fails, so a host that went to sleep shows the reconnect screen.
    func report(_ error: Error) {
        if let e = error as? LastbookError, e.isConnectivity || e == .accessDenied {
            status = .failed(e)
        }
    }
}
