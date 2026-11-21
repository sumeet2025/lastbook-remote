import LastbookRemoteKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var cleared = false

    private let caps: [Int64] = [100 * 1024 * 1024, 500 * 1024 * 1024] + [1, 2, 5, 10, 20, 50, 100].map { Int64($0) * 1024 * 1024 * 1024 }

    var body: some View {
        Form {
            Section {
                Picker("Offline storage limit", selection: $model.storageCap) {
                    ForEach(caps, id: \.self) { c in
                        Text(Format.size(c) ?? "").tag(c)
                    }
                }
                LabeledContent("Used", value: Format.size(model.usedBytes) ?? "Nothing")
            } header: {
                Text("Save for offline")
            } footer: {
                Text("A save that would go over the limit is refused. Lowering the limit does not delete anything already saved.")
            }

            Section {
                Button("Clear cache") {
                    model.clearCache()
                    cleared = true
                }
                if cleared {
                    Label("Cache cleared", systemImage: "checkmark").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Removes temporary copies of documents you viewed, thumbnails and web pages. Saved items are kept.")
            }

            Section("Privacy") {
                Text("This app talks only to the Lastbook computers you add. It has no analytics, accounts or third-party services. Access keys are kept in the Keychain on this device only.")
                    .font(.footnote)
            }

            Section {
                Text("• Pairing codes and QR codes instead of a shared access link\n• Finding computers automatically (Bonjour)\n• HTTPS with a pinned certificate\n• Computer names, including Tailscale MagicDNS\n• H.264 copies of AV1 and VP9 videos")
                    .font(.footnote)
            } header: {
                Text("When Lastbook supports it")
            } footer: {
                Text("These need changes in Lastbook first. Today the app uses the access link from Share this library with my devices, or server.py --lan.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("Lastbook Remote on GitHub", destination: URL(string: "https://github.com/sumeet2025/lastbook-remote")!)
                Link("Lastbook", destination: URL(string: "https://lastbook.org")!)
            }
        }
        .navigationTitle("Settings")
    }
}
