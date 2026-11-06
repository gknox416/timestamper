import Foundation

enum RIFFError: Error, LocalizedError {
    case fileTooSmall
    case notWave
    case invalidChunkSize
    case missingBext
    case missingFormat
    case invalidBext
    case invalidFormat
    case duplicateMetadata
    case missingData

    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            return "File is too small to be a WAV file."
        case .notWave:
            return "File is not a RIFF/WAVE file."
        case .invalidChunkSize:
            return "WAV contains an invalid chunk size."
        case .missingBext:
            return "WAV does not contain a BEXT chunk."
        case .missingFormat:
            return "WAV does not contain a format chunk."
        case .invalidBext:
            return "BEXT chunk is too small to contain a TimeReference."
        case .invalidFormat:
            return "Format chunk is invalid."
        case .duplicateMetadata:
            return "WAV contains ambiguous duplicate format or BEXT chunks."
        case .missingData:
            return "WAV does not contain an audio data chunk."
        }
    }
}

struct BWFMetadata {
    let sampleRate: UInt32
    let timeReference: UInt64
}

struct BWFLayout {
    let metadata: BWFMetadata
    let timeReferenceRange: Range<Int>
    let audioDataRanges: [Range<Int>]
    let chunks: [String: [Range<Int>]]
}

struct RIFFReader {

    let data: Data

    init(url: URL) throws {
        data = try Data(contentsOf: url)
    }

    func readMetadata() throws -> BWFMetadata {
        try readLayout().metadata
    }

    func readLayout() throws -> BWFLayout {

        guard data.count >= 12 else {
            throw RIFFError.fileTooSmall
        }

        guard fourCC(at: 0) == "RIFF",
              fourCC(at: 8) == "WAVE" else {
            throw RIFFError.notWave
        }

        var offset = 12
        // Be conservative: do not patch files with inconsistent RIFF boundaries.
        guard Int(readUInt32LE(at: 4)) + 8 == data.count else {
            throw RIFFError.invalidChunkSize
        }
        var sampleRate: UInt32?
        var timeReference: UInt64?
        var timeReferenceRange: Range<Int>?
        var audioDataRanges: [Range<Int>] = []
        var chunks: [String: [Range<Int>]] = [:]

        while offset < data.count {
            guard offset + 8 <= data.count else {
                throw RIFFError.invalidChunkSize
            }

            let chunkID = fourCC(at: offset)
            let chunkSize = Int(readUInt32LE(at: offset + 4))
            let chunkDataOffset = offset + 8

            let nextOffset = chunkDataOffset + chunkSize + chunkSize % 2
            guard nextOffset <= data.count else {
                throw RIFFError.invalidChunkSize
            }
            chunks[chunkID, default: []].append(chunkDataOffset..<(chunkDataOffset + chunkSize))

            switch chunkID {

            case "fmt ":
                guard sampleRate == nil else { throw RIFFError.duplicateMetadata }
                guard chunkSize >= 16 else {
                    throw RIFFError.invalidFormat
                }

                // In a WAV fmt chunk, sample rate begins
                // 4 bytes into the chunk payload.
                sampleRate = readUInt32LE(
                    at: chunkDataOffset + 4
                )
                guard sampleRate != 0 else { throw RIFFError.invalidFormat }

            case "bext":
                guard timeReference == nil else { throw RIFFError.duplicateMetadata }
                guard chunkSize >= 346 else {
                    throw RIFFError.invalidBext
                }

                // BEXT TimeReference begins 338 bytes
                // into the BEXT payload.
                timeReference = readUInt64LE(
                    at: chunkDataOffset + 338
                )
                timeReferenceRange = (chunkDataOffset + 338)..<(chunkDataOffset + 346)

            case "data":
                audioDataRanges.append(chunkDataOffset..<(chunkDataOffset + chunkSize))

            default:
                break
            }

            offset = nextOffset
        }

        guard let sampleRate else {
            throw RIFFError.missingFormat
        }

        guard let timeReference, let timeReferenceRange else {
            throw RIFFError.missingBext
        }

        guard !audioDataRanges.isEmpty else { throw RIFFError.missingData }

        return BWFLayout(
            metadata: BWFMetadata(sampleRate: sampleRate, timeReference: timeReference),
            timeReferenceRange: timeReferenceRange,
            audioDataRanges: audioDataRanges,
            chunks: chunks
        )
    }

    private func fourCC(at offset: Int) -> String {
        let bytes = data[offset..<(offset + 4)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func readUInt64LE(at offset: Int) -> UInt64 {
        UInt64(readUInt32LE(at: offset))
            | UInt64(readUInt32LE(at: offset + 4)) << 32
    }
}
