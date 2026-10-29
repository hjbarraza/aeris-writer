import Foundation
import Testing
@testable import MarkdownCore

// Mirrored in Sources/mdcheck/TextEncodingChecks.swift.
struct TextEncodingTests {
    private func roundTrip(_ data: Data, _ want: TextEncoding, _ text: String) {
        let got = TextEncoding.decode(data)
        #expect(got?.encoding == want)
        #expect(got?.text == text)
        #expect(got.flatMap { $0.encoding.encode($0.text) } == data)
    }

    @Test func emptyFile() { roundTrip(Data(), .utf8, "") }
    @Test func utf8() { roundTrip(Data("# Café 👋\r\nx\n".utf8), .utf8, "# Café 👋\r\nx\n") }
    @Test func utf8BOM() { roundTrip(Data([0xEF, 0xBB, 0xBF]) + Data("# Café".utf8), .utf8BOM, "# Café") }
    @Test func utf16LEBOM() {
        roundTrip(Data([0xFF, 0xFE]) + "# Café 👋\n".data(using: .utf16LittleEndian)!, .utf16LE, "# Café 👋\n")
    }
    @Test func utf16BEBOM() {
        roundTrip(Data([0xFE, 0xFF]) + "# Café 👋\n".data(using: .utf16BigEndian)!, .utf16BE, "# Café 👋\n")
    }
    @Test func windows1252WithAccents() {
        // "Café “ok” – naïve": é E9, “ 93, ” 94, – 96, ï EF.
        let bytes: [UInt8] = [0x43, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x6F, 0x6B, 0x94, 0x20, 0x96, 0x20,
                              0x6E, 0x61, 0xEF, 0x76, 0x65]
        roundTrip(Data(bytes), .windows1252, "Café “ok” – naïve")
        roundTrip(Data([0x4E, 0x6F, 0xEB, 0x6C]), .windows1252, "Noël")
    }
    @Test func validUTF8WinsOverWindows1252() { roundTrip(Data("é".utf8), .utf8, "é") }
    @Test func utf16NeverGuessedWithoutBOM() {
        #expect(TextEncoding.decode("ab".data(using: .utf16LittleEndian)!)?.encoding == .utf8)
    }
    @Test func unrepresentableTextIsNotEncoded() {
        #expect(TextEncoding.windows1252.encode("Café 👋") == nil)
        #expect(TextEncoding.windows1252.encode("Café") == Data([0x43, 0x61, 0x66, 0xE9]))
        #expect(TextEncoding.utf8.encode("a") == Data("a".utf8))
    }
}
