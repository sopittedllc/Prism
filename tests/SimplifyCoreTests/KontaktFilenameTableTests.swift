import Foundation
import Testing
@testable import SimplifyCore

private func integer(_ value: Int, _ width: Int = 4) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
}
private func table(_ segments: [(UInt8, String)]) -> Data {
    var result = integer(3, 2) + integer(1) + Data(repeating: 0, count: 8) + integer(segments.count)
    for (kind, text) in segments {
        result.append(kind)
        if [1, 2, 4, 5, 8, 9].contains(kind) {
            let encoded = text.data(using: .utf16LittleEndian)!
            result += integer(encoded.count / 2) + encoded
        }
    }
    return result + Data(repeating: 0, count: 20)
}

@Test func kontaktFilenameTablePreservesExactPathsWithoutPromotingOwnership() throws {
    let raw = table([(1, ""), (2, "Libraries"), (2, "Glass 🎵"), (4, "Rubbed.nki")])
    let entry = try #require(KontaktFilenameTable.read(raw).first)
    #expect(entry.absolutePath == "/Libraries/Glass 🎵/Rubbed.nki")
    #expect(entry.header.count == 8 && entry.trailer.count == 20)
    let unresolved: [[(UInt8, String)]] = [
        [(2, "Libraries"), (4, "Rubbed.nki")],
        [(1, ""), (3, ""), (4, "Rubbed.nki")],
        [(1, ""), (8, "Library.nkx"), (4, "Rubbed.nki")],
        [(1, ""), (2, "../Other"), (4, "Rubbed.nki")]
    ]
    for segments in unresolved {
        #expect(try KontaktFilenameTable.read(table(segments)).first?.absolutePath == nil)
    }
}

@Test func kontaktFilenameTableRejectsPartialUnknownAndExcessiveInputs() throws {
    let raw = table([(1, ""), (2, "Library"), (4, "Patch.nki")])
    for end in 0..<raw.count {
        #expect(throws: (any Error).self) { try KontaktFilenameTable.read(Data(raw.prefix(end))) }
    }
    #expect(throws: (any Error).self) { try KontaktFilenameTable.read(raw + Data([0])) }
    #expect(throws: (any Error).self) { try KontaktFilenameTable.read(integer(4, 2) + raw.dropFirst(2)) }
    #expect(throws: (any Error).self) { try KontaktFilenameTable.read(integer(3, 2) + integer(16_385)) }
    #expect(throws: (any Error).self) { try KontaktFilenameTable.read(table([(255, "")])) }
    #expect(try KontaktFilenameTable.read(integer(3, 2) + integer(0)).isEmpty)
}

@Test func nativeKontaktFilenameTablesWhenExplicitlyEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_TABLE_RUNTIME"] == "1" else { return }
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/usage-controls/kontakt-tables")
    let loaded = try KontaktFilenameTable.read(BoundedFile.read(root.appendingPathComponent("loaded.bin"), limit: 4 * 1024 * 1024))
    let empty = try KontaktFilenameTable.read(BoundedFile.read(root.appendingPathComponent("empty.bin"), limit: 4 * 1024 * 1024))
    let paths = loaded.compactMap(\.absolutePath).filter { $0.hasSuffix(".nki") }
    #expect(paths.count == 1)
    #expect(paths.first?.hasSuffix("/01_Rubbed Wineglass.nki") == true)
    #expect(empty.compactMap(\.absolutePath).allSatisfy { !$0.hasSuffix(".nki") })
}
