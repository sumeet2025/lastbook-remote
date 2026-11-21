import LastbookRemoteKit
import SwiftUI
import UIKit

struct ItemRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: LibrarySession
    let item: LibraryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(item: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(3)
                Text(Format.subtitle(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let hit = item.hits?.first, let snippet = hit.snippet, !snippet.isEmpty {
                    Text(Format.snippet(snippet))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if model.savedItem(server: session.profile.id, item: item.id) != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Saved for offline")
            }
        }
        .padding(.vertical, 2)
    }
}

struct Thumbnail: View {
    @EnvironmentObject var session: LibrarySession
    let item: LibraryItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
            if let thumb = item.thumb {
                AuthorizedImage(path: thumb)
            } else {
                Image(systemName: item.itemKind.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: item.itemKind == .video ? 72 : 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// An image from the library, fetched with the access key (AsyncImage cannot add headers).
struct AuthorizedImage: View {
    @EnvironmentObject var session: LibrarySession
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: path) {
            if let data = try? await session.client.data(path: path) {
                image = UIImage(data: data)
            }
        }
    }
}

enum Format {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ n: Int64?) -> String? {
        guard let n, n > 0 else { return nil }
        return bytes.string(fromByteCount: n)
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let s = seconds, s > 0 else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = s >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        f.zeroFormattingBehavior = .pad
        return f.string(from: s)
    }

    static func subtitle(_ item: LibraryItem) -> String {
        var parts: [String] = []
        if let k = item.kindLabel { parts.append(k) } else if item.itemKind == .video { parts.append("Video") }
        if let p = item.publisher, !p.isEmpty { parts.append(p) }
        if let pages = item.pages, pages > 0 { parts.append("\(pages) pages") }
        if let d = duration(item.duration) { parts.append(d) }
        if let y = item.year { parts.append(y) }
        return parts.joined(separator: " · ")
    }

    /// A search snippet with the matched words in bold.
    static func snippet(_ html: String) -> AttributedString {
        var out = AttributedString()
        for part in Snippet.parts(html) {
            var a = AttributedString(part.text)
            if part.marked { a.inlinePresentationIntent = .stronglyEmphasized }
            out += a
        }
        return out
    }
}
