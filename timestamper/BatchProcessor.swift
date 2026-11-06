import Foundation

struct BatchResult {
    let source: URL
    let destination: URL
    let outcome: Result<BWFMetadata, Error>
}

enum BatchError: Error, LocalizedError {
    case invalidDestination, filenameCollision, existingOutput

    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "Destination must be an existing directory."
        case .filenameCollision: return "Multiple inputs have the same output filename (ignoring case). All conflicting inputs were skipped."
        case .existingOutput: return "Destination already exists. Choose another directory or resolve the collision; nothing was overwritten."
        }
    }
}

/// Sequential, independent file operations. Failed items do not cancel other items.
/// No filesystem modifications occur during planning. The writer still exclusively
/// creates each output to protect against destinations created after planning.
struct BatchProcessor {
    static func process(sources: [URL], destinationDirectory: URL, target: Timecode,
                        frameRate: FrameRate,
                        onResult: (BatchResult) -> Void = { _ in }) throws -> [BatchResult] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw BatchError.invalidDestination }
        func nameKey(_ name: String) -> String {
            name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive,
                                                               locale: Locale(identifier: "en_US_POSIX"))
        }
        let groups = Dictionary(grouping: sources, by: { nameKey($0.lastPathComponent) })
        // Including directory entries catches dangling symlinks and case-only
        // collisions, even on case-sensitive development volumes.
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path).map(nameKey))
        var results: [BatchResult] = []
        for source in sources {
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let outcome: Result<BWFMetadata, Error>
            if groups[nameKey(source.lastPathComponent)]!.count > 1 {
                outcome = .failure(BatchError.filenameCollision)
            } else if existing.contains(nameKey(source.lastPathComponent)) {
                outcome = .failure(BatchError.existingOutput)
            } else {
                outcome = Result {
                    try BWFWriter.writeCopy(from: source, to: destination, target: target, frameRate: frameRate)
                }
            }
            let result = BatchResult(source: source, destination: destination, outcome: outcome)
            results.append(result)
            onResult(result)
        }
        return results
    }
}
