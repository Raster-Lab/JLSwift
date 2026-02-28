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
//
// Coverage:
//   Phase 12.2 items addressed:
//     ✅ Create test infrastructure to validate JLSwift-encoded output
//     ✅ Validate lossless output (bit-exact round-trip) — 8-bit RGB, 12-bit grayscale
//     ✅ Validate near-lossless output (error ≤ NEAR) — 8-bit RGB near=3, 12-bit near=3
//     ✅ All interleaving modes: none, line, sample
//     ✅ Bit depths: 8-bit and 12-bit (natural images); 16-bit in RoundTripTests
//     ✅ Grayscale and RGB configurations
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
            interleaveMode: .none,
            description: "8-bit RGB none-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .line,
            description: "8-bit RGB line-ILV lossless"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 0,
            interleaveMode: .sample,
            description: "8-bit RGB sample-ILV lossless"
        ),
        // 8-bit grayscale (test8r.pgm — R component of test8)
        EncodeInteropTestCase(
            referenceFile: "test8r.pgm",
            width: 256, height: 256, components: 1, maxVal: 255, near: 0,
            interleaveMode: .none,
            description: "8-bit grayscale lossless"
        ),
        // 12-bit grayscale (test16.pgm — stored with MAXVAL=4095)
        EncodeInteropTestCase(
            referenceFile: "test16.pgm",
            width: 256, height: 256, components: 1, maxVal: 4095, near: 0,
            interleaveMode: .none,
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
            interleaveMode: .none,
            description: "8-bit RGB none-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .line,
            description: "8-bit RGB line-ILV near=3"
        ),
        EncodeInteropTestCase(
            referenceFile: "test8.ppm",
            width: 256, height: 256, components: 3, maxVal: 255, near: 3,
            interleaveMode: .sample,
            description: "8-bit RGB sample-ILV near=3"
        ),
        // 12-bit grayscale near=3
        EncodeInteropTestCase(
            referenceFile: "test16.pgm",
            width: 256, height: 256, components: 1, maxVal: 4095, near: 3,
            interleaveMode: .none,
            description: "12-bit grayscale near=3"
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

        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: testCase.interleaveMode)
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

        let config = try JPEGLSEncoder.Configuration(near: testCase.near, interleaveMode: testCase.interleaveMode)
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
}
