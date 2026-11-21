import AVFoundation
import SwiftUI

@main
struct LastbookRemoteApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Video keeps playing with the screen locked and in Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                LibraryView(session: session)
                    .id(session.profile.id)
            } else {
                ServerListView()
            }
        }
        .alert(item: $model.alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }
}
