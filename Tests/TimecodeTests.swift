import XCTest
@testable import Timestamper

final class TimecodeTests: XCTestCase {
    func testKnownOneHourReferences() throws {
        let cases: [(FrameRate, String, UInt64)] = [
            (.fps23_976, "01:00:00:00", 172_972_800),
            (.fps24, "01:00:00:00", 172_800_000),
            (.fps25, "01:00:00:00", 172_800_000),
            (.fps29_97NDF, "01:00:00:00", 172_972_800),
            (.fps29_97DF, "01:00:00;00", 172_799_827),
            (.fps30, "01:00:00:00", 172_800_000)
        ]
        for (rate, label, reference) in cases {
            let tc = try Timecode(label, frameRate: rate)
            XCTAssertEqual(try tc.sampleReference(sampleRate: 48_000, frameRate: rate), reference)
            XCTAssertEqual(try Timecode.from(timeReference: reference, sampleRate: 48_000, frameRate: rate), tc)
        }
    }

    func testDropFrameBoundaries() throws {
        // Use 30,000 Hz: every frame is exactly 1001 samples.
        let cases: [(UInt64, String)] = [
            (0, "00:00:00;00"), (1799, "00:00:59;29"), (1800, "00:01:00;02"),
            (3597, "00:01:59;29"), (3598, "00:02:00;02"),
            (17981, "00:09:59;29"), (17982, "00:10:00;00"),
            (19781, "00:10:59;29"), (19782, "00:11:00;02"),
            (107891, "00:59:59;29"), (107892, "01:00:00;00"),
            (2_589_407, "23:59:59;29")
        ]
        for (frame, label) in cases {
            XCTAssertEqual(try Timecode.from(timeReference: frame * 1001, sampleRate: 30_000,
                                             frameRate: .fps29_97DF).description, label)
            XCTAssertEqual(try Timecode(label, frameRate: .fps29_97DF)
                .sampleReference(sampleRate: 30_000, frameRate: .fps29_97DF), frame * 1001)
        }
    }

    func testEveryMinuteAcrossDay() throws {
        for rate in FrameRate.allCases {
            for minute in 0..<1440 {
                let firstFrame = rate.isDropFrame && minute % 10 != 0 ? 2 : 0
                let label = String(format: "%02d:%02d:00:%02d", minute / 60, minute % 60, firstFrame)
                let tc = try Timecode(label, frameRate: rate)
                for sr: UInt32 in [44_100, 48_000, 96_000] {
                    let samples = try tc.sampleReference(sampleRate: sr, frameRate: rate)
                    XCTAssertEqual(try Timecode.from(timeReference: samples, sampleRate: sr, frameRate: rate), tc)
                }
            }
        }
    }

    func testEveryLabelInDropFrameTenMinuteBlock() throws {
        var expectedFrame: UInt64 = 0
        for minute in 0..<10 {
            for second in 0..<60 {
                for frame in 0..<30 {
                    if minute != 0 && second == 0 && frame < 2 { continue }
                    let label = String(format: "00:%02d:%02d;%02d", minute, second, frame)
                    XCTAssertEqual(try Timecode.from(timeReference: expectedFrame * 1001,
                        sampleRate: 30_000, frameRate: .fps29_97DF).description, label)
                    expectedFrame += 1
                }
            }
        }
        XCTAssertEqual(expectedFrame, 17_982)
    }

    func testValidationAndOverflow() throws {
        for label in ["", "1:00:00:00", "24:00:00:00", "00:60:00:00", "00:00:60:00",
                      "00:00:00:24", "00:00:00;00", "-1:00:00:00", "00:00:00:0a", " 00:00:00:00"] {
            XCTAssertThrowsError(try Timecode(label, frameRate: .fps24), label)
        }
        for label in ["00:01:00;00", "00:01:00;01", "23:59:00;01"] {
            XCTAssertThrowsError(try Timecode(label, frameRate: .fps29_97DF))
        }
        XCTAssertThrowsError(try FrameRate(argument: "29.97"))
        for rate in FrameRate.allCases {
            XCTAssertThrowsError(try Timecode.from(timeReference: UInt64.max, sampleRate: 1, frameRate: rate))
            XCTAssertThrowsError(try Timecode.from(timeReference: 0, sampleRate: 0, frameRate: rate))
            let end = try Timecode("23:59:59:\(rate.nominalFPS - 1)", frameRate: rate)
            let last = try end.sampleReference(sampleRate: UInt32.max, frameRate: rate)
            XCTAssertEqual(try Timecode.from(timeReference: last, sampleRate: UInt32.max, frameRate: rate), end)
            // Exactly one label-day in samples, rounded up for fractional positions.
            let day = (rate.framesPerDay * 48_000 * rate.denominator + rate.numerator - 1) / rate.numerator
            XCTAssertThrowsError(try Timecode.from(timeReference: day, sampleRate: 48_000, frameRate: rate))
        }
        XCTAssertThrowsError(try Timecode("00:00:00:00", frameRate: .fps24)
            .sampleReference(sampleRate: 0, frameRate: .fps24))
    }

    func testRoundingNearestTiesUp() throws {
        XCTAssertThrowsError(try Timecode("00:00:00:01", frameRate: .fps24)
            .sampleReference(sampleRate: 1, frameRate: .fps24))
        XCTAssertEqual(try Timecode("00:00:00:01", frameRate: .fps24)
            .sampleReference(sampleRate: 44_100, frameRate: .fps24), 1838)
        XCTAssertEqual(try Timecode.from(timeReference: 999, sampleRate: 48_000, frameRate: .fps24).frames, 0)
        XCTAssertEqual(try Timecode.from(timeReference: 1000, sampleRate: 48_000, frameRate: .fps24).frames, 1)
    }

    func testCLIOptions() throws {
        let options = try CLIOptions(arguments: ["in.wav", "--target", "01:00:00;00", "--fps", "29.97-df",
                                                  "--output-dir", "/tmp"])
        XCTAssertEqual(options.target?.description, "01:00:00;00")
        XCTAssertEqual(options.frameRate, .fps29_97DF)
        XCTAssertNil(try CLIOptions(arguments: ["in.wav"]).target)
        XCTAssertEqual(try CLIOptions(arguments: ["in.wav", "--zero-to", "/tmp"]).target?.description, "00:00:00:00")
        let invalid = [
            [], ["in.wav", "--fps"], ["in.wav", "--fps", "29.97"],
            ["in.wav", "--target", "01:00:00:00", "--output-dir", "/tmp"],
            ["in.wav", "--target", "01:00:00:00", "--fps", "24"],
            ["in.wav", "--output-dir", "/tmp"], ["in.wav", "--bogus", "24"],
            ["in.wav", "--fps", "24", "--fps", "25"],
            ["in.wav", "--zero-to", "/tmp", "--target", "00:00:00:00"]
        ]
        for args in invalid { XCTAssertThrowsError(try CLIOptions(arguments: args)) }
    }
}
