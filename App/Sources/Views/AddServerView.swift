import LastbookRemoteKit
import SwiftUI
import UIKit

/// Add or edit a library: paste the access link, or type the address, port and key.
struct AddServerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: ServerProfile?

    @State private var link = ""
    @State private var name = ""
    @State private var host = ""
    @State private var port = "8890"
    @State private var key = ""
    @State private var testing = false
    @State private var result: TestResult?

    enum TestResult: Equatable {
        case ok(String)
        case failed(String)
    }

    init(existing: ServerProfile?) {
        self.existing = existing
    }

    private var hostKind: HostKind { HostAddress.classify(host) }
    private var portNumber: Int? { Int(port).flatMap { (1...65535).contains($0) ? $0 : nil } }
    private var canSave: Bool {
        HostAddress.isAllowed(hostKind) && portNumber != nil && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.20:8890/?key=…", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: link) { _, new in apply(new) }
                    Button {
                        if let s = UIPasteboard.general.string { link = s }
                    } label: {
                        Label("Paste access link", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("Access link")
                } footer: {
                    Text("Copy it from Lastbook on the computer (Library and local AI → Share this library with my devices), or from the line python3 server.py --lan prints.")
                }

                Section {
                    TextField("Name", text: $name, prompt: Text("Studio Mac"))
                    TextField("IP address", text: $host, prompt: Text("192.168.1.20 or 100.x.y.z"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    SecureField("Access key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Or enter it by hand")
                } footer: {
                    if !host.isEmpty {
                        Label(HostAddress.advice(for: hostKind), systemImage: HostAddress.isAllowed(hostKind) ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(HostAddress.isAllowed(hostKind) ? Color.secondary : Color.orange)
                    } else {
                        Text("Away from home, turn on Tailscale on both devices and use the computer's Tailscale IP (100.x.y.z). Lastbook accepts only IP addresses today, not names. Never forward the port to the internet.")
                    }
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!canSave || testing)
                    if let result {
                        switch result {
                        case .ok(let s): Label(s, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed(let s): Label(s, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add library" : "Edit library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let e = existing, host.isEmpty else { return }
        name = e.name
        host = e.host
        port = String(e.port)
        key = model.key(for: e) ?? ""
    }

    private func apply(_ text: String) {
        guard let l = AccessLink.parse(text) else { return }
        host = l.host
        port = String(l.port)
        key = l.key
        if name.isEmpty { name = "Lastbook on \(l.host)" }
        result = nil
    }

    private func profile() -> ServerProfile? {
        guard let p = portNumber else { return nil }
        let n = name.trimmingCharacters(in: .whitespaces)
        return ServerProfile(id: existing?.id ?? UUID(), name: n.isEmpty ? "Lastbook on \(host)" : n,
                             host: host, port: p, addedAt: existing?.addedAt ?? Date())
    }

    private func test() async {
        guard let p = profile(), let client = LastbookClient(profile: p, key: key.trimmingCharacters(in: .whitespaces),
                                                             session: LastbookClient.makeSession()) else { return }
        testing = true
        defer { testing = false }
        do {
            let s = try await client.testConnection()
            var parts: [String] = []
            if let r = s.resources { parts.append("\(r) items") }
            if let v = s.videos { parts.append("\(v) videos") }
            if let z = s.zims, !z.isEmpty { parts.append("\(z.count) encyclopedias") }
            result = .ok("Connected" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")))
        } catch {
            result = .failed(error.localizedDescription)
        }
    }

    private func save() {
        guard let p = profile() else { return }
        model.addOrUpdate(p, key: key.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}
