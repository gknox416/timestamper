import Foundation

if CommandLine.arguments.dropFirst() == ["--help"] {
    print(CLIOptions.usage)
    exit(0)
}

func reportError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
}

do {
    let options = try CLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    var failures = 0
    if let target = options.target, let directory = options.outputDirectory {
        let results = try BatchProcessor.process(sources: options.sources, destinationDirectory: directory,
                                                target: target, frameRate: options.frameRate) { result in
            switch result.outcome {
            case .success(let metadata):
                print("Verified: \(result.source.path) -> \(result.destination.path)")
                print("  \(target) at \(options.frameRate.name); \(metadata.timeReference) samples; \(metadata.sampleRate) Hz")
            case .failure(let error):
                failures += 1
                reportError("\(result.source.path) -> \(result.destination.path): \(error.localizedDescription)")
            }
        }
        print("Batch complete: \(results.count - failures) verified, \(failures) failed, \(results.count) total.")
    } else {
        for source in options.sources {
            do {
                let metadata = try RIFFReader(url: source).readMetadata()
                let tc = try Timecode.from(timeReference: metadata.timeReference,
                                          sampleRate: metadata.sampleRate, frameRate: options.frameRate)
                print("File: \(source.path)")
                print("Sample Rate: \(metadata.sampleRate) Hz")
                print("BEXT TimeReference: \(metadata.timeReference) samples")
                print("Frame Rate: \(options.frameRate.name)")
                print("Start TC: \(tc)")
            } catch {
                failures += 1
                reportError("\(source.path): \(error.localizedDescription)")
            }
        }
    }
    if failures > 0 { exit(1) }
} catch {
    reportError(error.localizedDescription)
    exit(1)
}
