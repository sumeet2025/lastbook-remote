import Foundation

/// Lastbook search snippets are HTML-escaped text with `<mark>…</mark>` around matched words.
public enum Snippet {
    public struct Part: Equatable, Sendable {
        public var text: String
        public var marked: Bool
    }

    public static func parts(_ html: String) -> [Part] {
        var out: [Part] = []
        var rest = Substring(html)
        var marked = false
        while !rest.isEmpty {
            let tag = marked ? "</mark>" : "<mark>"
            if let r = rest.range(of: tag) {
                let t = unescape(String(rest[..<r.lowerBound]))
                if !t.isEmpty { out.append(Part(text: t, marked: marked)) }
                rest = rest[r.upperBound...]
                marked.toggle()
            } else {
                let t = unescape(String(rest))
                if !t.isEmpty { out.append(Part(text: t, marked: marked)) }
                break
            }
        }
        return out
    }

    public static func plain(_ html: String) -> String { parts(html).map(\.text).joined() }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
