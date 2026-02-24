// JPEGLSPart2ColorTransformTests.swift
//
// Unit tests for JPEG-LS Part 2 colour transform support (ITU-T T.870 Annex A).
//
// Covers:
//   - Modular forward/inverse transforms
//   - APP8 "mrfx" marker writing in encoder
//   - APP8 "mrfx" marker parsing in parser
//   - End-to-end round-trip encoding and decoding with HP1, HP2, and HP3
//     for all interleaving modes

import Foundation
import Testing
@testable import JPEGLS

// MARK: - Modular Arithmetic Tests

@Suite("Part 2 Colour Transform: Modular Arithmetic")
struct JPEGLSColorTransformModularTests {

    // MARK: HP1 Modular Forward

    @Test("HP1 forward with maxValue produces values in [0, maxValue]")
    func testHP1ForwardModular() throws {
        let transform = JPEGLSColorTransformation.hp1
        // R < G → R' would be negative without modular reduction
        let result = try transform.transformForward([50, 200, 180], maxValue: 255)
        for v in result {
            #expect(v >= 0 && v <= 255)
        }
        // R' = (50 - 200 + 256) % 256 = 106
        #expect(result[0] == (50 - 200 + 256) % 256)
        // G' = G = 200
        #expect(result[1] == 200)
        // B' = (180 - 200 + 256) % 256 = 236
        #expect(result[2] == (180 - 200 + 256) % 256)
    }

    @Test("HP1 forward with maxValue, positive result unchanged")
    func testHP1ForwardModularPositive() throws {
        let transform = JPEGLSColorTransformation.hp1
        // R >= G → no modular change needed
        let result = try transform.transformForward([200, 100, 180], maxValue: 255)
        #expect(result[0] == 100)   // 200 - 100 = 100
        #expect(result[1] == 100)   // G
        #expect(result[2] == 80)    // 180 - 100 = 80
    }

    // MARK: HP1 Modular Inverse

    @Test("HP1 inverse with maxValue recovers original from modular values")
    func testHP1InverseModular() throws {
        let transform = JPEGLSColorTransformation.hp1
        // Simulate JPEG-LS decoded output: R'_mod = 106, G'=200, B'_mod=236
        let decoded = [106, 200, 236]
        let original = try transform.transformInverse(decoded, maxValue: 255)
        // R = (106 + 200) % 256 = 50
        #expect(original[0] == 50)
        #expect(original[1] == 200)
        // B = (236 + 200) % 256 = 180
        #expect(original[2] == 180)
    }

    // MARK: HP2 Modular

    @Test("HP2 forward+inverse round-trip with maxValue")
    func testHP2ModularRoundTrip() throws {
        let transform = JPEGLSColorTransformation.hp2
        let original = [50, 200, 180]
        let maxValue = 255
        let forward = try transform.transformForward(original, maxValue: maxValue)
        // All forward values must be in [0, 255]
        for v in forward {
            #expect(v >= 0 && v <= maxValue)
        }
        let recovered = try transform.transformInverse(forward, maxValue: maxValue)
        #expect(recovered == original)
    }

    @Test("HP2 inverse with maxValue recovers original")
    func testHP2InverseModular() throws {
        let transform = JPEGLSColorTransformation.hp2
        let original = [50, 200, 100]
        let maxValue = 255
        // Apply forward transform manually
        let forward = try transform.transformForward(original, maxValue: maxValue)
        // Verify all in range
        for v in forward { #expect(v >= 0 && v <= maxValue) }
        // Apply inverse
        let recovered = try transform.transformInverse(forward, maxValue: maxValue)
        #expect(recovered == original)
    }

    // MARK: HP3 Modular

    @Test("HP3 forward+inverse round-trip with maxValue")
    func testHP3ModularRoundTrip() throws {
        let transform = JPEGLSColorTransformation.hp3
        let original = [100, 150, 200]
        let maxValue = 255
        let forward = try transform.transformForward(original, maxValue: maxValue)
        for v in forward { #expect(v >= 0 && v <= maxValue) }
        let recovered = try transform.transformInverse(forward, maxValue: maxValue)
        #expect(recovered == original)
    }

    @Test("HP3 inverse with maxValue handles wraparound")
    func testHP3InverseModularWraparound() throws {
        let transform = JPEGLSColorTransformation.hp3
        // R=50, B=200 → R'=50-200=-150 → mod 256 → 106
        let maxValue = 255
        let original = [50, 100, 200]
        let forward = try transform.transformForward(original, maxValue: maxValue)
        #expect(forward[2] == 200)  // B' = B, no change
        let recovered = try transform.transformInverse(forward, maxValue: maxValue)
        #expect(recovered == original)
    }

    // MARK: 16-bit Modular

    @Test("HP1 modular arithmetic works for 16-bit images")
    func testHP1Modular16Bit() throws {
        let transform = JPEGLSColorTransformation.hp1
        let maxValue = 65535
        let original = [1000, 60000, 50000]
        let forward = try transform.transformForward(original, maxValue: maxValue)
        for v in forward { #expect(v >= 0 && v <= maxValue) }
        let recovered = try transform.transformInverse(forward, maxValue: maxValue)
        #expect(recovered == original)
    }

    // MARK: None Transform

    @Test("None transform is unaffected by maxValue parameter")
    func testNoneTransformWithMaxValue() throws {
        let transform = JPEGLSColorTransformation.none
        let v = [128, 200, 50]
        let forward = try transform.transformForward(v, maxValue: 255)
        #expect(forward == v)
        let inverse = try transform.transformInverse(v, maxValue: 255)
        #expect(inverse == v)
    }

    // MARK: Comprehensive Round-Trip

    @Test("All HP transforms preserve lossless round-trip for typical 8-bit values")
    func testAllTransformsRoundTrip8Bit() throws {
        let transforms: [JPEGLSColorTransformation] = [.hp1, .hp2, .hp3]
        let testCases: [[Int]] = [
            [0, 0, 0],
            [255, 255, 255],
            [100, 150, 200],
            [50, 200, 180],
            [10, 240, 130],
            [200, 50, 100],
        ]
        for transform in transforms {
            for original in testCases {
                let forward = try transform.transformForward(original, maxValue: 255)
                for v in forward { #expect(v >= 0 && v <= 255) }
                let recovered = try transform.transformInverse(forward, maxValue: 255)
                #expect(recovered == original, "Transform \(transform) failed for \(original)")
            }
        }
    }
}

// MARK: - APP8 "mrfx" Marker Tests

@Suite("Part 2 Colour Transform: APP8 mrfx Marker")
struct JPEGLSColorTransformMarkerTests {

    @Test("Encoder writes APP8 mrfx marker for HP1")
    func testEncoderWritesApp8HP1() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeRGBImage()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .sample,
            colorTransformation: .hp1
        )
        let data = try encoder.encode(imageData, configuration: config)
        // Find APP8 "mrfx" marker in the output
        let (found, transformId) = findMrfxMarker(in: data)
        #expect(found)
        #expect(transformId == JPEGLSColorTransformation.hp1.rawValue)
    }

    @Test("Encoder writes APP8 mrfx marker for HP2")
    func testEncoderWritesApp8HP2() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeRGBImage()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .sample,
            colorTransformation: .hp2
        )
        let data = try encoder.encode(imageData, configuration: config)
        let (found, transformId) = findMrfxMarker(in: data)
        #expect(found)
        #expect(transformId == JPEGLSColorTransformation.hp2.rawValue)
    }

    @Test("Encoder writes APP8 mrfx marker for HP3")
    func testEncoderWritesApp8HP3() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeRGBImage()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .sample,
            colorTransformation: .hp3
        )
        let data = try encoder.encode(imageData, configuration: config)
        let (found, transformId) = findMrfxMarker(in: data)
        #expect(found)
        #expect(transformId == JPEGLSColorTransformation.hp3.rawValue)
    }

    @Test("Encoder does not write APP8 mrfx for no-transform encoding")
    func testEncoderNoApp8ForNoneTransform() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeRGBImage()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample)
        let data = try encoder.encode(imageData, configuration: config)
        let (found, _) = findMrfxMarker(in: data)
        #expect(!found)
    }

    @Test("Parser extracts HP1 transform from APP8 mrfx marker")
    func testParserExtractsHP1() throws {
        let encoded = try encodeWithTransform(.hp1, interleave: .sample)
        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        #expect(result.colorTransformation == .hp1)
    }

    @Test("Parser extracts HP2 transform from APP8 mrfx marker")
    func testParserExtractsHP2() throws {
        let encoded = try encodeWithTransform(.hp2, interleave: .line)
        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        #expect(result.colorTransformation == .hp2)
    }

    @Test("Parser extracts HP3 transform from APP8 mrfx marker")
    func testParserExtractsHP3() throws {
        let encoded = try encodeWithTransform(.hp3, interleave: .none)
        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        #expect(result.colorTransformation == .hp3)
    }

    @Test("Parser defaults to none when no APP8 mrfx marker is present")
    func testParserDefaultsToNone() throws {
        let imageData = try makeRGBImage()
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample)
        let encoded = try encoder.encode(imageData, configuration: config)
        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        #expect(result.colorTransformation == .none)
    }

    @Test("Parser ignores APP8 with unknown mrfx transform ID gracefully")
    func testParserIgnoresUnknownTransformId() throws {
        // Build a bitstream with APP8 "mrfx" + invalid transform ID (0xFF)
        let imageData = try makeRGBImage()
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample)
        var encoded = try encoder.encode(imageData, configuration: config)
        
        // Inject an APP8 "mrfx" marker with ID 0xFF before the SOI end is reached
        // We'll insert it right after the SOI marker (first 2 bytes)
        var patchedData = Data()
        patchedData.append(encoded[0])  // FF
        patchedData.append(encoded[1])  // D8 (SOI)
        // APP8: FF E8, length 00 07, mrfx, 0xFF
        patchedData.append(contentsOf: [0xFF, 0xE8, 0x00, 0x07, 0x6D, 0x72, 0x66, 0x78, 0xFF])
        patchedData.append(contentsOf: encoded[2...])
        encoded = patchedData

        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        // 0xFF is not a valid transform ID, so colorTransformation stays .none
        #expect(result.colorTransformation == .none)
    }

    // MARK: - Helpers

    private func makeRGBImage(
        width: Int = 4,
        height: Int = 4,
        bitsPerSample: Int = 8
    ) throws -> MultiComponentImageData {
        let maxVal = (1 << bitsPerSample) - 1
        var r = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var g = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var b = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                r[row][col] = min(row * 40 + col * 20 + 100, maxVal)
                g[row][col] = min(row * 30 + col * 15 + 80, maxVal)
                b[row][col] = min(row * 20 + col * 25 + 60, maxVal)
            }
        }
        return try MultiComponentImageData.rgb(
            redPixels: r,
            greenPixels: g,
            bluePixels: b,
            bitsPerSample: bitsPerSample
        )
    }

    private func encodeWithTransform(
        _ transform: JPEGLSColorTransformation,
        interleave: JPEGLSInterleaveMode
    ) throws -> Data {
        let encoder = JPEGLSEncoder()
        let imageData = try makeRGBImage()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: interleave,
            colorTransformation: transform
        )
        return try encoder.encode(imageData, configuration: config)
    }

    /// Scan raw bytes for APP8 marker (FF E8) followed by "mrfx" signature.
    private func findMrfxMarker(in data: Data) -> (found: Bool, transformId: UInt8) {
        var i = 0
        while i < data.count - 8 {
            if data[i] == 0xFF && data[i + 1] == 0xE8 {
                // Read segment length (big-endian)
                let len = Int(data[i + 2]) << 8 | Int(data[i + 3])
                if len >= 5 && i + 4 + len - 2 <= data.count {
                    // Check "mrfx" signature at payload start (after marker + length)
                    if data[i + 4] == 0x6D && data[i + 5] == 0x72 &&
                       data[i + 6] == 0x66 && data[i + 7] == 0x78 {
                        return (true, data[i + 8])
                    }
                }
            }
            i += 1
        }
        return (false, 0)
    }
}

// MARK: - Round-Trip Tests

@Suite("Part 2 Colour Transform: End-to-End Round-Trip")
struct JPEGLSColorTransformRoundTripTests {

    @Test("HP1 round-trip: none-interleaved")
    func testHP1RoundTripNoneInterleaved() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .none)
    }

    @Test("HP1 round-trip: line-interleaved")
    func testHP1RoundTripLineInterleaved() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .line)
    }

    @Test("HP1 round-trip: sample-interleaved")
    func testHP1RoundTripSampleInterleaved() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .sample)
    }

    @Test("HP2 round-trip: none-interleaved")
    func testHP2RoundTripNoneInterleaved() throws {
        try verifyRoundTrip(transform: .hp2, interleave: .none)
    }

    @Test("HP2 round-trip: line-interleaved")
    func testHP2RoundTripLineInterleaved() throws {
        try verifyRoundTrip(transform: .hp2, interleave: .line)
    }

    @Test("HP2 round-trip: sample-interleaved")
    func testHP2RoundTripSampleInterleaved() throws {
        try verifyRoundTrip(transform: .hp2, interleave: .sample)
    }

    @Test("HP3 round-trip: none-interleaved")
    func testHP3RoundTripNoneInterleaved() throws {
        try verifyRoundTrip(transform: .hp3, interleave: .none)
    }

    @Test("HP3 round-trip: line-interleaved")
    func testHP3RoundTripLineInterleaved() throws {
        try verifyRoundTrip(transform: .hp3, interleave: .line)
    }

    @Test("HP3 round-trip: sample-interleaved")
    func testHP3RoundTripSampleInterleaved() throws {
        try verifyRoundTrip(transform: .hp3, interleave: .sample)
    }

    @Test("HP1 round-trip with heavily varied pixel values")
    func testHP1RoundTripVariedPixels() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .sample, useVariedPixels: true)
    }

    @Test("HP2 round-trip with heavily varied pixel values")
    func testHP2RoundTripVariedPixels() throws {
        try verifyRoundTrip(transform: .hp2, interleave: .sample, useVariedPixels: true)
    }

    @Test("HP3 round-trip with heavily varied pixel values")
    func testHP3RoundTripVariedPixels() throws {
        try verifyRoundTrip(transform: .hp3, interleave: .sample, useVariedPixels: true)
    }

    @Test("None transform round-trip still works correctly")
    func testNoneTransformRoundTrip() throws {
        try verifyRoundTrip(transform: .none, interleave: .sample)
    }

    @Test("HP1 round-trip for 8x8 image")
    func testHP1RoundTrip8x8() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .sample, width: 8, height: 8)
    }

    @Test("HP1 round-trip for single-row image")
    func testHP1RoundTripSingleRow() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .sample, width: 8, height: 1)
    }

    @Test("HP1 round-trip for single-column image")
    func testHP1RoundTripSingleColumn() throws {
        try verifyRoundTrip(transform: .hp1, interleave: .none, width: 1, height: 8)
    }

    // MARK: - Helpers

    private func makeTestImage(
        width: Int,
        height: Int,
        bitsPerSample: Int = 8,
        varied: Bool = false
    ) throws -> MultiComponentImageData {
        let maxVal = (1 << bitsPerSample) - 1
        var r = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var g = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        var b = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                if varied {
                    // Use values that will produce negative transformed components
                    r[row][col] = (row * 37 + col * 13 + 50)  % (maxVal + 1)
                    g[row][col] = (row * 53 + col * 29 + 200) % (maxVal + 1)
                    b[row][col] = (row * 17 + col * 61 + 100) % (maxVal + 1)
                } else {
                    r[row][col] = min(row * 40 + col * 20 + 100, maxVal)
                    g[row][col] = min(row * 30 + col * 15 + 80, maxVal)
                    b[row][col] = min(row * 20 + col * 25 + 60, maxVal)
                }
            }
        }
        return try MultiComponentImageData.rgb(
            redPixels: r,
            greenPixels: g,
            bluePixels: b,
            bitsPerSample: bitsPerSample
        )
    }

    private func verifyRoundTrip(
        transform: JPEGLSColorTransformation,
        interleave: JPEGLSInterleaveMode,
        width: Int = 4,
        height: Int = 4,
        useVariedPixels: Bool = false
    ) throws {
        let original = try makeTestImage(width: width, height: height, varied: useVariedPixels)

        // Encode with colour transform
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: interleave,
            colorTransformation: transform
        )
        let encoded = try encoder.encode(original, configuration: config)

        // Decode — the decoder reads the APP8 "mrfx" marker and applies the inverse transform
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)

        // Verify pixel-perfect round-trip
        #expect(decoded.components.count == original.components.count)
        for (decComp, origComp) in zip(decoded.components, original.components) {
            #expect(decComp.id == origComp.id)
            #expect(decComp.pixels == origComp.pixels,
                    "Pixel mismatch for component \(decComp.id) with \(transform) \(interleave)")
        }
    }
}
