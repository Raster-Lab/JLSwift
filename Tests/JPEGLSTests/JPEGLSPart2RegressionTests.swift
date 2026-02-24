/// Phase 11.5: Part 2 Performance Regression Tests
///
/// Verifies that Part 2 codepaths (colour transforms, mapping tables) do not regress
/// the performance of Part 1 codepaths and remain within acceptable time thresholds.
///
/// **Colour transforms (Phase 11.4)**: HP1/HP2/HP3 are measured to ensure the
/// forward transform (encode path) and inverse transform (decode path) add only a
/// small constant overhead compared to the baseline no-transform path.
///
/// **Mapping tables (Phase 11.2)**: Round-trip encode/decode with a 256-entry
/// mapping table is validated to complete within the threshold.
///
/// **Threshold policy**: 10× multiplier is used (consistent with
/// `JPEGLSPerformanceRegressionTests`) to avoid false failures on shared CI runners.

import Testing
import Foundation
@testable import JPEGLS

@Suite("Phase 11.5: Part 2 Performance Regression Tests")
struct JPEGLSPart2RegressionTests {

    // MARK: - Configuration

    private static let regressionThresholdMultiplier: Double = 10.0
    private static let iterations = 5

    // MARK: - Baselines (x86_64 Linux CI)

    /// Baseline: encode 256×256 8-bit RGB with a colour transform (ms)
    private static let baselineEncodeRGBWithTransform: Double = 100.0

    /// Baseline: decode 256×256 8-bit RGB with a colour transform (ms)
    private static let baselineDecodeRGBWithTransform: Double = 100.0

    /// Baseline: full round-trip 256×256 8-bit RGB with a colour transform (ms)
    private static let baselineRoundTripRGBWithTransform: Double = 200.0

    /// Baseline: full round-trip 64×64 8-bit grayscale with mapping table (ms)
    private static let baselineRoundTripWithMappingTable: Double = 50.0

    // MARK: - Test Image Helpers

    /// Generate a synthetic 256×256 RGB image for benchmark use.
    private func makeRGBImage(width: Int = 256, height: Int = 256) throws -> MultiComponentImageData {
        let maxValue = 255
        var red:   [[Int]] = []
        var green: [[Int]] = []
        var blue:  [[Int]] = []

        for row in 0..<height {
            var r: [Int] = []; var g: [Int] = []; var b: [Int] = []
            for col in 0..<width {
                r.append((row * 31 + col * 37 + 13) % (maxValue + 1))
                g.append((row * 41 + col * 29 + 71) % (maxValue + 1))
                b.append((row * 17 + col * 53 + 97) % (maxValue + 1))
            }
            red.append(r); green.append(g); blue.append(b)
        }

        return try MultiComponentImageData.rgb(
            redPixels: red, greenPixels: green, bluePixels: blue,
            bitsPerSample: 8
        )
    }

    /// Generate a synthetic 64×64 grayscale image whose pixel values lie
    /// entirely within the 256 entries of a mapping table.
    private func makeGrayscaleImageForMappingTable(
        width: Int = 64,
        height: Int = 64
    ) throws -> MultiComponentImageData {
        var pixels: [[Int]] = []
        for row in 0..<height {
            var row_pixels: [Int] = []
            for col in 0..<width {
                row_pixels.append((row * 31 + col * 37) % 256)
            }
            pixels.append(row_pixels)
        }
        return try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
    }

    // MARK: - Helpers

    /// Measure average encoding time across iterations.
    private func measureEncode(
        imageData: MultiComponentImageData,
        colorTransformation: JPEGLSColorTransformation = .none,
        interleaveMode: JPEGLSInterleaveMode = .none
    ) throws -> Double {
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: interleaveMode,
            colorTransformation: colorTransformation
        )

        // Warm-up
        _ = try encoder.encode(imageData, configuration: config)

        var times: [Double] = []
        for _ in 0..<Self.iterations {
            let start = DispatchTime.now()
            _ = try encoder.encode(imageData, configuration: config)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        return times.reduce(0, +) / Double(times.count)
    }

    /// Measure average decoding time across iterations (pre-encodes once).
    private func measureDecode(
        imageData: MultiComponentImageData,
        colorTransformation: JPEGLSColorTransformation = .none,
        interleaveMode: JPEGLSInterleaveMode = .none
    ) throws -> Double {
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: interleaveMode,
            colorTransformation: colorTransformation
        )
        let encoded = try encoder.encode(imageData, configuration: config)
        let decoder = JPEGLSDecoder()

        // Warm-up
        _ = try decoder.decode(encoded)

        var times: [Double] = []
        for _ in 0..<Self.iterations {
            let start = DispatchTime.now()
            _ = try decoder.decode(encoded)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        return times.reduce(0, +) / Double(times.count)
    }

    // MARK: - Colour Transform Encoding Regression (Phase 11.4)

    @Test("Regression: Encode 256×256 RGB with HP1 transform within baseline threshold")
    func regressionEncodeHP1() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureEncode(imageData: imageData, colorTransformation: .hp1)
        let threshold = Self.baselineEncodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Encode 256×256 RGB HP1")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineEncodeRGBWithTransform)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)×)")

        #expect(
            averageMs < threshold,
            "Encode 256×256 RGB HP1 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    @Test("Regression: Encode 256×256 RGB with HP2 transform within baseline threshold")
    func regressionEncodeHP2() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureEncode(imageData: imageData, colorTransformation: .hp2)
        let threshold = Self.baselineEncodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Encode 256×256 RGB HP2")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Encode 256×256 RGB HP2 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    @Test("Regression: Encode 256×256 RGB with HP3 transform within baseline threshold")
    func regressionEncodeHP3() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureEncode(imageData: imageData, colorTransformation: .hp3)
        let threshold = Self.baselineEncodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Encode 256×256 RGB HP3")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Encode 256×256 RGB HP3 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    // MARK: - Colour Transform Decoding Regression (Phase 11.4)

    @Test("Regression: Decode 256×256 RGB with HP1 transform within baseline threshold")
    func regressionDecodeHP1() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureDecode(imageData: imageData, colorTransformation: .hp1)
        let threshold = Self.baselineDecodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Decode 256×256 RGB HP1")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Decode 256×256 RGB HP1 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    @Test("Regression: Decode 256×256 RGB with HP2 transform within baseline threshold")
    func regressionDecodeHP2() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureDecode(imageData: imageData, colorTransformation: .hp2)
        let threshold = Self.baselineDecodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Decode 256×256 RGB HP2")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Decode 256×256 RGB HP2 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    @Test("Regression: Decode 256×256 RGB with HP3 transform within baseline threshold")
    func regressionDecodeHP3() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureDecode(imageData: imageData, colorTransformation: .hp3)
        let threshold = Self.baselineDecodeRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Decode 256×256 RGB HP3")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Decode 256×256 RGB HP3 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    // MARK: - Colour Transform Round-Trip Regression (Phase 11.4)

    @Test("Regression: Round-trip 256×256 RGB with HP1 within baseline threshold")
    func regressionRoundTripHP1() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureRoundTrip(imageData: imageData, colorTransformation: .hp1)
        let threshold = Self.baselineRoundTripRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Round-trip 256×256 RGB HP1")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Round-trip 256×256 RGB HP1 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    @Test("Regression: Round-trip 256×256 RGB with HP3 within baseline threshold")
    func regressionRoundTripHP3() throws {
        let imageData = try makeRGBImage()
        let averageMs = try measureRoundTrip(imageData: imageData, colorTransformation: .hp3)
        let threshold = Self.baselineRoundTripRGBWithTransform * Self.regressionThresholdMultiplier

        print("Regression: Round-trip 256×256 RGB HP3")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms")

        #expect(
            averageMs < threshold,
            "Round-trip 256×256 RGB HP3 took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    // MARK: - Part 2 Does Not Regress Part 1 (no-transform overhead)

    @Test("Colour transform overhead vs no-transform is within acceptable bounds")
    func regressionTransformOverheadBound() throws {
        let imageData = try makeRGBImage()

        let baseMs   = try measureEncode(imageData: imageData, colorTransformation: .none)
        let hp2Ms    = try measureEncode(imageData: imageData, colorTransformation: .hp2)

        // The colour-transform path must not be more than 5× slower than the
        // no-transform path (generous to accommodate CI noise).
        let overheadFactor = hp2Ms / max(baseMs, 0.001)

        print("Part 2 overhead: no-transform=\(String(format: "%.2f", baseMs)) ms, HP2=\(String(format: "%.2f", hp2Ms)) ms, factor=\(String(format: "%.2f", overheadFactor))×")

        #expect(
            overheadFactor < 5.0,
            "HP2 encode is \(String(format: "%.2f", overheadFactor))× slower than no-transform; Part 2 regresses Part 1 performance"
        )
    }

    // MARK: - Mapping Table Round-Trip Regression (Phase 11.2)

    @Test("Regression: Round-trip 64×64 grayscale with 256-entry mapping table within baseline threshold")
    func regressionRoundTripMappingTable() throws {
        let imageData = try makeGrayscaleImageForMappingTable()
        let encoder = JPEGLSEncoder()
        let decoder = JPEGLSDecoder()

        // Build identity mapping table and its LSE segment
        let identityEntries = Array(0..<256)
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: identityEntries)
        let tableWriter = JPEGLSBitstreamWriter()
        encoder.writeMappingTable(table, to: tableWriter)
        let lseData = try tableWriter.getData()

        // Produce a base-encoded bitstream once; patching is deterministic so we
        // can reuse the same patched data for all timing iterations.
        let baseEncoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        let patched = try patchBitstreamWithTableAndReference(
            encoded: baseEncoded, lseData: lseData, tableID: 1
        )

        // Warm-up
        _ = try decoder.decode(patched)

        var times: [Double] = []
        for _ in 0..<Self.iterations {
            let start = DispatchTime.now()
            _ = try decoder.decode(patched)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }

        let averageMs = times.reduce(0, +) / Double(times.count)
        let threshold = Self.baselineRoundTripWithMappingTable * Self.regressionThresholdMultiplier

        print("Regression: Decode 64×64 grayscale with identity mapping table")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineRoundTripWithMappingTable)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)×)")

        #expect(
            averageMs < threshold,
            "Decode with mapping table took \(String(format: "%.2f", averageMs)) ms, exceeding threshold"
        )
    }

    // MARK: - Bitstream patch helper (mirrors MappingTableDecoderTests)

    /// Insert an LSE segment before the first SOS marker and set the component's
    /// mapping table ID (Tdi) to `tableID`.
    private func patchBitstreamWithTableAndReference(
        encoded: Data,
        lseData: Data,
        tableID: UInt8
    ) throws -> Data {
        var bytes = Array(encoded)

        // Find SOS marker
        var sosPos: Int?
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDA { sosPos = i; break }
            i += 1
        }
        guard let pos = sosPos else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS marker not found")
        }

        // Splice LSE before SOS
        bytes = Array(bytes.prefix(pos)) + Array(lseData) + Array(bytes.suffix(from: pos))

        // Re-find SOS after splice
        sosPos = nil; i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDA { sosPos = i; break }
            i += 1
        }
        guard let newPos = sosPos else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS marker not found after splice")
        }

        // Patch first component's Tdi field (FF DA | Ll(2) | Ns(1) | Cs(1) | Td)
        let tdOffset = newPos + 2 + 2 + 1 + 1
        guard tdOffset < bytes.count else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS too short to patch")
        }
        bytes[tdOffset] = tableID

        return Data(bytes)
    }

    // MARK: - Round-trip measurement helper

    private func measureRoundTrip(
        imageData: MultiComponentImageData,
        colorTransformation: JPEGLSColorTransformation
    ) throws -> Double {
        let encoder = JPEGLSEncoder()
        let decoder = JPEGLSDecoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .none,
            colorTransformation: colorTransformation
        )

        // Warm-up
        let encoded = try encoder.encode(imageData, configuration: config)
        _ = try decoder.decode(encoded)

        var times: [Double] = []
        for _ in 0..<Self.iterations {
            let start = DispatchTime.now()
            let enc = try encoder.encode(imageData, configuration: config)
            _ = try decoder.decode(enc)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        return times.reduce(0, +) / Double(times.count)
    }
}
