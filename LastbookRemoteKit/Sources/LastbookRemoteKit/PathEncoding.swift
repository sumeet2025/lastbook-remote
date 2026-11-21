import Foundation

enum PathEncoding {
    /// The characters JavaScript's `encodeURIComponent` leaves alone, as Lastbook's `fileUrl()` uses.
    static let allowed: CharacterSet = {
        var s = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        s.insert(charactersIn: "-_.!~*'()")
        return s
    }()

    static func encode(component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    /// `documents/a b.pdf` → `/documents/a%20b.pdf`
    static func filePath(_ libraryPath: String) -> String {
        "/" + libraryPath.split(separator: "/", omittingEmptySubsequences: false).map { encode(component: String($0)) }.joined(separator: "/")
    }
}
