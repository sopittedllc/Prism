import Foundation
import Testing
@testable import SimplifyCore

private func le(_ n: Int, _ width: Int = 4) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: n >> (8 * $0)) })
}
private func property(_ type: Int, _ payload: Data, domain: String = "DSIN") -> Data {
    let parent = type == 1 ? Data() : property(1, le(1))
    return le(20 + parent.count + payload.count, 8) + Data(domain.utf8) + le(type) + le(1) + parent + payload
}
private func item(_ properties: Data, children: [Data] = []) -> Data {
    let tail = le(1) + le(children.count) + children.reduce(Data()) { $0 + Data(repeating: 0, count: 12) + $1 }
    return le(40 + properties.count + tail.count, 8) + le(1) + Data("hsin".utf8) + Data(repeating: 0, count: 24) + properties + tail
}
private func library(_ id: String, domain: String = "DSIN") -> Data {
    let text = id.data(using: .utf16LittleEndian)!
    return item(property(106, le(1) + le(1) + le(1) + le(1) + le(text.count / 2) + text + Data(repeating: 0, count: 12), domain: domain))
}

@Test func kontaktPublicMetadataRequiresStructuredDomainAndPreservesOpaqueState() throws {
    let wrapped = item(property(115, le(1) + Data([0]) + library("ABC")),
                       children: [library("DEF"), library("DECOY", domain: "FAKE"), item(property(115, le(1) + Data([1, 99, 42])))])
    let result = try KontaktStateReader.read(wrapped)
    #expect(result.libraryIDs == ["ABC", "DEF"] && result.opaquePayloads == 1)
    #expect(try KontaktStateReader.read(library("../ABC")).libraryIDs.isEmpty)
    #expect(throws: (any Error).self) { try KontaktStateReader.read(library("ABC") + Data([0])) }
    for i in 0..<wrapped.count {
        #expect(throws: (any Error).self) { try KontaktStateReader.read(Data(wrapped.prefix(i))) }
    }
}

@Test func kontaktPublicMetadataBoundsWrapperDepthAndRejectsUnknownEncoding() throws {
    var nested = library("ABC")
    for _ in 0..<30 { nested = item(property(115, le(1) + Data([0]) + nested)) }
    #expect(throws: (any Error).self) { try KontaktStateReader.read(nested) }
    #expect(throws: (any Error).self) { try KontaktStateReader.read(item(property(115, le(1) + Data([255])))) }
}

@Test func nativeKontaktAccordionPublicIdentityWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_TABLE_RUNTIME"] == "1" else { return }
    let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/usage-controls/kontakt-active-controls/Accordion.state")
    let result = try KontaktStateReader.read(BoundedFile.read(file, limit: KontaktStateReader.maximumBytes))
    #expect(result.libraryIDs == ["P44"])
    #expect(result.opaquePayloads == 1)
}

@Test func nativeKontaktEmptyStateHasNoPublicLibraryCandidatesWhenEnabled() throws {
    guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_TABLE_RUNTIME"] == "1" else { return }
    let file = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/usage-controls/20260926-125602/working/Ableton/Kontakt-empty.als.kontakt.bin")
    let result = try KontaktStateReader.read(BoundedFile.read(file, limit: KontaktStateReader.maximumBytes))
    #expect(result.libraryIDs.isEmpty)
    #expect(result.opaquePayloads == 1)
}
