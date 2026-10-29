import Foundation

/// The file name a new draft takes from its first line (M2-8): the line's text with heading,
/// list and quote markers and inline Markdown removed (as `Excerpt` does), `/` and `:` replaced
/// by `-`, zero-width and bidi control characters removed, leading dots dropped (no hidden files),
/// trimmed, and capped at 60 characters on a word boundary and at `maxBytes` UTF-8 bytes.
/// Nothing left gives "Untitled".
public enum DraftName {
    public static let maxLength = 60
    /// File names hold 255 UTF-8 bytes; this leaves room for " 2" … and the extension.
    public static let maxBytes = 240
    /// Invisible characters that hide or visually reorder a name (ZWJ stays: emoji need it).
    private static let invisible: Set<Unicode.Scalar> = Set(
        [0x061C, 0x200B, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2060,
         0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF].compactMap(Unicode.Scalar.init))

    public static func make(_ text: String) -> String {
        let firstLine = text.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: \.isNewline).first ?? ""
        var name = Excerpt.make(String(firstLine), limit: .max)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        name.unicodeScalars.removeAll { invisible.contains($0) }
        name = String(name.drop { $0 == "." || $0.isWhitespace })
        if name.count > maxLength {
            // A space right after the 60th character still ends a whole word.
            let head = name.prefix(maxLength + 1)
            if let space = head.lastIndex(where: \.isWhitespace), space > head.startIndex {
                name = String(head[..<space])
            } else {
                name = String(name.prefix(maxLength))
            }
        }
        while name.utf8.count > maxBytes { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }

    /// `base.ext`, or the first of `base 2.ext`, `base 3.ext`, … that `exists` says is free.
    public static func unique(_ base: String, ext: String, exists: (String) -> Bool) -> String {
        var candidate = "\(base).\(ext)"
        var n = 2
        while exists(candidate) {
            candidate = "\(base) \(n).\(ext)"
            n += 1
        }
        return candidate
    }
}
