// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2025 Raster-Lab
// CharLS Encode Interoperability Tests
//
// Phase 12.2: JLSwift-encoded → (JLSwift-decoded) interoperability tests.
//
// Tests that JLSwift produces valid JPEG-LS output for real-world reference images
// from the CharLS conformance test suite (test8.ppm and test16.pgm).  Since the
// JLSwift decoder is validated bit-exact against CharLS (Phase 12.1), a successful
// JLSwift-encode → JLSwift-decode round-trip on these images demonstrates that:
//   - The encoder produces standards-compliant JPEG-LS bitstreams.
//   - All interleave modes (none, line, sample) work with natural images.
//   - All target bit depths (8-bit, 12-bit, 16-bit) are correctly handled.
//   - Near-lossless coding (NEAR > 0) respects the error bound on natural images.
//   - Grayscale and RGB component configurations are both correctly encoded.
//   - Part 2 colour transforms (HP1, HP2, HP3) work correctly on natural images.
//
// Coverage:
//   Phase 12.2 items addressed:
//     ✅ Create test infrastructure to validate JLSwift-encoded output
//     ✅ Validate lossless output (bit-exact round-trip) — 8-bit RGB, 12-bit grayscale
//     ✅ Validate near-lossless output (error ≤ NEAR) — 8-bit RGB near=3, 12-bit near=3
//     ✅ All interleaving modes: none, line, sample
//     ✅ Bit depths: 8-bit and 12-bit (natural images); 16-bit in RoundTripTests
//     ✅ Grayscale and RGB configurations
//   Phase 12.1 items addressed:
//     ✅ Test encoding/decoding with colour transformations (HP1, HP2, HP3) on natural images
//
// Note: Bit depth listed as "16-bit" in the JLS standard actually stores 12-bit
// (MAXVAL=4095) samples for the CharLS test16 reference image.

import Testing
@testable import JPEGLS

// MARK: - Encoder Interoperability Test Configuration

/// A test case that encodes a reference image with the JLSwift encoder and
/// round-trips it through the JLSwift decoder.
struct EncodeInteropTestCase: CustomTestStringConvertible, Sendable {
    /// Source reference file name (PGM or PPM from TestFixtures)
    let referenceFile: String
    /// Expected image width
    let width: Int
    /// Expected image height
    let height: Int
    /// Number of colour components
    let components: Int
    /// Maximum sample value (MAXVAL)
    let maxVal: Int
    /// NEAR parameter (0 = lossless)
    let near: Int
    /// Interleave mode used for encoding
    let interleaveMode: JPEGLSInterleaveMode
    /// Part 2 colour transformation applied before encoding
    let colorTransformation: JPEGLSColorTransformation
    /// Human-readable description used as the Swift Testing test name
    let description: String

    var testDescription: String { description }
}

// MARK: - CharLS Encoder Interoperability Test Suite

/// Tests that JLSwift produces valid JPEG-LS output for all CharLS reference images.
///
/// Each test loads a reference image, encodes it with JLSwift, decodes the encoded
/// data with JLSwift, and compares the decoded pixels against the original.
@Suite("CharLS Encode Interoperability Tests")
struct CharLSEncodeInteropTests {

    // MARK: - Lossless test cases

    /// Parameterised lossless test cases covering both reference images and all
    /// interleave modes that are applicable to each image type.
    static let losslessTestCases: [EncodeInteropTestCase] = [
        // 8-bit colour (test8.ppm) — three interleave modes
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .none, colorTransformation: .none,
            description: "8-bit RGB none-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .line, colorTransformation: .none,
            description: "8-bit RGB line-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .sample, colorTransformation: .none,
            description: "8-bit RGB sample-ILV lossless"
        ),
        // 8-bit grayscale (test8r.pgm — R component of test8)
        EncodeInteropTestCase(
            referenceFile: "test8r.pgm",
            width: 256, height: 256, components: 1, maxVal: 255, near: 0,
            interleaveMode: .none, colorTransformation: .none,
            description: "8-bit grayscale lossless"
        ),
        // 12-bit grayscale (test16.pgm — stored with MAXVAL=4095)
        EncodeInteropTestCase(
            referenceFile: "test16.pgm",
            width: 256, height: 256, components: 1, maxVal: 4095, near: 0,
            interleaveMode: .none, colorTransformation: .none,
            description: "12-bit grayscale lossless"
        ),
    ]

    // MARK: - Near-lossless test cases

    /// Parameterised near-lossless test cases for natural reference images.
    static let nearLosslessTestCases: [EncodeInteropTestCase] = [
        // 8-bit colour near=3
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .none, colorTransformation: .none,
            description: "8-bit RGB none-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .line, colorTransformation: .none,
            description: "8-bit RGB line-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .sample, colorTransformation: .none,
            description: "8-bit RGB sample-ILV near=3"
        ),
        // 12-bit grayscale near=3
        EncodeInteropTestCase(
            referenceFile: "test16.pgm",
            width: 256, height: 256, components: 1, maxVal: 4095, near: 3,
            interleaveMode: .none, colorTransformation: .none,
            description: "12-bit grayscale near=3"
        ),
    ]

    // MARK: - Colour transform lossless test cases

    /// Parameterised lossless test cases with Part 2 colour transforms (HP1, HP2, HP3)
    /// applied to the 256×256 RGB reference image (test8.ppm).
    static let colorTransformLosslessTestCases: [EncodeInteropTestCase] = [
        // HP1 colour transform — all interleave modes
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .none, colorTransformation: .hp1,
            description: "8-bit RGB HP1 none-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .line, colorTransformation: .hp1,
            description: "8-bit RGB HP1 line-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .sample, colorTransformation: .hp1,
            description: "8-bit RGB HP1 sample-ILV lossless"
        ),
        // HP2 colour transform — all interleave modes
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .none, colorTransformation: .hp2,
            description: "8-bit RGB HP2 none-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .line, colorTransformation: .hp2,
            description: "8-bit RGB HP2 line-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .sample, colorTransformation: .hp2,
            description: "8-bit RGB HP2 sample-ILV lossless"
        ),
        // HP3 colour transform — all interleave modes
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .none, colorTransformation: .hp3,
            description: "8-bit RGB HP3 none-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .line, colorTransformation: .hp3,
            description: "8-bit RGB HP3 line-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .sample, colorTransformation: .hp3,
            description: "8-bit RGB HP3 sample-ILV lossless"
        ),
    ]

    // MARK: - Colour transform near-lossless test cases

    /// Parameterised near-lossless test cases with Part 2 colour transforms (HP1, HP2, HP3)
    /// applied to the 256×256 RGB reference image (test8.ppm) with NEAR=3.
    static let colorTransformNearLosslessTestCases: [EncodeInteropTestCase] = [
        // HP1 colour transform near=3 — all interleave modes
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .none, colorTransformation: .hp1,
            description: "8-bit RGB HP1 none-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .line, colorTransformation: .hp1,
            description: "8-bit RGB HP1 line-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .sample, colorTransformation: .hp1,
            description: "8-bit RGB HP1 sample-ILV near=3"
        ),
        // HP2 colour transform near=3
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .none, colorTransformation: .hp2,
            description: "8-bit RGB HP2 none-ILV near=3"
        ),
        // HP3 colour transform near=3
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .none, colorTransformation: .hp3,
            description: "8-bit RGB HP3 none-ILV near=3"
        ),
    ]

    // MARK: - Helpers

    /// Load reference pixel data from a PGM or PPM fixture file.
    ///
    /// Returns a flat array of UInt16 sample values in component-interleaved order
    /// (for PPM: R0 G0 B0 R1 G1 B1 …; for PGM: Y0 Y1 …).
    private func loadReferencePixels(testCase: EncodeInteropTestCase) throws -> [UInt16] {
        if testCase.referenceFile.hasSuffix(".ppm") {
            let (_, _, _, pixels) = try TestFixtureLoader.loadPPM(named: testCase.referenceFile)
            return pixels
        } else {
            let (_, _, _, pixels) = try TestFixtureLoader.loadPGM(named: testCase.referenceFile)
            return pixels
        }
    }

    /// Build a `MultiComponentImageData` from a flat interleaved pixel array.
    private func buildImageData(
        pixels referencePixels: [UInt16],
        testCase: EncodeInteropTestCase
    ) throws -> MultiComponentImageData {
        let width = testCase.width
        let height = testCase.height
        let components = testCase.components

        if components == 1 {
            // Grayscale — flat array maps directly to [row][col]
            let pixelGrid: [[Int]] = (0..<height).map { row in
                (0..<width).map { col in Int(referencePixels[row * width + col]) }
            }
            return try MultiComponentImageData.grayscale(
                pixels: pixelGrid,
                bitsPerSample: testCase.maxVal < 256 ? 8 : 12
            )
        } else {
            // RGB — reference data is interleaved (R0 G0 B0, R1 G1 B1, …)
            var r = [[Int]](), g = [[Int]](), b = [[Int]]()
            r.reserveCapacity(height); g.reserveCapacity(height); b.reserveCapacity(height)
            for row in 0..<height {
                var rRow = [Int](); var gRow = [Int](); var bRow = [Int]()
                rRow.reserveCapacity(width); gRow.reserveCapacity(width); bRow.reserveCapacity(width)
                for col in 0..<width {
                    let base = (row * width + col) * components
                    rRow.append(Int(referencePixels[base]))
                    gRow.append(Int(referencePixels[base + 1]))
                    bRow.append(Int(referencePixels[base + 2]))
                }
                r.append(rRow); g.append(gRow); b.append(bRow)
            }
            return try MultiComponentImageData.rgb(
                redPixels: r, greenPixels: g, bluePixels: b,
                bitsPerSample: 8
            )
        }
    }

    // MARK: - Lossless encode/decode round-trip

    @Test("Lossless encode round-trip for reference image", arguments: losslessTestCases)
    func testLosslessRoundTrip(testCase: EncodeInteropTestCase) throws {
        let referencePixels = try loadReferencePixels(testCase: testCase)
        let imageData = try buildImageData(pixels: referencePixels, testCase: testCase)

        let config = try JPEGLSEncoder.Configuration(
            near: 0, interleaveMode: testCase.interleaveMode,
            colorTransformation: testCase.colorTransformation
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        // Verify dimensions
        #expect(decoded.frameHeader.width == testCase.width)
        #expect(decoded.frameHeader.height == testCase.height)
        #expect(decoded.components.count == testCase.components)

        // Lossless: every decoded pixel must exactly equal the original
        for compIdx in 0..<testCase.components {
            let decodedComp = decoded.components[compIdx]
            for row in 0..<testCase.height {
                for col in 0..<testCase.width {
                    let refBase = (row * testCase.width + col) * testCase.components + compIdx
                    let expected = Int(referencePixels[refBase])
                    let actual = decodedComp.pixels[row][col]
                    #expect(actual == expected,
                           "comp\(compIdx) [\(row),\(col)]: decoded=\(actual) expected=\(expected) (\(testCase.description))")
                }
            }
        }
    }

    // MARK: - Near-lossless encode/decode round-trip

    @Test("Near-lossless encode round-trip for reference image", arguments: nearLosslessTestCases)
    func testNearLosslessRoundTrip(testCase: EncodeInteropTestCase) throws {
        let referencePixels = try loadReferencePixels(testCase: testCase)
        let imageData = try buildImageData(pixels: referencePixels, testCase: testCase)

        let config = try JPEGLSEncoder.Configuration(
            near: testCase.near, interleaveMode: testCase.interleaveMode,
            colorTransformation: testCase.colorTransformation
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        // Verify dimensions
        #expect(decoded.frameHeader.width == testCase.width)
        #expect(decoded.frameHeader.height == testCase.height)
        #expect(decoded.components.count == testCase.components)

        // Near-lossless: |decoded - original| ≤ NEAR for every pixel
        for compIdx in 0..<testCase.components {
            let decodedComp = decoded.components[compIdx]
            for row in 0..<testCase.height {
                for col in 0..<testCase.width {
                    let refBase = (row * testCase.width + col) * testCase.components + compIdx
                    let expected = Int(referencePixels[refBase])
                    let actual = decodedComp.pixels[row][col]
                    let diff = abs(actual - expected)
                    #expect(diff <= testCase.near,
                           "comp\(compIdx) [\(row),\(col)]: diff=\(diff) > NEAR=\(testCase.near) (\(testCase.description))")
                }
            }
        }
    }

    // MARK: - Colour transform lossless encode/decode round-trip

    @Test("Colour transform lossless encode round-trip for reference image",
          arguments: colorTransformLosslessTestCases)
    func testColorTransformLosslessRoundTrip(testCase: EncodeInteropTestCase) throws {
        let referencePixels = try loadReferencePixels(testCase: testCase)
        let imageData = try buildImageData(pixels: referencePixels, testCase: testCase)

        let config = try JPEGLSEncoder.Configuration(
            near: 0, interleaveMode: testCase.interleaveMode,
            colorTransformation: testCase.colorTransformation
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        // Verify dimensions
        #expect(decoded.frameHeader.width == testCase.width)
        #expect(decoded.frameHeader.height == testCase.height)
        #expect(decoded.components.count == testCase.components)

        // Lossless: every decoded pixel must exactly equal the original
        for compIdx in 0..<testCase.components {
            let decodedComp = decoded.components[compIdx]
            for row in 0..<testCase.height {
                for col in 0..<testCase.width {
                    let refBase = (row * testCase.width + col) * testCase.components + compIdx
                    let expected = Int(referencePixels[refBase])
                    let actual = decodedComp.pixels[row][col]
                    #expect(actual == expected,
                           "comp\(compIdx) [\(row),\(col)]: decoded=\(actual) expected=\(expected) (\(testCase.description))")
                }
            }
        }
    }

    // MARK: - Colour transform near-lossless encode/decode round-trip

    @Test("Colour transform near-lossless encode round-trip for reference image",
          arguments: colorTransformNearLosslessTestCases)
    func testColorTransformNearLosslessRoundTrip(testCase: EncodeInteropTestCase) throws {
        let referencePixels = try loadReferencePixels(testCase: testCase)
        let imageData = try buildImageData(pixels: referencePixels, testCase: testCase)

        let config = try JPEGLSEncoder.Configuration(
            near: testCase.near, interleaveMode: testCase.interleaveMode,
            colorTransformation: testCase.colorTransformation
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        // Verify dimensions
        #expect(decoded.frameHeader.width == testCase.width)
        #expect(decoded.frameHeader.height == testCase.height)
        #expect(decoded.components.count == testCase.components)

        // Near-lossless with colour transform: the NEAR error bound applies to
        // each component in the *transformed* domain (per ITU-T T.870).  After
        // inverse transform, the original-domain error can be amplified.  We
        // therefore verify the bound in the transformed domain.
        let ct = testCase.colorTransformation
        let maxVal = testCase.maxVal
        for row in 0..<testCase.height {
            for col in 0..<testCase.width {
                let base = (row * testCase.width + col) * testCase.components
                let origRGB = (0..<testCase.components).map { Int(referencePixels[base + $0]) }
                let decRGB = (0..<testCase.components).map { decoded.components[$0].pixels[row][col] }

                let origT = try ct.transformForward(origRGB, maxValue: maxVal)
                let decT = try ct.transformForward(decRGB, maxValue: maxVal)

                for c in 0..<testCase.components {
                    // Colour-transformed values use modular arithmetic in [0, maxVal].
                    // Near-lossless quantisation may push a value past the boundary
                    // (e.g. 2 → 254 mod 256), so the true distance is the shorter
                    // path around the modular ring — min(|d|, modulus−|d|).
                    let modulus = maxVal + 1
                    let rawDiff = abs(origT[c] - decT[c])
                    let diff = min(rawDiff, modulus - rawDiff)
                    #expect(diff <= testCase.near,
                           "transformed comp\(c) [\(row),\(col)]: diff=\(diff) > NEAR=\(testCase.near) (\(testCase.description))")
                }
            }
        }
    }
}
