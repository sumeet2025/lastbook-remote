import AVFoundation
import AVKit
import LastbookRemoteKit
import SwiftUI
import UIKit
import VideoToolbox

enum VideoSupport {
    /// True on devices with a hardware AV1 decoder (A17 Pro, M3 and later).
    static let hasAV1Decoder: Bool = VTIsHardwareDecodeSupported(CMVideoCodecType(0x6176_3031)) // 'av01'
}

/// Plays a library video with AVPlayer: streamed from the host with Range requests, or from
/// Downloaded. Picture in Picture, AirPlay and background audio come from AVPlayerViewController.
struct VideoView: View {
    let source: DocumentSource
    @State private var player: AVPlayer?
    @State private var problem: String?
    @State private var checking = true
    @State private var statusObservation: NSKeyValueObservation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Color.black
                    if let problem {
                        VStack(spacing: 10) {
                            Image(systemName: "film.stack").font(.largeTitle)
                            Text(problem).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .padding()
                    } else if let player {
                        PlayerController(player: player)
                    } else if checking {
                        ProgressView().tint(.white)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(source.item.title).font(.title3.bold())
                Text(Format.subtitle(source.item)).font(.subheadline).foregroundStyle(.secondary)
                if let notes = source.item.notes { Text(notes).font(.body) }
                if source.isLocal {
                    Label("Playing the copy saved on this device.", systemImage: "arrow.down.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .task { await prepare() }
        .onDisappear {
            player?.pause()
            statusObservation = nil
        }
    }

    private func prepare() async {
        checking = true
        defer { checking = false }
        let item = source.item
        guard let path = item.path else {
            problem = "This video has no file."
            return
        }
        let url: URL
        let report: VideoFormatReport?
        switch source {
        case .local(_, let file):
            url = file
            report = try? await VideoCodecs.probe(fileURL: file)
        case .remote(_, _, let client):
            // AVPlayer cannot add a header to its range requests, and an AirPlay receiver fetches the
            // URL itself, so the key goes in the query (the listener accepts it there and strips it).
            url = client.keyedURL(path: path)
            do {
                report = try await client.videoFormats(path: path)
            } catch let e as LastbookError where e == .accessDenied || e.isConnectivity {
                problem = e.localizedDescription
                return
            } catch {
                report = nil  // not an MP4 we can read; let AVPlayer try
            }
        }
        if let f = report?.unplayableFormat(av1Hardware: VideoSupport.hasAV1Decoder) {
            if f == "WebM" || f == "Matroska (MKV)" {
                problem = "This video is a \(f) file, which iOS can't play. Play it on the computer instead."
            } else {
                problem = "This video is in the \(f) format, which this \(UIDevice.current.model) can't play. "
                    + "Lastbook doesn't offer an H.264 copy of it yet. Play it on the computer, or on a device with an AV1 hardware decoder (iPhone 15 Pro or later, recent M-series iPads)."
            }
            return
        }
        let playerItem = AVPlayerItem(url: url)
        statusObservation = playerItem.observe(\.status, options: [.new]) { obj, _ in
            if obj.status == .failed {
                let reason = obj.error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    problem = "This video couldn't be played here (\(reason))."
                    player = nil
                }
            }
        }
        let p = AVPlayer(playerItem: playerItem)
        p.allowsExternalPlayback = true
        player = p
    }
}

struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
