import Foundation
import Darwin

public enum BoundedFile {
    /// Nonblocking open plus descriptor validation rejects FIFOs, devices, and symlinks.
    public static func read(_ url: URL, limit: Int, prefixOnly: Bool = false) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let data = try handle.read(upToCount: prefixOnly ? limit : limit + 1) ?? Data()
        guard data.count <= limit else { throw ProjectReadError.tooLarge }
        return data
    }
}
