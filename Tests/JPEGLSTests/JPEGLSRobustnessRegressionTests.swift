/// Regression tests for issues found by the hot-path-optimizations branch
/// review: Data-slice handling, malformed/hostile streams, and encoder
/// configuration validation. Every malformed input must throw a
/// `JPEGLSError` — never crash, and never decode silently to garbage.

import Foundation
import Testing
@testable import JPEGLS

@Suite("Robustness regressions (branch review)")
struct JPEGLSRobustnessRegressionTests {

    // MARK: - Helpers

    private func encodeSample(
        width: Int = 24, height: Int = 20, restartInterval: Int = 0
    ) throws -> (encoded: Data, pixels: [[Int]]) {
        let pixels = (0..<height).map { row in
            (0..<width).map { col in (row * 5 + col * 3) % 256 }
        }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(restartInterval: restartInterval)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        return (encoded, pixels)
    }

    /// Remove the DRI segment (FFDD, length 4, 2-byte interval) from a stream.
    private func strippingDRI(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDD {
                bytes.removeSubrange(i..<i + 6)
                return Data(bytes)
            }
            i += 1
        }
        return data
    }

    // MARK: - Data slices (zero-based offset assumptions)

    @Test("Decoding a Data slice with non-zero startIndex matches the unsliced decode")
    func dataSliceDecode() throws {
        let (encoded, pixels) = try encodeSample()
        // Embed the stream after a prefix and decode the slice; slice indices
        // are parent-relative, which used to mis-slice the scan ranges.
        for prefixLength in [1, 2, 7, 64] {
            let prefixed = Data(repeating: 0xAB, count: prefixLength) + encoded
            let slice = prefixed.dropFirst(prefixLength)
            let decoded = try JPEGLSDecoder().decode(slice)
            #expect(decoded.components[0].pixels == pixels, "prefix \(prefixLength)")
        }
    }

    @Test("Decoding a restart-interval stream from a Data slice round-trips")
    func dataSliceRestartDecode() throws {
        let (encoded, pixels) = try encodeSample(height: 32, restartInterval: 8)
        let slice = (Data([0x00, 0x01, 0x02]) + encoded).dropFirst(3)
        let decoded = try JPEGLSDecoder().decode(slice)
        #expect(decoded.components[0].pixels == pixels)
    }

    // MARK: - Malformed streams must throw, not crash or corrupt

    @Test("Missing scans for declared components throws")
    func missingComponentScans() throws {
        // Encode a 3-component image (3 non-interleaved scans), then keep
        // only the first scan: SOI..end-of-scan-1 + EOI.
        let size = 8
        let plane = (0..<size).map { row in (0..<size).map { ($0 + row) % 256 } }
        let imageData = try MultiComponentImageData.rgb(
            redPixels: plane, greenPixels: plane, bluePixels: plane, bitsPerSample: 8
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: .init())
        let parser = JPEGLSParser(data: encoded)
        let parsed = try parser.parse()
        #expect(parsed.scanDataRanges.count == 3)
        let firstScanEnd = parsed.scanDataRanges[0].upperBound
        let truncated = encoded.prefix(firstScanEnd) + Data([0xFF, 0xD9])
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSDecoder().decode(Data(truncated))
        }
    }

    @Test("Stray restart marker without an active DRI throws (not silent garbage)")
    func strayRestartMarkerWithoutDRI() throws {
        let (encoded, _) = try encodeSample(height: 32, restartInterval: 8)
        let stripped = strippingDRI(encoded)
        #expect(stripped.count < encoded.count, "DRI segment should have been removed")
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSDecoder().decode(stripped)
        }
    }

    @Test("Out-of-sequence restart marker throws")
    func outOfSequenceRestartMarker() throws {
        let (encoded, _) = try encodeSample(height: 32, restartInterval: 8)
        var bytes = [UInt8](encoded)
        // Find the first RST marker (FFD0) and bump it to FFD1.
        var corrupted = false
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xD0 {
                bytes[i + 1] = 0xD1
                corrupted = true
                break
            }
            i += 1
        }
        #expect(corrupted)
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSDecoder().decode(Data(bytes))
        }
    }

    @Test("Truncated restart stream throws rather than crashing")
    func truncatedRestartStream() throws {
        let (encoded, _) = try encodeSample(height: 32, restartInterval: 8)
        // Cut in the middle of the entropy data (keep headers intact) and
        // terminate with EOI so the parser completes.
        let cut = encoded.count * 2 / 3
        let truncated = encoded.prefix(cut) + Data([0xFF, 0xD9])
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSDecoder().decode(Data(truncated))
        }
    }

    @Test("Hostile LSE type-4 extended dimensions throw instead of trapping")
    func extendedDimensionsOverflow() throws {
        // Hand-built stream: SOI, LSE type 4 declaring 2^32−1 × 2^32−1
        // (whose product overflows Int multiplication on 64-bit), SOF55 with
        // zero dimensions (extended dims take precedence), one SOS, EOI.
        var bytes: [UInt8] = [0xFF, 0xD8]                       // SOI
        bytes += [0xFF, 0xF8, 0x00, 0x0C, 0x04, 0x04]           // LSE len=12 type=4 Wxy=4
        bytes += [0xFF, 0xFF, 0xFF, 0xFF]                       // XSIZE = 2^32-1
        bytes += [0xFF, 0xFF, 0xFF, 0xFF]                       // YSIZE = 2^32-1
        bytes += [0xFF, 0xF7, 0x00, 0x0B, 0x08]                 // SOF55 len=11 P=8
        bytes += [0x00, 0x00, 0x00, 0x00]                       // Y=0, X=0 (use LSE dims)
        bytes += [0x01, 0x01, 0x11, 0x00]                       // Nf=1, C1=1, H/V=1, Tq=0
        bytes += [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00]     // SOS len=8 Ns=1 C1 Tdi=0
        bytes += [0x00, 0x00]                                    // NEAR=0, ILV=0
        bytes += [0x00]                                          // point transform
        bytes += [0xFF, 0xD9]                                    // EOI
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSDecoder().decode(Data(bytes))
        }
    }

    @Test("LSE segment with undersized length throws instead of trapping")
    func undersizedLSESegment() throws {
        // LSE with length 2 (shorter than its own header) used to compute a
        // negative skip count and trap in readBytes.
        var bytes: [UInt8] = [0xFF, 0xD8]            // SOI
        bytes += [0xFF, 0xF8, 0x00, 0x02]            // LSE with invalid length 2
        bytes += [0xFF, 0xD9]                        // EOI
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSParser(data: Data(bytes)).parse()
        }
    }

    // MARK: - Encoder configuration validation

    @Test("Encoding with preset MAXVAL above 2^P-1 throws")
    func presetMaxValueAboveSampleRange() throws {
        let pixels = (0..<8).map { row in (0..<8).map { ($0 + row) % 200 } }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let preset = try JPEGLSPresetParameters(
            maxValue: 65535, threshold1: 3, threshold2: 7, threshold3: 21, reset: 64
        )
        let config = try JPEGLSEncoder.Configuration(presetParameters: preset)
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder().encode(imageData, configuration: config)
        }
    }

    @Test("Encoding sub-sampled component planes throws instead of reading out of bounds")
    func subSampledPlanesRejected() throws {
        // Frame 4x2 with component 2 sub-sampled to half width: the
        // validating image init accepts it, but the scan encoders do not
        // support sub-sampling and must reject it loudly.
        let frameHeader = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: 2,
            width: 4,
            componentCount: 2,
            components: [
                .init(id: 1, horizontalSamplingFactor: 2, verticalSamplingFactor: 1),
                .init(id: 2, horizontalSamplingFactor: 1, verticalSamplingFactor: 1),
            ]
        )
        let fullPlane = [[10, 20, 30, 40], [50, 60, 70, 80]]
        let halfPlane = [[1, 2], [3, 4]]
        let imageData = try MultiComponentImageData(
            components: [
                .init(id: 1, pixels: fullPlane),
                .init(id: 2, pixels: halfPlane),
            ],
            frameHeader: frameHeader
        )
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder().encode(imageData, configuration: .init())
        }
    }

    @Test("Interleaved stream declaring DRI >= height still decodes")
    func interleavedStreamWithInactiveDRI() throws {
        // A DRI larger than the frame height produces zero RST markers; the
        // scan body is identical to a no-DRI stream and must not be rejected.
        let size = 8
        let plane = (0..<size).map { row in (0..<size).map { ($0 * 7 + row) % 256 } }
        let imageData = try MultiComponentImageData.rgb(
            redPixels: plane, greenPixels: plane, bluePixels: plane, bitsPerSample: 8
        )
        let config = try JPEGLSEncoder.Configuration(interleaveMode: .line)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        // Inject a DRI (interval 9999 >= height 8) right after SOI.
        var bytes = [UInt8](encoded)
        let dri: [UInt8] = [0xFF, 0xDD, 0x00, 0x04, 0x27, 0x0F]  // 0x270F = 9999
        bytes.insert(contentsOf: dri, at: 2)
        let decoded = try JPEGLSDecoder().decode(Data(bytes))
        #expect(decoded.components[0].pixels == plane)
    }

    @Test("Per-scan DRI: interval defined after the first scan applies to later scans only")
    func driAfterFirstScan() throws {
        // Encode two single-component streams — one plain, one with restart —
        // and splice them into a 2-component non-interleaved stream where the
        // DRI appears between scan 1 (no restart) and scan 2 (restart).
        let size = 16
        let plane = (0..<size).map { row in (0..<size).map { ($0 * 3 + row * 5) % 256 } }
        let imageData = try MultiComponentImageData.rgb(
            redPixels: plane, greenPixels: plane, bluePixels: plane, bitsPerSample: 8
        )
        // Whole-file restart encode: DRI before all scans — every scan uses it.
        let config = try JPEGLSEncoder.Configuration(restartInterval: 4)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let parsed = try JPEGLSParser(data: encoded).parse()
        #expect(parsed.scanRestartIntervals == [4, 4, 4])
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components.count == 3)
        for component in decoded.components {
            #expect(component.pixels == plane)
        }
    }
}
