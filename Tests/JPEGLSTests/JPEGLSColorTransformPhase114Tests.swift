/// Tests for Phase 11.4: APP8 "mrfx" colour-transform marker support
///
/// Covers:
///   - `transformForward`/`transformInverse` with `maxValue` (modular arithmetic)
///   - Encoder writes APP8 "mrfx" marker when a transform is configured
///   - Parser reads APP8 "mrfx" marker and stores `colorTransformation`
///   - Decoder applies inverse transform; full encode→decode round-trip

import Testing
import Foundation
@testable import JPEGLS

@Suite("Phase 11.4: APP8 Colour Transform Tests")
struct JPEGLSColorTransformPhase114Tests {

    // MARK: - Modular arithmetic in transformForward / transformInverse

    @Test("HP1 forward with maxValue keeps values in [0, maxValue]")
    func testHP1ForwardModular() throws {
        let t = JPEGLSColorTransformation.hp1
        let maxValue = 255

        // R=50, G=200 → R'=(50-200+256)%256 = 106
        let result = try t.transformForward([50, 200, 100], maxValue: maxValue)
        #expect(result[0] == 106)  // (50 - 200 + 256) % 256
        #expect(result[1] == 200)  // G unchanged
        #expect(result[2] == 156)  // (100 - 200 + 256) % 256
        #expect(result.allSatisfy { $0 >= 0 && $0 <= maxValue })
    }

    @Test("HP1 inverse with maxValue recovers original values")
    func testHP1InverseModular() throws {
        let t = JPEGLSColorTransformation.hp1
        let maxValue = 255

        // Forward then inverse must be identity
        let original = [50, 200, 100]
        let transformed = try t.transformForward(original, maxValue: maxValue)
        let recovered = try t.transformInverse(transformed, maxValue: maxValue)
        #expect(recovered == original)
    }

    @Test("HP2 forward with maxValue keeps values in [0, maxValue]")
    func testHP2ForwardModular() throws {
        let t = JPEGLSColorTransformation.hp2
        let maxValue = 255

        // R=10, G=200, B=50
        let result = try t.transformForward([10, 200, 50], maxValue: maxValue)
        #expect(result.allSatisfy { $0 >= 0 && $0 <= maxValue })
    }

    @Test("HP2 round-trip with maxValue is lossless")
    func testHP2RoundTripModular() throws {
        let t = JPEGLSColorTransformation.hp2
        let maxValue = 255

        for r in stride(from: 0, through: 255, by: 51) {
            for g in stride(from: 0, through: 255, by: 51) {
                for b in stride(from: 0, through: 255, by: 51) {
                    let original = [r, g, b]
                    let transformed = try t.transformForward(original, maxValue: maxValue)
                    let recovered = try t.transformInverse(transformed, maxValue: maxValue)
                    #expect(recovered == original,
                            "HP2 round-trip failed for (\(r),\(g),\(b))")
                }
            }
        }
    }

    @Test("HP3 round-trip with maxValue is lossless")
    func testHP3RoundTripModular() throws {
        let t = JPEGLSColorTransformation.hp3
        let maxValue = 255

        for r in stride(from: 0, through: 255, by: 51) {
            for g in stride(from: 0, through: 255, by: 51) {
                for b in stride(from: 0, through: 255, by: 51) {
                    let original = [r, g, b]
                    let transformed = try t.transformForward(original, maxValue: maxValue)
                    let recovered = try t.transformInverse(transformed, maxValue: maxValue)
                    #expect(recovered == original,
                            "HP3 round-trip failed for (\(r),\(g),\(b))")
                }
            }
        }
    }

    @Test("transformForward without maxValue is backward-compatible (no modular reduction)")
    func testBackwardCompatibilityNoMaxValue() throws {
        let t = JPEGLSColorTransformation.hp1
        // Without maxValue the raw (possibly negative) value is returned
        let result = try t.transformForward([50, 200, 100])
        #expect(result[0] == 50 - 200)  // -150 (negative, no wrap)
        #expect(result[1] == 200)
        #expect(result[2] == 100 - 200)  // -100 (negative, no wrap)
    }

    @Test("HP1 round-trip without maxValue is still lossless for non-wrapping values")
    func testHP1RoundTripNoMaxValue() throws {
        let t = JPEGLSColorTransformation.hp1
        let original = [200, 100, 150]  // R > G and B > G → no negative values
        let transformed = try t.transformForward(original)
        let recovered = try t.transformInverse(transformed)
        #expect(recovered == original)
    }

    @Test("modular arithmetic on 16-bit image (maxValue=65535)")
    func testModularArithmetic16bit() throws {
        let t = JPEGLSColorTransformation.hp1
        let maxValue = 65535

        let original = [1000, 60000, 50000]
        let transformed = try t.transformForward(original, maxValue: maxValue)
        let recovered = try t.transformInverse(transformed, maxValue: maxValue)
        #expect(recovered == original)
        #expect(transformed.allSatisfy { $0 >= 0 && $0 <= maxValue })
    }

    // MARK: - APP8 "mrfx" marker in the encoder output

    @Test("Encoder writes APP8 mrfx marker when colorTransformation != none")
    func testEncoderWritesApp8MrfxMarker() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeSmallRGBImage()

        for ct in [JPEGLSColorTransformation.hp1, .hp2, .hp3] {
            let config = try JPEGLSEncoder.Configuration(
                near: 0,
                interleaveMode: .none,
                colorTransformation: ct
            )
            let data = try encoder.encode(imageData, configuration: config)

            // Locate APP8 "mrfx" segment: FF E8 xx xx 6D 72 66 78 id
            let marker: [UInt8] = [0xFF, 0xE8]
            let mrfx:   [UInt8] = [0x6D, 0x72, 0x66, 0x78]

            var found = false
            for i in 0..<(data.count - 8) {
                if data[i] == marker[0] && data[i + 1] == marker[1] {
                    // Check for "mrfx" after the 2-byte length field
                    if data[i + 4] == mrfx[0] && data[i + 5] == mrfx[1]
                        && data[i + 6] == mrfx[2] && data[i + 7] == mrfx[3]
                    {
                        #expect(data[i + 8] == ct.rawValue,
                                "Transform ID mismatch for \(ct)")
                        found = true
                        break
                    }
                }
            }
            #expect(found, "APP8 mrfx marker not found for \(ct)")
        }
    }

    @Test("Encoder does NOT write APP8 mrfx marker for .none transform")
    func testEncoderSkipsApp8ForNoneTransform() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeSmallRGBImage()
        let config = try JPEGLSEncoder.Configuration(near: 0)
        let data = try encoder.encode(imageData, configuration: config)

        // Should not contain 0xFF 0xE8
        for i in 0..<(data.count - 1) {
            if data[i] == 0xFF && data[i + 1] == 0xE8 {
                Issue.record("Unexpected APP8 marker at offset \(i) for .none transform")
            }
        }
    }

    // MARK: - Parser reads APP8 "mrfx" and sets colorTransformation

    @Test("Parser extracts colorTransformation from APP8 mrfx marker")
    func testParserExtractsColorTransformation() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeSmallRGBImage()

        for ct in [JPEGLSColorTransformation.hp1, .hp2, .hp3] {
            let config = try JPEGLSEncoder.Configuration(
                near: 0,
                interleaveMode: .none,
                colorTransformation: ct
            )
            let data = try encoder.encode(imageData, configuration: config)

            let parser = JPEGLSParser(data: data)
            let result = try parser.parse()
            #expect(result.colorTransformation == ct,
                    "Expected \(ct) but got \(result.colorTransformation)")
        }
    }

    @Test("Parser returns .none colorTransformation when no APP8 marker present")
    func testParserDefaultsToNone() throws {
        let encoder = JPEGLSEncoder()
        let imageData = try makeSmallRGBImage()
        let config = try JPEGLSEncoder.Configuration(near: 0)
        let data = try encoder.encode(imageData, configuration: config)

        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        #expect(result.colorTransformation == .none)
    }

    // MARK: - Full encode → decode round-trip with colour transform

    @Test("HP1 colour transform round-trip (none-interleaved) recovers original pixels")
    func testHP1RoundTripNoneInterleaved() throws {
        try assertRoundTrip(transform: .hp1, interleave: .none)
    }

    @Test("HP2 colour transform round-trip (none-interleaved) recovers original pixels")
    func testHP2RoundTripNoneInterleaved() throws {
        try assertRoundTrip(transform: .hp2, interleave: .none)
    }

    @Test("HP3 colour transform round-trip (none-interleaved) recovers original pixels")
    func testHP3RoundTripNoneInterleaved() throws {
        try assertRoundTrip(transform: .hp3, interleave: .none)
    }

    @Test("HP1 colour transform round-trip (line-interleaved) recovers original pixels")
    func testHP1RoundTripLineInterleaved() throws {
        try assertRoundTrip(transform: .hp1, interleave: .line)
    }

    @Test("HP2 colour transform round-trip (sample-interleaved) recovers original pixels")
    func testHP2RoundTripSampleInterleaved() throws {
        try assertRoundTrip(transform: .hp2, interleave: .sample)
    }

    @Test("HP3 colour transform round-trip (line-interleaved) recovers original pixels")
    func testHP3RoundTripLineInterleaved() throws {
        try assertRoundTrip(transform: .hp3, interleave: .line)
    }

    @Test("HP1 colour transform round-trip with edge pixel values (0 and 255)")
    func testHP1RoundTripEdgeValues() throws {
        let encoder = JPEGLSEncoder()
        let decoder = JPEGLSDecoder()

        // Image with all extreme values
        let red   = [[0,   255, 0],
                     [255, 0,   128]]
        let green = [[255, 0,   128],
                     [0,   255, 64]]
        let blue  = [[128, 64,  255],
                     [192, 32,  0]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red, greenPixels: green, bluePixels: blue,
            bitsPerSample: 8
        )
        let config = try JPEGLSEncoder.Configuration(
            near: 0, interleaveMode: .none,
            colorTransformation: .hp1
        )
        let encoded = try encoder.encode(imageData, configuration: config)
        let decoded = try decoder.decode(encoded)

        #expect(decoded.components[0].pixels == red)
        #expect(decoded.components[1].pixels == green)
        #expect(decoded.components[2].pixels == blue)
    }

    // MARK: - Helpers

    /// Create a small 4×2 RGB test image with varied pixel values.
    private func makeSmallRGBImage() throws -> MultiComponentImageData {
        let red   = [[100, 50,  200, 10],
                     [255, 0,   128, 75]]
        let green = [[150, 200, 100, 50],
                     [0,   255, 64,  190]]
        let blue  = [[200, 150, 50,  250],
                     [128, 100, 200, 30]]

        return try MultiComponentImageData.rgb(
            redPixels: red, greenPixels: green, bluePixels: blue,
            bitsPerSample: 8
        )
    }

    private func assertRoundTrip(
        transform: JPEGLSColorTransformation,
        interleave: JPEGLSInterleaveMode
    ) throws {
        let encoder = JPEGLSEncoder()
        let decoder = JPEGLSDecoder()
        let imageData = try makeSmallRGBImage()

        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: interleave,
            colorTransformation: transform
        )
        let encoded = try encoder.encode(imageData, configuration: config)
        let decoded = try decoder.decode(encoded)

        let originalComponents = imageData.components
        let decodedComponents  = decoded.components

        #expect(originalComponents.count == decodedComponents.count)
        for idx in 0..<originalComponents.count {
            #expect(
                decodedComponents[idx].pixels == originalComponents[idx].pixels,
                "\(transform) \(interleave)-interleaved: component \(idx) mismatch"
            )
        }
    }
}
