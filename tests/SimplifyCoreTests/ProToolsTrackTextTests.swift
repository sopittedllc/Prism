import Foundation
import Testing
@testable import SimplifyCore

private let trackSessionHeader = "SESSION NAME:\tExample\nSAMPLE RATE:\t48000.000000\nBIT DEPTH:\t24-bit\nSESSION START TIMECODE:\t04:00:00:00\nTIMECODE FORMAT:\t24 Frame\n# OF AUDIO TRACKS:\t1\n# OF AUDIO CLIPS:\t2\n# OF AUDIO FILES:\t1\n\n"
private let trackSection = "T R A C K  L I S T I N G\n"
private let eventHeader = "CHANNEL\tEVENT\tCLIP NAME\tSTART TIME\tEND TIME\tDURATION\tSTATE\n"
private let fileSection = "O N L I N E  F I L E S  I N  S E S S I O N\nFilename\tLocation\n"
private let clipSection = "O N L I N E  C L I P S  I N  S E S S I O N\nCLIP NAME\tSource File\n"
private let oneFile = "Tone.wav\tVolume:Audio:\n"
private let oneClip = "Tone.L\tTone.wav\t[1]\n"
private func eventRow(_ state: String = "Unmuted") -> String {
    "1\t1\tTone.L\t04:00:06:00\t04:01:50:12\t00:01:44:12\t\(state)\n"
}
private func trackBlock(_ rows: String, name: String = "Audio 1", comments: String = "") -> String {
    "TRACK NAME:\t\(name)\nCOMMENTS:\t\(comments)\nUSER DELAY:\t0 Samples\nSTATE: \nPLUG-INS: \tExample EQ (stereo)\n" + eventHeader + rows
}
private func trackData(_ tracks: String, pools: String = "") -> Data {
    Data((trackSessionHeader + pools + trackSection + tracks).utf8)
}

@Test func proToolsTrackPlacementRetainsMutedRowsAndPoolOnlyStaysEmpty() throws {
    let pools = fileSection + oneFile + clipSection + oneClip
    let r = try ProToolsSessionTextReader.parse(trackData(trackBlock(eventRow("Muted")), pools: pools))
    #expect(r.includedSections == ["online-files", "online-clips", "tracks"])
    let t = try #require(r.tracks.first), e = try #require(t.events.first)
    #expect(t.ordinal == 0 && t.name == "Audio 1" && t.comments == "" && t.state == "")
    #expect(t.userDelay == "0 Samples" && t.pluginSummary == "Example EQ (stereo)")
    #expect(e.state == "Muted" && e.clipName == "Tone.L" && e.eventNumber == "1" && e.channel == "1")
    #expect(e.start == "04:00:06:00" && e.end == "04:01:50:12" && e.duration == "00:01:44:12")
    #expect(e.clipPoolOrdinal == 0 && e.filePoolOrdinal == 0 && e.bindingStatus == "unique-export-row")
    let removed = try ProToolsSessionTextReader.parse(trackData(trackBlock(""), pools: pools))
    #expect(removed.tracks.count == 1 && removed.tracks[0].events.isEmpty)
    #expect(removed.files == r.files && removed.clips == r.clips)
    let absent = try ProToolsSessionTextReader.parse(Data((trackSessionHeader + pools).utf8))
    let empty = try ProToolsSessionTextReader.parse(trackData("", pools: pools))
    #expect(!absent.includedSections.contains("tracks") && empty.includedSections.contains("tracks"))
    #expect(absent.tracks.isEmpty && empty.tracks.isEmpty)
}

@Test func proToolsTrackJoinsPreserveAllUnresolvedCasesWithoutFirstMatch() throws {
    let cases: [(String, String, Int?, Int?)] = [
        ("", "clip-list-omitted", nil, nil),
        (clipSection, "missing-clip-name", nil, nil),
        (clipSection + oneClip + oneClip, "ambiguous-clip-name", nil, nil),
        (clipSection + oneClip, "file-list-omitted", 0, nil),
        (fileSection + clipSection + oneClip, "missing-file-name", 0, nil),
        (fileSection + oneFile + oneFile + clipSection + oneClip, "ambiguous-file-name", 0, nil),
        (fileSection + oneFile + "O F F L I N E  F I L E S  I N  S E S S I O N\nFilename\tLocation\n" + oneFile + clipSection + oneClip, "ambiguous-file-name", 0, nil),
        (fileSection + oneFile + clipSection + oneClip.replacingOccurrences(of: "Tone.L", with: "tone.L"), "missing-clip-name", nil, nil),
        (fileSection + oneFile.replacingOccurrences(of: "Tone.wav", with: "tone.wav") + clipSection + oneClip, "missing-file-name", 0, nil),
        ("O F F L I N E  F I L E S  I N  S E S S I O N\nFilename\tLocation\n" + oneFile + clipSection + oneClip, "unique-export-row", 0, 0)
    ]
    for (pools, status, clip, file) in cases {
        let r = try ProToolsSessionTextReader.parse(trackData(trackBlock(eventRow()), pools: pools))
        let e = try #require(r.tracks.first?.events.first)
        #expect(e.bindingStatus == status && e.clipPoolOrdinal == clip && e.filePoolOrdinal == file)
    }
}

@Test func proToolsTrackOwnersAndCellDecoysDoNotCreatePluginOrTrackIdentity() throws {
    let block = trackBlock(eventRow(), name: "Repeated", comments: "P L U G - I N S  L I S T I N G")
    let r = try ProToolsSessionTextReader.parse(trackData(block + "\n" + block + "M A R K E R S  L I S T I N G\n" + trackSection + block))
    #expect(r.tracks.map(\.ordinal) == [0, 1] && r.tracks.map(\.name) == ["Repeated", "Repeated"])
    #expect(r.tracks.map(\.events.count) == [1, 1] && r.plugins.isEmpty)
    #expect(r.tracks.allSatisfy { $0.comments == "P L U G - I N S  L I S T I N G" })
    let blankPlugin = trackBlock("").replacingOccurrences(of: "Example EQ (stereo)", with: "")
    #expect(try ProToolsSessionTextReader.parse(trackData(blankPlugin)).tracks[0].pluginSummary == "")
}

@Test func proToolsTrackGrammarRejectsMalformedMetadataAndEvents() {
    let block = trackBlock(eventRow())
    var invalid = [
        "TRACK NAME:\tIncomplete\nM A R K E R S  L I S T I N G\n",
        block.replacingOccurrences(of: "COMMENTS:\t\n", with: ""),
        block.replacingOccurrences(of: "COMMENTS:\t\n", with: "COMMENTS:\t\nCOMMENTS:\t\n"),
        block.replacingOccurrences(of: "STATE: \n", with: "STATE:\tMuted\n"),
        block.replacingOccurrences(of: "USER DELAY:", with: "DELAY:"),
        block.replacingOccurrences(of: eventHeader, with: ""),
        block.replacingOccurrences(of: "DURATION\tSTATE", with: "STATE\tDURATION"),
        block.replacingOccurrences(of: "DURATION\tSTATE", with: "DURATION\tSTATE\tUSER TIMESTAMP"),
        block + trackSection, block + fileSection,
        trackBlock("1\t1\tTone.L\n"),
        trackBlock(eventRow().replacingOccurrences(of: "Tone.L", with: "")),
        trackBlock(eventRow().replacingOccurrences(of: "Tone.L", with: String(repeating: "x", count: 1_025)))
    ]
    for number in ["0", "000", "-1", "1x", "+1", "１"] {
        invalid.append(trackBlock(eventRow().replacingOccurrences(of: "1\t1\t", with: number + "\t1\t")))
        invalid.append(trackBlock(eventRow().replacingOccurrences(of: "1\t1\t", with: "1\t" + number + "\t")))
    }
    for text in invalid { #expect(throws: (any Error).self) { try ProToolsSessionTextReader.parse(trackData(text)) } }
}

@Test func proToolsTrackAndSharedRowBudgetsRemainBounded() throws {
    let events = String(repeating: eventRow(), count: ProToolsSessionTextReader.maximumRows)
    #expect(try ProToolsSessionTextReader.parse(trackData(trackBlock(events))).tracks[0].events.count == ProToolsSessionTextReader.maximumRows)
    #expect(throws: (any Error).self) {
        try ProToolsSessionTextReader.parse(trackData(trackBlock(events), pools: fileSection + oneFile))
    }
    let plugins = "P L U G - I N S  L I S T I N G\nMANUFACTURER\tPLUG-IN NAME\tVERSION\tFORMAT\tSTEMS\tNUMBER OF INSTANCES\nMaker\tEQ\t1\tAAX\tStereo\t1 active\n"
    #expect(throws: (any Error).self) {
        try ProToolsSessionTextReader.parse(trackData(trackBlock(events), pools: plugins))
    }
    #expect(throws: (any Error).self) {
        try ProToolsSessionTextReader.parse(trackData(String(repeating: trackBlock(""), count: ProToolsSessionTextReader.maximumTracks + 1)))
    }
    #expect(try ProToolsSessionTextReader.parse(trackData(String(repeating: trackBlock(""), count: ProToolsSessionTextReader.maximumTracks))).tracks.count == ProToolsSessionTextReader.maximumTracks)
}
