import Foundation
import Darwin

public enum BoundedFile {
    /// Read a bounded metadata prefix through the first complete terminator.
    /// This avoids charging unrelated trailing binary payload against a batch
    /// reader's budget while preserving the same regular-file/no-link checks.
    public static func readThrough(_ url: URL, terminator: Data, limit: Int) throws -> Data {
        guard !terminator.isEmpty, limit > 0 else { throw ProjectReadError.tooLarge }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var prefix = Data()
        while prefix.count < limit {
            let previous = prefix.count
            guard let chunk = try handle.read(upToCount: min(4096, limit - previous)), !chunk.isEmpty else { break }
            prefix.append(chunk)
            let searchStart = max(0, previous - terminator.count + 1)
            if let close = prefix.range(of: terminator, in: searchStart..<prefix.count) {
                return prefix.subdata(in: 0..<close.upperBound)
            }
        }
        throw ProjectReadError.tooLarge
    }
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
