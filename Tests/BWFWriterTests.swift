import Foundation
import CryptoKit
import XCTest
@testable import TimeStamper

final class BWFWriterTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporary)
    }

    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav")
    }

    func testCanonicalProToolsCopy() throws {
        let original = try Data(contentsOf: fixture)
        XCTAssertEqual(SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
                       "b09af898360733a47cd61b86957f238da86408f387c92dafef1e7aafe957014e")
        let before = try RIFFReader(url: fixture).readMetadata()
        XCTAssertEqual(before.sampleRate, 48_000)
        XCTAssertEqual(before.timeReference, 172_972_800)
        XCTAssertEqual(try Timecode.from(timeReference: before.timeReference, sampleRate: before.sampleRate,
                                     frameRate: .fps23_976).description, "01:00:00:00")
        let destination = temporary.appendingPathComponent(fixture.lastPathComponent)
        try BWFWriter.writeCopy(from: fixture, to: destination, timeReference: 0)
        let result = try Data(contentsOf: destination)
        XCTAssertEqual(result.count, original.count)
        // Independently established offsets in the canonical Pro Tools fixture.
        XCTAssertEqual(result[430..<438], Data(repeating: 0, count: 8))
        let allowed = [380..<412, 430..<438, 456..<472, 22410..<22418,
                       22442..<22458, 22506..<22514]
        for i in original.indices where !allowed.contains(where: { $0.contains(i) }) {
            XCTAssertEqual(result[i], original[i], "Unrelated byte changed at \(i)")
        }
        XCTAssertEqual(result[22442..<22458], Data(repeating: 0, count: 16))
        XCTAssertNotEqual(result[456..<464], original[456..<464])
        XCTAssertNotEqual(result[380..<412], original[380..<412])
        XCTAssertEqual(result[456..<464], result[22410..<22418])
        XCTAssertEqual(result[456..<464], result[22506..<22514])
        XCTAssertEqual(result[16384..<22390], original[16384..<22390])
        let after = try RIFFReader(url: destination).readMetadata()
        XCTAssertEqual(after.timeReference, 0)
        XCTAssertEqual(try Timecode.from(timeReference: after.timeReference, sampleRate: after.sampleRate,
                                     frameRate: .fps23_976).description, "00:00:00:00")
        XCTAssertEqual(try Data(contentsOf: fixture), original)
    }

    func testExistingOutputAndSourceAliasesAreNeverOverwritten() throws {
        let source = temporary.appendingPathComponent("source.wav")
        let original = wave()
        try original.write(to: source)
        let existing = temporary.appendingPathComponent("existing.wav")
        let sentinel = Data("keep me".utf8)
        try sentinel.write(to: existing)
        let symbolic = temporary.appendingPathComponent("symbolic.wav")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: source)
        let hard = temporary.appendingPathComponent("hard.wav")
        try FileManager.default.linkItem(at: source, to: hard)
        let dangling = temporary.appendingPathComponent("dangling.wav")
        try FileManager.default.createSymbolicLink(at: dangling,
            withDestinationURL: temporary.appendingPathComponent("absent.wav"))
        for destination in [existing, source, symbolic, hard, dangling] {
            XCTAssertThrowsError(try BWFWriter.writeCopy(from: source, to: destination, timeReference: 0))
        }
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.appendingPathComponent("absent.wav").path))
    }

    func testOddUnknownChunksAndFull64BitReferenceArePreserved() throws {
        let source = temporary.appendingPathComponent("source.wav")
        let original = wave()
        try original.write(to: source)
        let destination = temporary.appendingPathComponent("result.wav")
        let value: UInt64 = 0xFEDCBA9876543210
        try BWFWriter.writeCopy(from: source, to: destination, timeReference: value)
        let result = try Data(contentsOf: destination)
        // Header + 12-byte odd unknown chunk + 24-byte fmt + BEXT header + 338.
        let offset = 394
        XCTAssertEqual(Array(result[offset..<(offset + 8)]), [0x10, 0x32, 0x54, 0x76, 0x98, 0xBA, 0xDC, 0xFE])
        XCTAssertEqual(result[..<offset], original[..<offset])
        XCTAssertEqual(result[(offset + 8)...], original[(offset + 8)...])
        XCTAssertEqual(try RIFFReader(url: destination).readMetadata().timeReference, value)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testMalformedAndUnsupportedInputsDoNotCreateOutput() throws {
        var wrongSize = wave(); wrongSize[4] ^= 1
        var partialHeader = wave(); partialHeader.append(0); fixSize(&partialHeader)
        var missingPad = wave(); missingPad.removeLast(); fixSize(&missingPad)
        var oversizedChunk = wave(); oversizedChunk.replaceSubrange(16..<20, with: le32(UInt32.max))
        var nonWave = wave(); nonWave[0] = 0
        let cases: [Data] = [
            Data(), nonWave, wrongSize, partialHeader, missingPad, oversizedChunk,
            wave(bext: nil), wave(bext: Data(repeating: 0, count: 345)),
            wave(format: nil), wave(format: Data(repeating: 0, count: 15)),
            wave(format: Data(repeating: 0, count: 16)), wave(includeAudio: false),
            wave(duplicateBext: true), wave(duplicateFormat: true)
        ]
        for (index, bytes) in cases.enumerated() {
            let source = temporary.appendingPathComponent("bad-\(index).wav")
            let destination = temporary.appendingPathComponent("output-\(index).wav")
            try bytes.write(to: source)
            XCTAssertThrowsError(try BWFWriter.writeCopy(from: source, to: destination, timeReference: 0), "case \(index)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    func testEachCopyGetsDistinctIdentityAndCanBeProcessedAgain() throws {
        let first = temporary.appendingPathComponent("first.wav")
        let second = temporary.appendingPathComponent("second.wav")
        let third = temporary.appendingPathComponent("third.wav")
        try BWFWriter.writeCopy(from: fixture, to: first, timeReference: 0)
        try BWFWriter.writeCopy(from: fixture, to: second, timeReference: 0)
        try BWFWriter.writeCopy(from: first, to: third, timeReference: 48_000)
        let files = try [first, second, third].map { try Data(contentsOf: $0) }
        XCTAssertEqual(Set(files.map { Data($0[456..<464]) }).count, 3)
        XCTAssertEqual(Set(files.map { Data($0[380..<412]) }).count, 3)
        let metadata = try RIFFReader(url: third).readMetadata()
        XCTAssertEqual(metadata.timeReference, 48_000)
        XCTAssertEqual(files[2][430..<438], files[2][22442..<22450])
        XCTAssertEqual(files[2][430..<438], files[2][22450..<22458])
    }

    func testUnsupportedProToolsIdentityLayoutsFailBeforeWriting() throws {
        let original = try Data(contentsOf: fixture)
        // UMID disagreement, unknown UMID label, timestamp disagreement,
        // unsupported region count/name layout, missing/duplicate identity chunk.
        for offset in [22506, 440, 22442, 22398, 22458, 22490, 742] {
            var invalid = original
            invalid[offset] ^= 0x40
            let source = temporary.appendingPathComponent("bad-\(offset).wav")
            let destination = temporary.appendingPathComponent("out-\(offset).wav")
            try invalid.write(to: source)
            XCTAssertThrowsError(try BWFWriter.writeCopy(from: source, to: destination, timeReference: 0))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), invalid)
        }
    }

    private func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private func chunk(_ id: String, _ payload: Data) -> Data {
        var result = Data(id.utf8) + le32(UInt32(payload.count)) + payload
        if payload.count % 2 == 1 { result.append(0xAB) } // Nonzero padding must survive.
        return result
    }

    private func fixSize(_ data: inout Data) {
        data.replaceSubrange(4..<8, with: le32(UInt32(data.count - 8)))
    }

    private func wave(bext: Data? = Data(repeating: 0x55, count: 602),
                      format: Data? = Data([1, 0, 1, 0, 0x80, 0xBB, 0, 0, 0, 0x77, 2, 0, 3, 0, 24, 0]),
                      includeAudio: Bool = true, duplicateBext: Bool = false,
                      duplicateFormat: Bool = false) -> Data {
        var data = Data("RIFF".utf8) + le32(0) + Data("WAVE".utf8)
        data += chunk("????", Data([1, 2, 3]))
        if let format {
            data += chunk("fmt ", format)
            if duplicateFormat { data += chunk("fmt ", format) }
        }
        if let bext {
            data += chunk("bext", bext)
            if duplicateBext { data += chunk("bext", bext) }
        }
        if includeAudio { data += chunk("data", Data([4, 5, 6, 7, 8, 9])) }
        data += chunk("tail", Data([10]))
        fixSize(&data)
        return data
    }
}
