import Foundation
import XCTest
@testable import Timestamper

final class BatchProcessorTests: XCTestCase {
    private var root: URL!
    private var output: URL!
    private var fixture: Data!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav")
        fixture = try Data(contentsOf: path)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func input(_ path: String, data: Data? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data ?? fixture).write(to: url)
        return url
    }
    private func run(_ sources: [URL], directory: URL? = nil,
                     onResult: (BatchResult) -> Void = { _ in }) throws -> [BatchResult] {
        try BatchProcessor.process(sources: sources, destinationDirectory: directory ?? output,
            target: Timecode("00:30:00:00", frameRate: .fps23_976), frameRate: .fps23_976, onResult: onResult)
    }
    func testMixedSampleRatesPreserveNamesAndAudio() throws {
        var otherRate = fixture!
        for (offset, value) in [(706, UInt32(96_000)), (710, UInt32(288_000))] {
            for i in 0..<4 { otherRate[offset+i] = UInt8(truncatingIfNeeded: value >> (8*i)) }
        }
        let sources = try [input("a/First.WAV"), input("b/Second.wav", data: otherRate)]
        var notifications: [URL] = []
        let results = try run(sources) { notifications.append($0.source) }
        XCTAssertEqual(notifications, sources)
        for (i, result) in results.enumerated() {
            let metadata = try result.outcome.get()
            XCTAssertEqual(metadata.timeReference, i == 0 ? 86_486_400 : 172_972_800)
            XCTAssertEqual(result.destination.lastPathComponent, sources[i].lastPathComponent)
            let before = try Data(contentsOf: sources[i])
            let after = try Data(contentsOf: result.destination)
            XCTAssertEqual(before.count, after.count)
            XCTAssertEqual(before[16384..<22390], after[16384..<22390])
            XCTAssertEqual(before, i == 0 ? fixture : otherRate)
        }
        let first = try Data(contentsOf: results[0].destination)
        let second = try Data(contentsOf: results[1].destination)
        XCTAssertNotEqual(first[456..<464], second[456..<464])
    }
    func testCollidingInputsAllFailAndIndependentInputSucceeds() throws {
        let sources = try [input("a/Same.wav"), input("b/same.WAV"), input("good.wav")]
        let results = try run(sources)
        XCTAssertThrowsError(try results[0].outcome.get())
        XCTAssertThrowsError(try results[1].outcome.get())
        XCTAssertNoThrow(try results[2].outcome.get())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["good.wav"])
        let duplicate = try run([sources[0], sources[0]])
        XCTAssertTrue(duplicate.allSatisfy { if case .failure = $0.outcome { return true }; return false })
    }
    func testExistingFilesLinksAndSourceDirectoryAreProtected() throws {
        let sources = try [input("one.wav"), input("two.wav")]
        let sentinel = Data("existing".utf8)
        let existing = output.appendingPathComponent("ONE.WAV")
        try sentinel.write(to: existing)
        try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("two.wav"),
                                                  withDestinationURL: root.appendingPathComponent("absent"))
        for result in try run(sources) { XCTAssertThrowsError(try result.outcome.get()) }
        XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        for result in try run(sources, directory: root) { XCTAssertThrowsError(try result.outcome.get()) }
        XCTAssertEqual(try Data(contentsOf: sources[0]), fixture)
    }
    func testMalformedAndMissingInputsDoNotStopBatch() throws {
        let bad = try input("bad.wav", data: Data("not WAV".utf8))
        let missing = root.appendingPathComponent("missing.wav")
        let good = try input("good.wav")
        let results = try run([bad, missing, good])
        XCTAssertThrowsError(try results[0].outcome.get())
        XCTAssertThrowsError(try results[1].outcome.get())
        XCTAssertNoThrow(try results[2].outcome.get())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["good.wav"])
        XCTAssertThrowsError(try run([good], directory: missing))
        XCTAssertThrowsError(try run([good], directory: bad))
    }
    func testFileCreatedAfterPlanningIsNotOverwritten() throws {
        let sources = try [input("one.wav"), input("two.wav")]
        let sentinel = Data("created after preflight".utf8)
        let second = output.appendingPathComponent("two.wav")
        let results = try run(sources) { result in
            if result.source == sources[0] {
                do { try sentinel.write(to: second) }
                catch { XCTFail("Could not create collision: \(error)") }
            }
        }
        XCTAssertNoThrow(try results[0].outcome.get())
        XCTAssertThrowsError(try results[1].outcome.get())
        XCTAssertEqual(try Data(contentsOf: second), sentinel)
    }
    func testBatchCLIParsingAndLiteralPaths() throws {
        let options = try CLIOptions(arguments: ["one.wav", "--fps", "24", "two.wav",
            "--target", "00:00:00:00", "--output-dir", "/tmp"])
        XCTAssertEqual(options.sources.map(\.lastPathComponent), ["one.wav", "two.wav"])
        let literal = try CLIOptions(arguments: ["--fps", "25", "--", "--name.wav"])
        XCTAssertEqual(literal.sources[0].lastPathComponent, "--name.wav")
        XCTAssertThrowsError(try CLIOptions(arguments: ["--fps", "24"]))
    }
}
