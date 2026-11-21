import PDFKit
import SwiftUI

/// A PDF in PDFKit: fetched once to a viewing copy (or opened from Downloaded), then native
/// scrolling, zoom, search-in-document and page thumbnails.
struct PDFDocumentView: View {
    let source: DocumentSource
    var initialPage: Int?
    @State private var document: PDFDocument?
    @State private var error: Error?

    var body: some View {
        Group {
            if let document {
                PDFKitView(document: document, initialPage: initialPage)
                    .ignoresSafeArea(edges: .bottom)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open the PDF", systemImage: "doc.richtext")
                } description: {
                    Text(error.localizedDescription)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    if let size = Format.size(source.item.bytes) {
                        Text("Loading \(size)…").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            do {
                let url = try await source.localFile()
                guard let doc = PDFDocument(url: url) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                document = doc
            } catch {
                self.error = error
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    var initialPage: Int?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.document = document
        if let n = initialPage, n > 0, let page = document.page(at: n - 1) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
