import Foundation

/// The byte encoding of a text file, detected on open and reused on save so a file
/// is never silently re-encoded.
///
/// Detection order: a BOM decides (UTF-8, UTF-16 LE/BE); otherwise strict UTF-8;
/// otherwise Windows-1252 (a superset of Latin-1's printable range). UTF-16 is never
/// guessed without a BOM. A decode is accepted only if encoding the text again gives
/// back the exact same bytes, so an unedited file always saves byte for byte.
public enum TextEncoding: Equatable, Sendable {
    case utf8, utf8BOM, utf16LE, utf16BE, windows1252

    /// The name shown to the user, e.g. in a save error.
    public var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf8BOM: "UTF-8 with BOM"
        case .utf16LE: "UTF-16 Little Endian"
        case .utf16BE: "UTF-16 Big Endian"
        case .windows1252: "Western (Windows Latin 1)"
        }
    }

    private static let utf8Mark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEMark: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEMark: [UInt8] = [0xFE, 0xFF]

    /// The text and its encoding, or nil when the bytes are none of the supported encodings.
    public static func decode(_ data: Data) -> (text: String, encoding: TextEncoding)? {
        let candidates: [TextEncoding] =
            data.starts(with: utf8Mark) ? [.utf8BOM]
            : data.starts(with: utf16LEMark) ? [.utf16LE]
            : data.starts(with: utf16BEMark) ? [.utf16BE]
            : [.utf8, .windows1252]
        for encoding in candidates {
            if let text = encoding.decodeBody(data), encoding.encode(text) == data {
                // U+0000 means binary or BOM-less UTF-16, not text: refuse rather than guess.
                return text.utf16.contains(0) ? nil : (text, encoding)
            }
        }
        return nil
    }

    /// The file's bytes for `text`, BOM included, or nil when the encoding can't
    /// represent every character (e.g. an emoji in Windows-1252) or the text holds an
    /// unpaired surrogate (possible in an NSString), which is never written as U+FFFD.
    public func encode(_ text: String) -> Data? {
        if Self.hasUnpairedSurrogate(text) { return nil }
        return switch self {
        case .utf8: Data(text.utf8)
        case .utf8BOM: Data(Self.utf8Mark) + Data(text.utf8)
        case .utf16LE: text.data(using: .utf16LittleEndian).map { Data(Self.utf16LEMark) + $0 }
        case .utf16BE: text.data(using: .utf16BigEndian).map { Data(Self.utf16BEMark) + $0 }
        case .windows1252: text.data(using: .windowsCP1252, allowLossyConversion: false)
        }
    }

    private static func hasUnpairedSurrogate(_ text: String) -> Bool {
        // `String.utf16` repairs a bridged NSString's lone surrogates to U+FFFD, so read
        // the NSString's own code units.
        let ns = text as NSString
        var units = [unichar](repeating: 0, count: ns.length)
        ns.getCharacters(&units, range: NSRange(location: 0, length: ns.length))
        var expectLow = false
        for unit in units {
            if UTF16.isTrailSurrogate(unit) {
                if !expectLow { return true }
                expectLow = false
            } else {
                if expectLow { return true }
                expectLow = UTF16.isLeadSurrogate(unit)
            }
        }
        return expectLow
    }

    private func decodeBody(_ data: Data) -> String? {
        switch self {
        // Lossy decode; `decode` rejects it unless it round-trips, which makes it strict.
        case .utf8: String(decoding: data, as: UTF8.self)
        case .utf8BOM: String(decoding: data.dropFirst(3), as: UTF8.self)
        case .utf16LE: String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        case .utf16BE: String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        case .windows1252: String(data: data, encoding: .windowsCP1252)
        }
    }
}
