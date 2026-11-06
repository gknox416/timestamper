import Foundation

enum ProToolsMetadataError: Error, LocalizedError {
    case unsupportedLayout

    var errorDescription: String? {
        "Unrecognized or inconsistent Pro Tools identity/timestamp metadata. No output was created."
    }
}

/// Narrow compatibility profile derived from the canonical fixture and its
/// Pro Tools-restamped copy. Unknown layouts fail closed rather than retaining
/// an identity known to collide. This is not a general regn/UMID parser.
struct ProToolsMetadata {
    let timestampRanges: [Range<Int>]
    let compactIdentityRanges: [Range<Int>]
    let materialIdentityRange: Range<Int>
    let originatorReferenceRange: Range<Int>

    static func inspect(data: Data, layout: BWFLayout) throws -> ProToolsMetadata? {
        let bext = layout.chunks["bext"]![0]
        let b = bext.lowerBound
        let isProTools = data[(b + 256)..<(b + 265)] == Data("Pro Tools".utf8)
        let hasPrivateChunks = ["regn", "umid", "minf"].contains { layout.chunks[$0] != nil }
        guard isProTools || hasPrivateChunks else { return nil }
        func unique(_ id: String, size: Int) throws -> Range<Int> {
            guard let ranges = layout.chunks[id], ranges.count == 1,
                  ranges[0].count == size else { throw ProToolsMetadataError.unsupportedLayout }
            return ranges[0]
        }
        let r = try unique("regn", size: 92).lowerBound
        let u = try unique("umid", size: 24).lowerBound
        _ = try unique("minf", size: 16)
        let prefix = Data([0x06, 0x0A, 0x2B, 0x34, 1, 1, 1, 5, 1, 1, 0x0F, 0x10, 0x13, 0, 0, 0])
        guard isProTools, bext.count >= 602,
              data[(b + 346)..<(b + 348)] == Data([1, 0]),
              data[(b + 348)..<(b + 364)] == prefix,
              data[(b + 380)..<(b + 412)] == Data(repeating: 0, count: 32),
              data[r..<(r + 4)] == Data([1, 0, 0, 0]),
              data[(r + 4)..<(r + 12)] == Data([0, 0, 0, 0, 0, 0, 0, 42]),
              data[u..<(u + 8)] == Data([0, 0, 0, 0, 0, 0, 0, 42]),
              data[(u + 16)..<(u + 24)] == Data(repeating: 0, count: 8),
              data[r + 60] <= 14,
              data[(b + 364)..<(b + 372)] == data[(r + 12)..<(r + 20)],
              data[(b + 364)..<(b + 372)] == data[(u + 8)..<(u + 16)],
              data[(r + 44)..<(r + 52)] == data[layout.timeReferenceRange],
              data[(r + 52)..<(r + 60)] == data[layout.timeReferenceRange] else {
            throw ProToolsMetadataError.unsupportedLayout
        }
        return ProToolsMetadata(
            timestampRanges: [(r + 44)..<(r + 52), (r + 52)..<(r + 60)],
            compactIdentityRanges: [(r + 12)..<(r + 20), (u + 8)..<(u + 16)],
            materialIdentityRange: (b + 364)..<(b + 380),
            originatorReferenceRange: (b + 288)..<(b + 320)
        )
    }

    func patch(_ output: inout Data, timestamp: Data) {
        // A new random identity per copy; mirror its first eight bytes in the
        // two compact Pro Tools identity fields, as observed in native files.
        var uuid = UUID().uuid
        var identity = withUnsafeBytes(of: &uuid) { Data($0) }
        while identity.prefix(8) == output[materialIdentityRange].prefix(8) {
            uuid = UUID().uuid
            identity = withUnsafeBytes(of: &uuid) { Data($0) }
        }
        output.replaceSubrange(materialIdentityRange, with: identity)
        for range in compactIdentityRanges { output.replaceSubrange(range, with: identity.prefix(8)) }
        let reference = Data(UUID().uuidString.replacingOccurrences(of: "-", with: "").utf8)
        output.replaceSubrange(originatorReferenceRange, with: reference)
        for range in timestampRanges { output.replaceSubrange(range, with: timestamp) }
    }
}
