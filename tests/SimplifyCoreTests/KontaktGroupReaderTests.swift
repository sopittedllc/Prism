import Foundation
import Testing
import CryptoKit
import CFastLZ
@testable import SimplifyCore

struct KontaktGroupReaderTests {
    @Test func qualifiedBrushProfileSeparatesAvailableSourcesFromRestShells() throws {
        let names = [
            "10000: long.nki from ../technique brushes/long.nki",
            "10005: long cs.nki from ../technique brushes/long cs.nki",
            "10010: short spiccato feathered.nki from rest shells",
            "10015: short pizzicato bartok.nki from ../technique brushes/short pizzicato bartok.nki"
        ]
        let result = try KontaktGroupReader.read(nis(groups: names))
        let manifest = KontaktManifestDetails(name: "Chamber Strings", maker: "Spitfire Audio", snpid: "001")
        #expect(SpitfireBrushProfile.articulations(manifest: manifest, groups: result)?.map(\.name) == ["Long", "Long CS", "Pizzicato Bartok"])
        let wrongMaker = KontaktManifestDetails(name: "Chamber Strings", maker: "Other", snpid: "001")
        #expect(SpitfireBrushProfile.articulations(manifest: wrongMaker, groups: result) == nil)
        let horn = try KontaktGroupReader.read(nis(groups: ["Attack", "Dynamic", "Noise"]))
        #expect(SpitfireBrushProfile.articulations(manifest: manifest, groups: horn) == nil)
        let unfamiliar = try KontaktGroupReader.read(nis(groups: names + ["10020: new.nki from other folder/new.nki"]))
        #expect(SpitfireBrushProfile.articulations(manifest: manifest, groups: unfamiliar) == nil)
    }
    @Test func readsPublicGroupsAndVersion() throws {
        let fixture = nis(groups: ["Long Legato", "Pizzicato"])
        let result = try KontaktGroupReader.read(fixture)
        #expect(result.groupNames == ["Long Legato", "Pizzicato"])
        #expect(result.sourceVersion == "6.1.1.255")
    }

    @Test func rejectsMalformedNamesAndMissingGroupList() throws {
        var fixture = nis(groups: ["Long Legato"])
        // An invalid outer length must not produce names from otherwise valid bytes.
        fixture[0] = 0xff
        #expect(throws: KontaktGroupReader.ReadError.self) { try KontaktGroupReader.read(fixture) }
        #expect(throws: KontaktGroupReader.ReadError.self) { try KontaktGroupReader.read(nis(groups: [] , includeGroupList: false)) }
    }

    @Test func readsCompressedSubtree() throws {
        let nested = nis(groups: ["Measured Bow"])
        var output = Data(count: nested.count + nested.count / 20 + 100)
        let count = nested.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { target in
                fastlz_compress_level(1, input.baseAddress, Int32(nested.count), target.baseAddress)
            }
        }
        #expect(count > 0)
        let payload = u(1, 4) + u(1, 1) + u(nested.count, 4) + u(Int(count), 4) + output.prefix(Int(count))
        let outer = item(chunk(115, payload, chunk(1, Data(), Data())))
        #expect(try KontaktGroupReader.read(outer).groupNames == ["Measured Bow"])
        #expect(throws: KontaktGroupReader.ReadError.self) {
            try KontaktGroupReader.read(item(chunk(115, payload.dropLast(), chunk(1, Data(), Data()))))
        }
    }

    @Test func truncatedFastLZMatchIsRejected() throws {
        let truncated = Data([0x20, 0x41, 0x20])
        var output = Data(count: 32)
        let decoded = truncated.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { target in
                fastlz_decompress(input.baseAddress, Int32(truncated.count), target.baseAddress, 32)
            }
        }
        #expect(decoded == 0)
        let payload = u(1, 4) + u(1, 1) + u(32, 4) + u(truncated.count, 4) + truncated
        #expect(throws: KontaktGroupReader.ReadError.self) {
            try KontaktGroupReader.read(item(chunk(115, payload, chunk(1, Data(), Data()))))
        }
    }

    @Test func rejectsInvalidUTF16() throws {
        var fixture = nis(groups: ["Long Legato"])
        let pattern = Data([0x4c, 0x00, 0x6f, 0x00])
        let range = try #require(fixture.range(of: pattern))
        fixture.replaceSubrange(range.lowerBound..<range.lowerBound + 2, with: [0x00, 0xd8])
        #expect(throws: KontaktGroupReader.ReadError.self) { try KontaktGroupReader.read(fixture) }
    }

    @Test func cancelledTaskStopsBeforeReadingNames() async {
        let fixture = nis(groups: ["Long Legato"])
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try KontaktGroupReader.read(fixture)
                return false
            } catch KontaktGroupReader.ReadError.cancelled {
                return true
            } catch {
                return false
            }
        }
        #expect(await task.value)
    }

    @Test func nativeContrastGroupControls() throws {
        guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_GROUP_CONTRAST_RUNTIME"] == "1" else { return }
        let env = ProcessInfo.processInfo.environment
        let positive = try #require(env["PRISM_KONTAKT_GROUP_SYMPHONIC_PATH"])
        let negative = try #require(env["PRISM_KONTAKT_GROUP_HORN_PATH"])
        let symphonicStart = ProcessInfo.processInfo.systemUptime
        let symphonic = try KontaktGroupReader.read(URL(fileURLWithPath: positive))
        print("Symphonic group read seconds:", ProcessInfo.processInfo.systemUptime - symphonicStart)
        #expect(symphonic.groupNames.count == 430)
        #expect(Set(symphonic.groupNames).count == 70)
        let profileManifest = KontaktManifestDetails(name: "Symphonic Strings", maker: "Spitfire Audio", snpid: "001")
        #expect(SpitfireBrushProfile.articulations(manifest: profileManifest, groups: symphonic)?.count == 16)
        let hornStart = ProcessInfo.processInfo.systemUptime
        let horn = try KontaktGroupReader.read(URL(fileURLWithPath: negative))
        print("Horn group read seconds:", ProcessInfo.processInfo.systemUptime - hornStart)
        #expect(horn.groupNames.count == 9)
        #expect(SpitfireBrushProfile.articulations(manifest: profileManifest, groups: horn) == nil)
    }

    @Test func nativeCoreGroupControl() throws {
        guard ProcessInfo.processInfo.environment["PRISM_KONTAKT_GROUP_RUNTIME"] == "1" else { return }
        guard let path = ProcessInfo.processInfo.environment["PRISM_KONTAKT_GROUP_RUNTIME_PATH"] else {
            Issue.record("Set PRISM_KONTAKT_GROUP_RUNTIME_PATH to the read-only Core control")
            return
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "a720ade2d31476a94f2de13f35f9539b8d8b670c0579e9585b1ea56693690e7a")
        let coreStart = ProcessInfo.processInfo.systemUptime
        let result = try KontaktGroupReader.read(url)
        print("Chamber Core group read seconds:", ProcessInfo.processInfo.systemUptime - coreStart)
        #expect(result.groupNames.count == 426)
        #expect(Set(result.groupNames).count == 61)
        #expect(result.groupNames.filter { $0.contains("from ../technique brushes/") }.count == 15)
        #expect(result.groupNames.filter { $0.contains("from rest shells") }.count == 2)
        #expect(result.sourceVersion != nil)
        let profileManifest = KontaktManifestDetails(name: "Chamber Strings", maker: "Spitfire Audio", snpid: "001")
        #expect(SpitfireBrushProfile.articulations(manifest: profileManifest, groups: result)?.map(\.name) == [
            "Long", "Long CS", "Long Harmonics", "Long Flautando", "Long Sul Pont", "Long Sul Pont (Dist)",
            "Long Sul Tasto", "Long Sul C", "Marcato Attack", "Spiccato", "Staccato", "Short CS",
            "Pizzicato", "Pizzicato Bartok", "Col Legno"
        ])
    }

    @Test func nativeAdditionalReaderControl() throws {
        guard let path = ProcessInfo.processInfo.environment["PRISM_KONTAKT_GROUP_OTHER_PATH"] else { return }
        let result = try KontaktGroupReader.read(URL(fileURLWithPath: path))
        #expect(!result.groupNames.isEmpty)
    }

    private func u(_ value: Int, _ width: Int) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func utf16(_ text: String) -> Data {
        let bytes = text.data(using: .utf16LittleEndian)!
        return u(bytes.count / 2, 4) + bytes
    }
    private func block(_ body: Data) -> Data { u(body.count + 8, 8) + body }
    private func object(_ id: Int, _ body: Data) -> Data { u(id, 2) + u(body.count, 4) + body }
    private func structure(_ publicData: Data, _ children: Data = Data()) -> Data {
        u(1, 1) + u(0x95, 2) + u(0, 4) + u(publicData.count, 4) + publicData + u(children.count, 4) + children
    }
    private func chunk(_ type: Int, _ payload: Data, _ next: Data) -> Data {
        block(Data("DSIN".utf8) + u(type, 4) + u(1, 4) + next + payload)
    }
    private func item(_ chunks: Data) -> Data {
        block(u(1, 4) + Data("hsin".utf8) + u(1, 4) + u(0, 4) + Data(repeating: 0, count: 16) + chunks + u(1, 4) + u(0, 4))
    }
    private func nis(groups: [String], includeGroupList: Bool = true) -> Data {
        let groupObjects = groups.reduce(into: Data()) { $0 += structure(utf16($1)) }
        let list = object(0x33, u(groups.count, 4) + groupObjects)
        let program = object(0x28, structure(Data(), includeGroupList ? list : Data()))
        let preset = u(1, 4) + u(0, 4) + u(1, 4) + u(program.count, 4) + u(0, 4) + program + u(0, 4) + u(0, 4)
        let author = u(1, 4) + u(0, 1) + u(2, 4) + u(1, 4) + utf16("6.1.1.255")
        return item(chunk(101, author, chunk(109, preset, chunk(1, Data(), Data()))))
    }
}
