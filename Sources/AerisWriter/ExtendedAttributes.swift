import Foundation

/// Read/write one extended attribute on a file. Follows symlinks.
enum ExtendedAttributes {
    static func data(named name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size >= 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            guard read >= 0 else { return nil }
            return data.prefix(read)
        }
    }

    static func set(_ data: Data, named name: String, at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// Per-document editor state, kept in an xattr so the `.md` bytes stay untouched.
/// `sel` is the selected range [location, length]; `scroll` is the character index
/// at the top of the editor (survives window-size changes better than a pixel offset).
struct EditorState: Codable, Equatable {
    static let attributeName = "com.aeris.writer.state"

    var sel: [Int]
    var scroll: Int
    /// Set when the caret was at the very end of the text: it then stays at the end of a file that grew since.
    var end: Bool?
    var v = 1
}
