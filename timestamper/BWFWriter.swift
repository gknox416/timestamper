import Foundation

enum BWFWriteError: Error, LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        "Output verification failed. Do not use the output file."
    }
}

/// Copies RIFF bytes, updating timestamps and supported Pro Tools identities.
/// This first proof of concept keeps the file in memory; it does not rebuild chunks.
struct BWFWriter {
    @discardableResult
    static func writeCopy(
        from source: URL,
        to destination: URL,
        timeReference: UInt64
    ) throws -> BWFMetadata {
        let reader = try RIFFReader(url: source)
        return try writeCopy(reader: reader, to: destination, timeReference: timeReference)
    }

    /// Calculate using the same input snapshot that is copied and verified.
    static func writeCopy(from source: URL, to destination: URL,
                          target: Timecode, frameRate: FrameRate) throws -> BWFMetadata {
        let reader = try RIFFReader(url: source)
        let metadata = try reader.readMetadata()
        let reference = try target.sampleReference(sampleRate: metadata.sampleRate, frameRate: frameRate)
        return try writeCopy(reader: reader, to: destination, timeReference: reference)
    }

    private static func writeCopy(reader: RIFFReader, to destination: URL,
                                  timeReference: UInt64) throws -> BWFMetadata {
        let layout = try reader.readLayout()
        let range = layout.timeReferenceRange
        let proTools = try ProToolsMetadata.inspect(data: reader.data, layout: layout)
        var output = reader.data
        for byte in 0..<8 {
            output[range.lowerBound + byte] = UInt8(truncatingIfNeeded: timeReference >> (byte * 8))
        }
        let timestamp = Data(output[range])
        proTools?.patch(&output, timestamp: timestamp)
        var changedRanges = [range]
        if let proTools {
            changedRanges += proTools.timestampRanges + proTools.compactIdentityRanges
                + [proTools.materialIdentityRange, proTools.originatorReferenceRange]
        }
        // Compare contiguous untouched spans rather than scanning large audio
        // payloads byte-by-byte. No chunk reconstruction is allowed here.
        var end = 0
        for changed in changedRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard output[end..<changed.lowerBound] == reader.data[end..<changed.lowerBound] else {
                throw BWFWriteError.verificationFailed
            }
            end = changed.upperBound
        }
        guard output.count == reader.data.count,
              output[end...] == reader.data[end...] else {
            throw BWFWriteError.verificationFailed
        }

        // Exclusive creation, not a check-then-write: also refuses the input path,
        // existing hard links, and symbolic links. Never retry with overwrite enabled.
        try output.write(to: destination, options: .withoutOverwriting)

        // Read the actual on-disk output before reporting success.
        let verified = try RIFFReader(url: destination)
        let verifiedLayout = try verified.readLayout()
        guard verifiedLayout.metadata.timeReference == timeReference,
              verifiedLayout.metadata.sampleRate == layout.metadata.sampleRate,
              verifiedLayout.timeReferenceRange == range,
              verifiedLayout.audioDataRanges == layout.audioDataRanges,
              verified.data.count == reader.data.count,
              verified.data == output,
              layout.audioDataRanges.allSatisfy({ verified.data[$0] == reader.data[$0] }) else {
            throw BWFWriteError.verificationFailed
        }
        // Revalidate synchronized identity and timestamp fields from disk.
        _ = try ProToolsMetadata.inspect(data: verified.data, layout: verifiedLayout)
        return verifiedLayout.metadata
    }
}
