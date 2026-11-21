import SwiftUI

/// Plain text and Markdown files, rendered natively with Dynamic Type.
struct TextDocumentView: View {
    let source: DocumentSource
    let markdown: Bool
    @State private var text: AttributedString?
    @State private var error: Error?

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open", systemImage: "doc.plaintext")
                } description: {
                    Text(error.localizedDescription)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let url = try await source.localFile()
                let data = try Data(contentsOf: url)
                let raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                if markdown, let md = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    text = md
                } else {
                    text = AttributedString(raw)
                }
            } catch {
                self.error = error
            }
        }
    }
}
