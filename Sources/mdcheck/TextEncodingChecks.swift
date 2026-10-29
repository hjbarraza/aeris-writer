import Foundation
import MarkdownCore

// Mirrored in Tests/MarkdownCoreTests/TextEncodingTests.swift.
func runTextEncodingChecks() {
    func bytes(_ b: [UInt8]) -> Data { Data(b) }
    func roundTrips(_ data: Data, _ want: TextEncoding, _ text: String, _ label: String) {
        let got = TextEncoding.decode(data)
        check(got?.encoding == want && got?.text == text, "encoding: \(label) decodes as \(want)")
        check(got.flatMap { $0.encoding.encode($0.text) } == data, "encoding: \(label) re-encodes to the same bytes")
    }

    roundTrips(Data(), .utf8, "", "empty file")
    roundTrips(Data("# Café 👋\r\nx\n".utf8), .utf8, "# Café 👋\r\nx\n", "UTF-8")
    roundTrips(bytes([0xEF, 0xBB, 0xBF]) + Data("# Café".utf8), .utf8BOM, "# Café", "UTF-8 with BOM")
    roundTrips(bytes([0xFF, 0xFE]) + "# Café 👋\n".data(using: .utf16LittleEndian)!, .utf16LE, "# Café 👋\n", "UTF-16 LE BOM")
    roundTrips(bytes([0xFE, 0xFF]) + "# Café 👋\n".data(using: .utf16BigEndian)!, .utf16BE, "# Café 👋\n", "UTF-16 BE BOM")
    // "Café “ok” – naïve" in Windows-1252: é E9, “ 93, ” 94, – 96, ï EF.
    let w1252 = Data("Caf".utf8) + bytes([0xE9, 0x20, 0x93]) + Data("ok".utf8) + bytes([0x94, 0x20, 0x96, 0x20])
        + Data("na".utf8) + bytes([0xEF]) + Data("ve".utf8)
    roundTrips(w1252, .windows1252, "Café “ok” – naïve", "Windows-1252 with accents")
    roundTrips(bytes([0x4E, 0x6F, 0xEB, 0x6C]), .windows1252, "Noël", "Latin-1 with accents")
    // Valid UTF-8 wins over a 1252 reading of the same bytes ("Ã©").
    roundTrips(Data("é".utf8), .utf8, "é", "ambiguous bytes")
    // No BOM, so never UTF-16: BOM-less UTF-16 decodes with NULs, and text with U+0000 is refused.
    check(TextEncoding.decode("ab".data(using: .utf16LittleEndian)!) == nil, "encoding: BOM-less UTF-16 is refused")
    check(TextEncoding.decode(Data("a\0b".utf8)) == nil, "encoding: text containing U+0000 is refused")
    check(TextEncoding.decode(bytes([0xFF, 0xFE]) + "a\0".data(using: .utf16LittleEndian)!) == nil,
          "encoding: U+0000 is refused in UTF-16 too")
    // A lone surrogate (possible in an NSString) is never written, not even as U+FFFD.
    let lone = NSString(characters: [0x61, 0xD800], length: 2) as String
    for e in [TextEncoding.utf8, .utf8BOM, .utf16LE, .utf16BE, .windows1252] {
        check(e.encode(lone) == nil, "encoding: an unpaired surrogate can't be written as \(e)")
    }
    check(TextEncoding.windows1252.displayName == "Western (Windows Latin 1)" && TextEncoding.utf8.displayName == "UTF-8",
          "encoding: display names")

    check(TextEncoding.windows1252.encode("Café 👋") == nil, "encoding: an emoji can't be written as Windows-1252")
    check(TextEncoding.windows1252.encode("Café") == bytes([0x43, 0x61, 0x66, 0xE9]),
          "encoding: Windows-1252 writes é as one byte")
    check(TextEncoding.utf8.encode("a") == Data("a".utf8), "encoding: UTF-8 without BOM gains no BOM")
}
