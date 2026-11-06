import Foundation

struct CLIOptions {
    static let usage = """
    Usage:
      timestamper <wav-file> [more-wav-files ...] [--fps <rate>]
      timestamper <wav-file> [more-wav-files ...] --target <HH:MM:SS:FF> --fps <rate> --output-dir <directory>
      timestamper <wav-file> [more-wav-files ...] --zero-to <directory> [--fps <rate>]
    Rates: 23.976, 24, 25, 29.97-ndf, 29.97-df, 30
    Quote drop-frame labels containing a semicolon, e.g. '01:00:00;00'.
    Read-only and legacy --zero-to default to 23.976. Target writes require --fps.
    Output filenames are preserved. Collisions are reported without overwriting or renaming.
    """

    let sources: [URL]
    let frameRate: FrameRate
    let target: Timecode?
    let outputDirectory: URL?

    init(arguments: [String]) throws {
        var paths: [String] = []
        var options: [String: String] = [:]
        var index = 0
        var literalPaths = false
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" && !literalPaths {
                literalPaths = true
                index += 1
                continue
            }
            if argument.hasPrefix("--") && !literalPaths {
                guard ["--fps", "--target", "--output-dir", "--zero-to"].contains(argument),
                      options[argument] == nil, index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError.invalidArguments
                }
                options[argument] = arguments[index + 1]
                index += 2
            } else {
                paths.append(argument)
                index += 1
            }
        }
        guard !paths.isEmpty else { throw CLIError.invalidArguments }
        sources = paths.map { URL(fileURLWithPath: $0) }
        frameRate = try FrameRate(argument: options["--fps"] ?? "23.976")
        if let zeroDirectory = options["--zero-to"] {
            guard options["--target"] == nil, options["--output-dir"] == nil else {
                throw CLIError.invalidArguments
            }
            target = try Timecode("00:00:00:00", frameRate: frameRate)
            outputDirectory = URL(fileURLWithPath: zeroDirectory, isDirectory: true)
        } else if let label = options["--target"] {
            guard let directory = options["--output-dir"], options["--fps"] != nil else {
                throw CLIError.invalidArguments
            }
            target = try Timecode(label, frameRate: frameRate)
            outputDirectory = URL(fileURLWithPath: directory, isDirectory: true)
        } else {
            guard options["--output-dir"] == nil else { throw CLIError.invalidArguments }
            target = nil
            outputDirectory = nil
        }
    }
}

enum CLIError: Error, LocalizedError {
    case invalidArguments
    var errorDescription: String? { CLIOptions.usage }
}
