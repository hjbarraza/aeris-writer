import Foundation

/// A document's line ending, and text made to match it. Only new text is ever
/// converted: a file's existing (even mixed) endings stay as they are.
public enum LineEnding {
    /// The first line ending in `text` ("\r\n", "\n" or "\r"); none → "\n".
    public static func of(_ text: String) -> String {
        let ns = text as NSString
        let r = ns.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n"))
        guard r.location != NSNotFound else { return "\n" }
        if ns.character(at: r.location) == 0x0A { return "\n" }
        return r.location + 1 < ns.length && ns.character(at: r.location + 1) == 0x0A ? "\r\n" : "\r"
    }

    /// `s` with every line break (CRLF, LF or lone CR) replaced by `eol`.
    public static func convert(_ s: String, to eol: String) -> String {
        guard s.utf16.contains(where: { $0 == 0x0A || $0 == 0x0D }) else { return s }
        return s.replacingOccurrences(of: "\r\n|\r|\n", with: NSRegularExpression.escapedTemplate(for: eol),
                                      options: .regularExpression)
    }
}
