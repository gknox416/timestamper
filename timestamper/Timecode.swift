import Foundation

enum FrameRate: CaseIterable {
    case fps23_976
    case fps24
    case fps25
    case fps29_97NDF
    case fps29_97DF
    case fps30

    init(argument: String) throws {
        switch argument {
        case "23.976": self = .fps23_976
        case "24": self = .fps24
        case "25": self = .fps25
        case "29.97-ndf": self = .fps29_97NDF
        case "29.97-df": self = .fps29_97DF
        case "30": self = .fps30
        default: throw TimecodeError.invalidFrameRate
        }
    }

    var isDropFrame: Bool { self == .fps29_97DF }
    var framesPerDay: UInt64 { isDropFrame ? 2_589_408 : nominalFPS * 86_400 }

    /// Actual playback-rate numerator.
    var numerator: UInt64 {
        switch self {
        case .fps23_976:
            return 24_000
        case .fps24:
            return 24
        case .fps25:
            return 25
        case .fps29_97NDF, .fps29_97DF:
            return 30_000
        case .fps30:
            return 30
        }
    }

    /// Actual playback-rate denominator.
    var denominator: UInt64 {
        switch self {
        case .fps23_976, .fps29_97NDF, .fps29_97DF:
            return 1_001
        default:
            return 1
        }
    }

    /// Number of frame labels per nominal second.
    var nominalFPS: UInt64 {
        switch self {
        case .fps23_976, .fps24:
            return 24
        case .fps25:
            return 25
        case .fps29_97NDF, .fps29_97DF, .fps30:
            return 30
        }
    }

    var name: String {
        switch self {
        case .fps23_976:
            return "23.976"
        case .fps24:
            return "24"
        case .fps25:
            return "25"
        case .fps29_97NDF:
            return "29.97 NDF"
        case .fps29_97DF:
            return "29.97 DF"
        case .fps30:
            return "30"
        }
    }
}

enum TimecodeError: Error, LocalizedError {
    case invalidFrameRate, invalidLabel, skippedDropFrameLabel, invalidSampleRate, outOfRange, insufficientSampleRate

    var errorDescription: String? {
        switch self {
        case .invalidFrameRate: return "Frame rate must be 23.976, 24, 25, 29.97-ndf, 29.97-df, or 30."
        case .invalidLabel: return "Use HH:MM:SS:FF (or HH:MM:SS;FF for drop-frame), with valid fields and hours 00–23."
        case .skippedDropFrameLabel: return "29.97 DF skips frame labels 00 and 01 at each minute except every tenth minute."
        case .invalidSampleRate: return "Sample rate must be greater than zero."
        case .insufficientSampleRate: return "Sample rate is too low to represent this frame label accurately."
        case .outOfRange: return "Time reference is outside the supported 00–23 hour timecode day; it will not wrap."
        }
    }
}

struct Timecode: CustomStringConvertible, Equatable {
    let hours: UInt64
    let minutes: UInt64
    let seconds: UInt64
    let frames: UInt64
    let dropFrame: Bool

    var description: String {
        String(format: "%02llu:%02llu:%02llu%@%02llu",
               hours, minutes, seconds, dropFrame ? ";" : ":", frames)
    }

    init(_ text: String, frameRate: FrameRate) throws {
        let bytes = Array(text.utf8)
        guard bytes.count == 11, bytes[2] == 58, bytes[5] == 58,
              bytes[8] == 58 || (frameRate.isDropFrame && bytes[8] == 59),
              [0, 1, 3, 4, 6, 7, 9, 10].allSatisfy({ (48...57).contains(bytes[$0]) }) else {
            throw TimecodeError.invalidLabel
        }
        func field(_ i: Int) -> UInt64 { UInt64(bytes[i] - 48) * 10 + UInt64(bytes[i + 1] - 48) }
        hours = field(0); minutes = field(3); seconds = field(6); frames = field(9)
        dropFrame = frameRate.isDropFrame
        guard hours < 24, minutes < 60, seconds < 60, frames < frameRate.nominalFPS else {
            throw TimecodeError.invalidLabel
        }
        if dropFrame && minutes % 10 != 0 && seconds == 0 && frames < 2 {
            throw TimecodeError.skippedDropFrameLabel
        }
    }

    private init(frameNumber: UInt64, frameRate: FrameRate) {
        // A ten-minute DF block has one 1800-frame minute followed by nine
        // 1798-frame minutes. Add skipped labels only after crossing each boundary.
        var labels = frameNumber
        if frameRate.isDropFrame {
            let blocks = frameNumber / 17_982
            let remainder = frameNumber % 17_982
            let shortMinutes = remainder < 1_800 ? 0 : 1 + (remainder - 1_800) / 1_798
            labels += blocks * 18 + shortMinutes * 2
        }
        frames = labels % frameRate.nominalFPS
        let totalSeconds = labels / frameRate.nominalFPS
        seconds = totalSeconds % 60
        minutes = (totalSeconds / 60) % 60
        hours = totalSeconds / 3600
        dropFrame = frameRate.isDropFrame
    }

    func sampleReference(sampleRate: UInt32, frameRate: FrameRate) throws -> UInt64 {
        guard sampleRate > 0 else { throw TimecodeError.invalidSampleRate }
        // Revalidate when a caller supplies a different rate than the parsed label.
        let validated = try Timecode(description, frameRate: frameRate)
        guard validated.dropFrame == dropFrame else { throw TimecodeError.invalidLabel }
        let totalMinutes = hours * 60 + minutes
        var frameNumber = (totalMinutes * 60 + seconds) * frameRate.nominalFPS + frames
        if dropFrame { frameNumber -= 2 * (totalMinutes - totalMinutes / 10) }
        let reference = try Self.roundedRatio(frameNumber, UInt64(sampleRate) * frameRate.denominator,
                                             dividedBy: frameRate.numerator)
        guard try Self.from(timeReference: reference, sampleRate: sampleRate, frameRate: frameRate) == self else {
            throw TimecodeError.insufficientSampleRate
        }
        return reference
    }

    static func from(timeReference: UInt64, sampleRate: UInt32, frameRate: FrameRate) throws -> Timecode {
        guard sampleRate > 0 else { throw TimecodeError.invalidSampleRate }
        let frameNumber = try roundedRatio(timeReference, frameRate.numerator,
                                          dividedBy: UInt64(sampleRate) * frameRate.denominator)
        guard frameNumber < frameRate.framesPerDay else { throw TimecodeError.outOfRange }
        return Timecode(frameNumber: frameNumber, frameRate: frameRate)
    }

    /// Exact integer scaling with a 128-bit intermediate. Round nearest, ties up.
    /// BEXT can only store whole samples; fractional frame boundaries are quantized.
    private static func roundedRatio(_ value: UInt64, _ multiplier: UInt64,
                                     dividedBy divisor: UInt64) throws -> UInt64 {
        let product = value.multipliedFullWidth(by: multiplier)
        guard product.high < divisor else { throw TimecodeError.outOfRange }
        let division = divisor.dividingFullWidth(product)
        let increment: UInt64 = division.remainder >= (divisor + 1) / 2 ? 1 : 0
        let rounded = division.quotient.addingReportingOverflow(increment)
        guard !rounded.overflow else { throw TimecodeError.outOfRange }
        return rounded.partialValue
    }
}
