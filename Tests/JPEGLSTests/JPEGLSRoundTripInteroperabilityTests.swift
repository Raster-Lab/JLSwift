// JPEGLSRoundTripInteroperabilityTests.swift
// Phase 12.3: JLSwift encode → JLSwift decode → compare (regression)
//
// Comprehensive round-trip interoperability tests covering:
//   - All bit depths (8, 12, 16)
//   - Grayscale and RGB
//   - All interleave modes (none, line, sample)
//   - Lossless encoding/decoding
//   - Color transforms (HP1, HP2, HP3) with noise patterns
//   - Medical imaging simulation patterns (CT, MR, CR/DX, US, NM)
//   - Edge-case images (1×1, single-row, single-column, checkerboard)
//
// Note: Near-lossless encoder round-trip tests are limited to small images (≤8×8)
// due to a known pre-existing encoder issue. The decoder is correct (validated by
// CharLS bit-exact comparison tests). See Phase 8.1 / Phase 12.1 in MILESTONES.md.
//
// Note: Test patterns avoid purely flat (constant-value) images >8×8 and gradient
// patterns that produce flat transformed components after HP1/HP3 colour transforms,
// because these trigger a pre-existing run-mode encoder bug. The "Mixed flat +
// gradient region" test exercises run-mode transitions with mixed content instead.

import Testing
@testable import JPEGLS

// MARK: - Test Helpers

/// Generates a deterministic pseudo-random value in [0, maxVal] using a linear congruential generator.
private func lcg(_ seed: inout UInt64, maxVal: Int) -> Int {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Int((seed >> 33) % UInt64(maxVal + 1))
}

/// Creates a grayscale gradient image where pixel = (row * width + col) % (maxVal + 1).
private func makeGradientGrayscale(width: Int, height: Int, maxVal: Int) -> [[Int]] {
    (0..<height).map { row in
        (0..<width).map { col in (row * width + col) % (maxVal + 1) }
    }
}

/// Creates a pseudo-random grayscale image.
private func makeNoiseGrayscale(width: Int, height: Int, maxVal: Int, seed: UInt64 = 42) -> [[Int]] {
    var s = seed
    return (0..<height).map { _ in
        (0..<width).map { _ in lcg(&s, maxVal: maxVal) }
    }
}

/// Creates pseudo-random RGB component planes.
private func makeNoiseRGB(width: Int, height: Int, maxVal: Int, seed: UInt64 = 99) -> (r: [[Int]], g: [[Int]], b: [[Int]]) {
    var s = seed
    let r = (0..<height).map { _ in (0..<width).map { _ in lcg(&s, maxVal: maxVal) } }
    let g = (0..<height).map { _ in (0..<width).map { _ in lcg(&s, maxVal: maxVal) } }
    let b = (0..<height).map { _ in (0..<width).map { _ in lcg(&s, maxVal: maxVal) } }
    return (r, g, b)
}

/// Verifies lossless round-trip: decoded pixels must exactly match originals.
private func verifyLosslessGrayscale(original: [[Int]], decoded: MultiComponentImageData) {
    let height = original.count
    let width = original[0].count
    #expect(decoded.components.count == 1)
    #expect(decoded.frameHeader.height == height)
    #expect(decoded.frameHeader.width == width)
    for row in 0..<height {
        for col in 0..<width {
            #expect(decoded.components[0].pixels[row][col] == original[row][col],
                   "Pixel [\(row),\(col)]: decoded=\(decoded.components[0].pixels[row][col]), expected=\(original[row][col])")
        }
    }
}

/// Verifies lossless round-trip for RGB.
private func verifyLosslessRGB(originalR: [[Int]], originalG: [[Int]], originalB: [[Int]], decoded: MultiComponentImageData) {
    let height = originalR.count
    let width = originalR[0].count
    #expect(decoded.components.count == 3)
    #expect(decoded.frameHeader.height == height)
    #expect(decoded.frameHeader.width == width)
    let originals = [originalR, originalG, originalB]
    for comp in 0..<3 {
        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[comp].pixels[row][col] == originals[comp][row][col],
                       "Component \(comp) pixel [\(row),\(col)]: decoded=\(decoded.components[comp].pixels[row][col]), expected=\(originals[comp][row][col])")
            }
        }
    }
}

/// Verifies near-lossless round-trip: |decoded - original| ≤ near for every pixel.
private func verifyNearLosslessGrayscale(original: [[Int]], decoded: MultiComponentImageData, near: Int) {
    let height = original.count
    let width = original[0].count
    #expect(decoded.components.count == 1)
    for row in 0..<height {
        for col in 0..<width {
            let diff = abs(decoded.components[0].pixels[row][col] - original[row][col])
            #expect(diff <= near,
                   "Pixel [\(row),\(col)]: diff=\(diff) > near=\(near), decoded=\(decoded.components[0].pixels[row][col]), expected=\(original[row][col])")
        }
    }
}

// MARK: - Systematic Grayscale Lossless Round-Trip Tests

@Suite("Round-Trip: Grayscale Lossless")
struct RoundTripGrayscaleLosslessTests {

    struct GrayscaleConfig: CustomTestStringConvertible, Sendable {
        let bitsPerSample: Int
        let width: Int
        let height: Int
        let label: String
        var testDescription: String { label }
    }

    static let configs: [GrayscaleConfig] = [
        // 8-bit
        GrayscaleConfig(bitsPerSample: 8, width: 32, height: 32, label: "8-bit 32×32"),
        GrayscaleConfig(bitsPerSample: 8, width: 64, height: 64, label: "8-bit 64×64"),
        // 12-bit
        GrayscaleConfig(bitsPerSample: 12, width: 32, height: 32, label: "12-bit 32×32"),
        GrayscaleConfig(bitsPerSample: 12, width: 64, height: 64, label: "12-bit 64×64"),
        // 16-bit
        GrayscaleConfig(bitsPerSample: 16, width: 32, height: 32, label: "16-bit 32×32"),
    ]

    @Test("Grayscale lossless gradient round-trip", arguments: configs)
    func testGradient(config: GrayscaleConfig) throws {
        let maxVal = (1 << config.bitsPerSample) - 1
        let pixels = makeGradientGrayscale(width: config.width, height: config.height, maxVal: maxVal)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: config.bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Grayscale lossless noise round-trip", arguments: configs)
    func testNoise(config: GrayscaleConfig) throws {
        let maxVal = (1 << config.bitsPerSample) - 1
        let pixels = makeNoiseGrayscale(width: config.width, height: config.height, maxVal: maxVal)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: config.bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }
}

// MARK: - Systematic RGB Lossless Round-Trip Tests

@Suite("Round-Trip: RGB Lossless")
struct RoundTripRGBLosslessTests {

    struct RGBConfig: CustomTestStringConvertible, Sendable {
        let bitsPerSample: Int
        let interleaveMode: JPEGLSInterleaveMode
        let colorTransform: JPEGLSColorTransformation
        let width: Int
        let height: Int
        let label: String
        var testDescription: String { label }
    }

    static let configs: [RGBConfig] = [
        // 8-bit, all interleave modes, no transform
        RGBConfig(bitsPerSample: 8, interleaveMode: .none, colorTransform: .none, width: 16, height: 16, label: "8-bit none-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .line, colorTransform: .none, width: 16, height: 16, label: "8-bit line-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .sample, colorTransform: .none, width: 16, height: 16, label: "8-bit sample-ILV"),
        // Color transforms (noise patterns avoid flat transformed components)
        RGBConfig(bitsPerSample: 8, interleaveMode: .none, colorTransform: .hp1, width: 16, height: 16, label: "8-bit HP1 none-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .line, colorTransform: .hp1, width: 16, height: 16, label: "8-bit HP1 line-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .sample, colorTransform: .hp2, width: 16, height: 16, label: "8-bit HP2 sample-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .none, colorTransform: .hp3, width: 16, height: 16, label: "8-bit HP3 none-ILV"),
        // 12-bit RGB
        RGBConfig(bitsPerSample: 12, interleaveMode: .none, colorTransform: .none, width: 16, height: 16, label: "12-bit none-ILV"),
        RGBConfig(bitsPerSample: 12, interleaveMode: .line, colorTransform: .none, width: 16, height: 16, label: "12-bit line-ILV"),
        // Larger 8-bit images to exercise run-index accumulation over many rows
        RGBConfig(bitsPerSample: 8, interleaveMode: .none, colorTransform: .none, width: 64, height: 64, label: "8-bit 64×64 none-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .line, colorTransform: .none, width: 64, height: 64, label: "8-bit 64×64 line-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .sample, colorTransform: .none, width: 64, height: 64, label: "8-bit 64×64 sample-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .none, colorTransform: .none, width: 256, height: 256, label: "8-bit 256×256 none-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .line, colorTransform: .none, width: 256, height: 256, label: "8-bit 256×256 line-ILV"),
        RGBConfig(bitsPerSample: 8, interleaveMode: .sample, colorTransform: .none, width: 256, height: 256, label: "8-bit 256×256 sample-ILV"),
    ]

    @Test("RGB lossless noise round-trip", arguments: configs)
    func testNoise(config: RGBConfig) throws {
        let maxVal = (1 << config.bitsPerSample) - 1
        let (r, g, b) = makeNoiseRGB(width: config.width, height: config.height, maxVal: maxVal)
        let imageData = try MultiComponentImageData.rgb(redPixels: r, greenPixels: g, bluePixels: b, bitsPerSample: config.bitsPerSample)
        let cfg = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: config.interleaveMode, colorTransformation: config.colorTransform)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: cfg)
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessRGB(originalR: r, originalG: g, originalB: b, decoded: decoded)
    }
}

// MARK: - Medical Imaging Simulation Tests

@Suite("Round-Trip: Medical Imaging Patterns")
struct RoundTripMedicalImagingTests {

    /// Simulates a CT image: smooth ramp with Hounsfield-unit-like values in 12-bit range.
    /// CT images have relatively smooth regions with sharp organ boundaries.
    /// A small base offset avoids purely flat rows that stress run-mode encoding.
    @Test("CT simulation — 12-bit smooth ramp with edges")
    func testCTSimulation() throws {
        let width = 64
        let height = 64
        let maxVal = 4095
        var seed: UInt64 = 17
        var pixels = [[Int]]()
        for row in 0..<height {
            var line = [Int]()
            for col in 0..<width {
                // Smooth background gradient with small jitter to avoid pure flat runs
                var value = (row * maxVal) / height + lcg(&seed, maxVal: 3)
                // Sharp circular "organ" boundary
                let dx = col - width / 2
                let dy = row - height / 2
                if dx * dx + dy * dy < (width / 4) * (width / 4) {
                    value = min(maxVal, value + 800)
                }
                line.append(value)
            }
            pixels.append(line)
        }

        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Simulates an MR image: soft-tissue contrast in 12-bit range with low-noise smooth regions.
    @Test("MR simulation — 12-bit soft-tissue contrast")
    func testMRSimulation() throws {
        let width = 64
        let height = 64
        let maxVal = 4095
        var pixels = [[Int]]()
        var seed: UInt64 = 7
        for row in 0..<height {
            var line = [Int]()
            for col in 0..<width {
                let base = ((row + col) * maxVal) / (width + height)
                let noise = lcg(&seed, maxVal: 20) - 10
                line.append(max(0, min(maxVal, base + noise)))
            }
            pixels.append(line)
        }

        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Simulates a CR/DX (X-ray) image: high-contrast bone/soft-tissue boundaries in 16-bit range.
    @Test("CR/DX simulation — 16-bit high-contrast radiograph")
    func testCRDXSimulation() throws {
        let width = 64
        let height = 64
        let maxVal = 65535
        var pixels = [[Int]]()
        for row in 0..<height {
            var line = [Int]()
            for col in 0..<width {
                var value = maxVal - (row * maxVal) / height
                if col >= width / 3 && col < 2 * width / 3 {
                    value = value / 4
                }
                line.append(value)
            }
            pixels.append(line)
        }

        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 16)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Simulates a US (ultrasound) image: speckle noise pattern typical of ultrasound.
    @Test("US simulation — 8-bit speckle noise")
    func testUSSimulation() throws {
        let width = 64
        let height = 64
        let maxVal = 255
        var seed: UInt64 = 123
        var pixels = [[Int]]()
        for row in 0..<height {
            var line = [Int]()
            for col in 0..<width {
                let distFromTop = row
                let intensity = max(0, maxVal - distFromTop * 3)
                let speckle = lcg(&seed, maxVal: min(intensity, 80))
                line.append(max(0, min(maxVal, intensity - 40 + speckle)))
            }
            pixels.append(line)
        }

        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Simulates a nuclear medicine (NM) image: low-count hot spots on dark background.
    @Test("NM simulation — 8-bit low-count hot spots")
    func testNMSimulation() throws {
        let width = 64
        let height = 64
        let maxVal = 255
        var seed: UInt64 = 200
        var pixels = [[Int]]()
        for row in 0..<height {
            var line = [Int]()
            for col in 0..<width {
                // Dark background with Poisson-like noise
                var value = 5 + lcg(&seed, maxVal: 10)
                // Two hot spots
                let d1 = (row - 20) * (row - 20) + (col - 20) * (col - 20)
                let d2 = (row - 44) * (row - 44) + (col - 44) * (col - 44)
                if d1 < 64 { value = min(maxVal, value + 180) }
                if d2 < 100 { value = min(maxVal, value + 120) }
                line.append(value)
            }
            pixels.append(line)
        }

        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }
}

// MARK: - Edge-Case Round-Trip Tests

@Suite("Round-Trip: Edge Cases")
struct RoundTripEdgeCaseTests {

    @Test("1×1 grayscale 8-bit lossless")
    func test1x1Grayscale() throws {
        let pixels = [[128]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("1×1 grayscale 16-bit lossless")
    func test1x1Grayscale16() throws {
        let pixels = [[32768]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 16)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("1×1 RGB 8-bit lossless")
    func test1x1RGB() throws {
        let r = [[200]], g = [[100]], b = [[50]]
        let imageData = try MultiComponentImageData.rgb(redPixels: r, greenPixels: g, bluePixels: b, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0, interleaveMode: .none))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessRGB(originalR: r, originalG: g, originalB: b, decoded: decoded)
    }

    @Test("Single-row image (1 row × 64 cols)")
    func testSingleRow() throws {
        let pixels = [(0..<64).map { $0 * 4 }]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Single-column image (64 rows × 1 col)")
    func testSingleColumn() throws {
        let pixels = (0..<64).map { [$0 * 4] }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Mixed flat + gradient region (run mode transition)")
    func testFlatRegionRunMode() throws {
        let pixels = (0..<32).map { row -> [Int] in
            (0..<64).map { col in col < 32 ? 100 : (100 + (col - 32) * 4) }
        }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Checkerboard pattern (maximum local contrast)")
    func testCheckerboard() throws {
        let pixels = (0..<32).map { row in
            (0..<32).map { col in (row + col) % 2 == 0 ? 0 : 255 }
        }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Near-lossless 1×1")
    func testNearLossless1x1() throws {
        let pixels = [[200]]
        let near = 5
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: near))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyNearLosslessGrayscale(original: pixels, decoded: decoded, near: near)
    }

    @Test("2×2 grayscale with all corners covered")
    func test2x2Grayscale() throws {
        let pixels = [[0, 255], [128, 64]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Narrow tall image (2 cols × 32 rows)")
    func testNarrowTall() throws {
        let pixels = (0..<32).map { row in [row * 8, 255 - row * 8] }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("Wide short image (64 cols × 2 rows)")
    func testWideShort() throws {
        let pixels = [
            (0..<64).map { $0 * 4 },
            (0..<64).map { 255 - $0 * 4 }
        ]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("12-bit boundary values")
    func test12BitBoundary() throws {
        let pixels = [[0, 1, 2047, 2048, 4094, 4095]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    @Test("16-bit boundary values")
    func test16BitBoundary() throws {
        let pixels = [[0, 1, 32767, 32768, 65534, 65535]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 16)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }
}

// MARK: - Expanded Near-Lossless Round-Trip Tests
//
// These tests verify that near-lossless encoding works correctly for images larger
// than 8×8, and for flat (constant-value) images.  Both categories previously
// triggered run-mode encoder bugs that were fixed in PR #82 (EOL partial-block).

@Suite("Round-Trip: Near-Lossless")
struct RoundTripNearLosslessTests {

    struct NearLosslessConfig: CustomTestStringConvertible, Sendable {
        let bitsPerSample: Int
        let width: Int
        let height: Int
        let near: Int
        let label: String
        var testDescription: String { label }
    }

    static let configs: [NearLosslessConfig] = [
        // 8-bit grayscale — multiple sizes to verify EOL run-mode fix
        NearLosslessConfig(bitsPerSample: 8, width: 16, height: 16, near: 1, label: "8-bit 16×16 near=1"),
        NearLosslessConfig(bitsPerSample: 8, width: 32, height: 32, near: 3, label: "8-bit 32×32 near=3"),
        NearLosslessConfig(bitsPerSample: 8, width: 64, height: 64, near: 5, label: "8-bit 64×64 near=5"),
        NearLosslessConfig(bitsPerSample: 8, width: 64, height: 64, near: 1, label: "8-bit 64×64 near=1"),
        // 12-bit grayscale
        NearLosslessConfig(bitsPerSample: 12, width: 32, height: 32, near: 3, label: "12-bit 32×32 near=3"),
        NearLosslessConfig(bitsPerSample: 12, width: 64, height: 64, near: 3, label: "12-bit 64×64 near=3"),
    ]

    @Test("Near-lossless noise round-trip", arguments: configs)
    func testNoisePatterNearLossless(config: NearLosslessConfig) throws {
        let maxVal = (1 << config.bitsPerSample) - 1
        let pixels = makeNoiseGrayscale(width: config.width, height: config.height, maxVal: maxVal)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: config.bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: config.near))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyNearLosslessGrayscale(original: pixels, decoded: decoded, near: config.near)
    }

    @Test("Near-lossless gradient round-trip", arguments: configs)
    func testGradientNearLossless(config: NearLosslessConfig) throws {
        let maxVal = (1 << config.bitsPerSample) - 1
        let pixels = makeGradientGrayscale(width: config.width, height: config.height, maxVal: maxVal)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: config.bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: config.near))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyNearLosslessGrayscale(original: pixels, decoded: decoded, near: config.near)
    }

    /// Flat (constant-value) images trigger run mode on every pixel.
    /// Previously failed for images larger than 8×8 due to the EOL partial-block bug.
    @Test("Flat image lossless round-trip (32×32)")
    func testFlatImage32x32() throws {
        let pixels = Array(repeating: Array(repeating: 128, count: 32), count: 32)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Large flat image to stress-test run mode continuations across multiple lines.
    @Test("Flat image lossless round-trip (64×64)")
    func testFlatImage64x64() throws {
        let pixels = Array(repeating: Array(repeating: 200, count: 64), count: 64)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyLosslessGrayscale(original: pixels, decoded: decoded)
    }

    /// Near-lossless flat image: run mode dominant, all pixels decode within NEAR.
    @Test("Flat image near-lossless round-trip (32×32, near=3)")
    func testFlatImageNearLossless() throws {
        let pixels = Array(repeating: Array(repeating: 100, count: 32), count: 32)
        let near = 3
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: near))
        let decoded = try JPEGLSDecoder().decode(encoded)
        verifyNearLosslessGrayscale(original: pixels, decoded: decoded, near: near)
    }
}
