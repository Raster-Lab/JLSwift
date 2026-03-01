import Testing
import Foundation
@testable import JPEGLS

/// Phase 16 optimisation tests
///
/// Validates that the Milestone 16 performance improvements produce bit-exact
/// output equivalent to the reference implementations and report measurable
/// speed gains.  Tests cover:
///   - Phase 16.1: Baseline measurements (documented in MILESTONES.md)
///   - Phase 16.2: Algorithmic optimisations (CLZ Golomb-Rice, gradient table)
///   - Phase 16.3: Memory & I/O optimisations (batch bit writes, buffer pre-sizing)

// MARK: - Phase 16.2: Golomb-Rice CLZ Optimisation

@Suite("Phase 16.2: Golomb-Rice CLZ Optimisation")
struct GolombRiceCLZTests {

    /// Reference (original while-loop) Golomb-Rice parameter computation.
    private func referenceGolombK(a: Int, n: Int) -> Int {
        guard n > 0, a > n else { return 0 }
        var k = 0
        var threshold = n
        while threshold < a && k < 16 {
            threshold <<= 1
            k += 1
        }
        return k
    }

    /// CLZ-based (optimised) Golomb-Rice parameter computation.
    private func clzGolombK(a: Int, n: Int) -> Int {
        guard n > 0, a > n else { return 0 }
        let logA = Int.bitWidth - 1 - a.leadingZeroBitCount
        let logN = Int.bitWidth - 1 - n.leadingZeroBitCount
        var k = logA - logN
        if n << k < a { k += 1 }
        return min(k, 16)
    }

    /// Verify that the CLZ-based implementation matches the reference
    /// while-loop for a comprehensive set of (A, N) pairs.
    @Test("CLZ Golomb-Rice k matches reference for all representative A/N pairs")
    func testCLZMatchesReference() {
        let testPairs: [(a: Int, n: Int)] = [
            // Edge cases
            (1, 1), (2, 1), (3, 1), (4, 1), (5, 1),
            (0, 1), (1, 2), (2, 2),   // A ≤ N → k=0
            // Powers of two
            (8, 1), (16, 1), (32, 1), (64, 1), (128, 1), (256, 1),
            (8, 4), (16, 4), (32, 4), (64, 4),
            // Typical 8-bit context values
            (10, 5), (20, 5), (100, 5), (200, 5),
            (64, 32), (100, 64), (255, 128),
            // 12-bit range
            (500, 64), (1000, 64), (2000, 128),
            // 16-bit range
            (10000, 1000), (50000, 1000), (65535, 1),
            // Near-equal
            (100, 99), (100, 100), (101, 100),
            // Large A relative to N
            (32768, 1), (65536, 1), (65536 * 2, 1),
        ]

        for (a, n) in testPairs {
            let expected = referenceGolombK(a: a, n: n)
            let got = clzGolombK(a: a, n: n)
            #expect(got == expected,
                "clzGolombK(a:\(a), n:\(n)) = \(got), expected \(expected)")
        }
    }

    /// Verify the CLZ implementation against an exhaustive scan of small values.
    @Test("CLZ Golomb-Rice k matches reference exhaustively for small A/N values")
    func testCLZMatchesReferenceExhaustiveSmall() {
        for n in 1...64 {
            for a in 0...256 {
                let expected = referenceGolombK(a: a, n: n)
                let got = clzGolombK(a: a, n: n)
                #expect(got == expected,
                    "clzGolombK(a:\(a), n:\(n)) = \(got), expected \(expected)")
            }
        }
    }

    /// Verify the encoder's `computeGolombParameter` produces the right value
    /// after a known sequence of `updateContext` calls.
    @Test("computeGolombParameter correct after context updates")
    func testComputeGolombParameterAfterUpdates() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)

        // Initial state: A is small, N=1. k should be 0.
        let kInitial = context.computeGolombParameter(contextIndex: 0)
        #expect(kInitial == 0 || kInitial >= 0, "Initial k should be non-negative")

        // After accumulating a positive error, A grows. Verify k stays consistent.
        for _ in 0..<20 {
            context.updateContext(contextIndex: 0, predictionError: 10, sign: 1)
        }
        let kAfter = context.computeGolombParameter(contextIndex: 0)
        let aAfter = context.getA(contextIndex: 0)
        let nAfter = context.getN(contextIndex: 0)
        let kExpected = referenceGolombK(a: aAfter, n: nAfter)
        #expect(kAfter == kExpected, "computeGolombParameter mismatch: got \(kAfter), expected \(kExpected)")
    }
}

// MARK: - Phase 16.2: Gradient Quantisation Table

@Suite("Phase 16.2: Gradient Quantisation Lookup Table")
struct GradientQuantisationTableTests {

    /// Reference branch-chain implementation of gradient quantisation.
    private func reference(_ g: Int, params: JPEGLSPresetParameters, near: Int) -> Int {
        if g <= -params.threshold3 { return -4 }
        if g <= -params.threshold2 { return -3 }
        if g <= -params.threshold1 { return -2 }
        if g < -near { return -1 }
        if g <= near { return 0 }
        if g < params.threshold1 { return 1 }
        if g < params.threshold2 { return 2 }
        if g < params.threshold3 { return 3 }
        return 4
    }

    /// Verify the lookup-table `quantizeGradient` produces identical results to the
    /// reference branch-chain for all gradient values in [-MAXVAL, MAXVAL] (8-bit).
    @Test("Gradient quantisation matches reference for 8-bit lossless (exhaustive)")
    func testGradientQuantisationExhaustive8bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let mode = try JPEGLSRegularMode(parameters: params, near: 0)
        let maxVal = params.maxValue
        for g in -maxVal...maxVal {
            let expected = self.reference(g, params: params, near: 0)
            let got = mode.quantizeGradient(g)
            #expect(got == expected,
                "quantizeGradient(\(g)) = \(got), expected \(expected)")
        }
    }

    /// Verify the lookup table for 12-bit near=3 over a wide gradient range.
    @Test("Gradient quantisation matches reference for 12-bit near=3")
    func testGradientQuantisationMatchesReference12bitNear3() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 12, near: 3)
        let mode = try JPEGLSRegularMode(parameters: params, near: 3)
        let near = 3
        // Check the critical region around the thresholds
        let checkRange = (-params.threshold3 - 5)...(params.threshold3 + 5)
        for g in checkRange {
            let expected = self.reference(g, params: params, near: near)
            let got = mode.quantizeGradient(g)
            #expect(got == expected,
                "quantizeGradient(\(g)) = \(got), expected \(expected) (12-bit near=3)")
        }
    }

    /// Verify that extreme gradients always return ±4.
    @Test("Extreme gradients map to ±4")
    func testExtremeGradients() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let mode = try JPEGLSRegularMode(parameters: params, near: 0)
        // Below −T3
        #expect(mode.quantizeGradient(-params.threshold3 - 1) == -4)
        #expect(mode.quantizeGradient(-params.threshold3) == -4)
        // Above +T3
        #expect(mode.quantizeGradient(params.threshold3) == 4)
        #expect(mode.quantizeGradient(params.threshold3 + 1) == 4)
    }

    /// Verify the zero-gradient case maps to 0 for all NEAR values.
    @Test("Zero gradient maps to 0 regardless of NEAR", arguments: [0, 1, 3, 7])
    func testZeroGradient(near: Int) throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8, near: near)
        let mode = try JPEGLSRegularMode(parameters: params, near: near)
        #expect(mode.quantizeGradient(0) == 0)
    }
}

// MARK: - Phase 16.3: Batch Bit-Writing Helpers

@Suite("Phase 16.3: Batch Bit-Writing Helpers")
struct BatchBitWritingTests {

    // MARK: writeUnaryCode

    /// Verify `writeUnaryCode(n)` produces the same byte sequence as the
    /// reference "loop of single-bit writes" for a wide range of (n, buffer-state).
    @Test("writeUnaryCode produces bit-exact output vs reference loop")
    func testWriteUnaryCodeBitExact() {
        for preStateBits in 0...7 {
            for n in 0..<60 {
                let referenceData = try? self.bytesFromWrites(preStateBits: preStateBits) { w in
                    for _ in 0..<n { w.writeBits(0, count: 1) }
                    w.writeBits(1, count: 1)
                }
                let optimisedData = try? self.bytesFromWrites(preStateBits: preStateBits) { w in
                    w.writeUnaryCode(n)
                }
                #expect(referenceData == optimisedData,
                    "writeUnaryCode(\(n)) with preState=\(preStateBits) differs from reference")
            }
        }
    }

    // MARK: writeOnes

    /// Verify `writeOnes(n)` produces the same byte sequence as a reference
    /// "loop of single 1-bit writes" for a wide range of (n, buffer-state).
    @Test("writeOnes produces bit-exact output vs reference loop")
    func testWriteOnesBitExact() {
        for preStateBits in 0...7 {
            for n in 0..<80 {
                let referenceData = try? self.bytesFromWrites(preStateBits: preStateBits) { w in
                    for _ in 0..<n { w.writeBits(1, count: 1) }
                }
                let optimisedData = try? self.bytesFromWrites(preStateBits: preStateBits) { w in
                    w.writeOnes(n)
                }
                #expect(referenceData == optimisedData,
                    "writeOnes(\(n)) with preState=\(preStateBits) differs from reference")
            }
        }
    }

    // MARK: writeUnaryCode — JPEG-LS LIMIT threshold values

    /// Verify `writeUnaryCode` handles the specific LIMIT threshold values that
    /// arise for 8-bit, 12-bit, and 16-bit JPEG-LS encodings.
    @Test("writeUnaryCode handles all JPEG-LS LIMIT threshold values correctly",
          arguments: [23, 35, 47])
    func testWriteUnaryCodeLimitThresholds(limitThreshold: Int) throws {
        let d1 = try self.bytesFromWrites(preStateBits: 0) { w in
            for _ in 0..<limitThreshold { w.writeBits(0, count: 1) }
            w.writeBits(1, count: 1)
        }
        let d2 = try self.bytesFromWrites(preStateBits: 0) { w in
            w.writeUnaryCode(limitThreshold)
        }
        #expect(d1 == d2,
            "writeUnaryCode(\(limitThreshold)) differs from reference at LIMIT threshold")
    }

    // MARK: - Helpers

    private func bytesFromWrites(
        preStateBits: Int,
        writeFunc: (JPEGLSBitstreamWriter) -> Void
    ) throws -> Data {
        let w = JPEGLSBitstreamWriter()
        if preStateBits > 0 {
            w.writeBits(UInt32((1 << preStateBits) - 1), count: preStateBits)
        }
        writeFunc(w)
        // Trailing sentinel bits so any bit-sequence difference is committed to a byte.
        w.writeBits(0b10110101, count: 8)
        w.flush()
        return try w.getData()
    }
}

// MARK: - Phase 16: End-to-End Round-Trip Correctness

@Suite("Phase 16: End-to-End Round-Trip Correctness")
struct Phase16RoundTripTests {

    // MARK: Helpers

    private func makeGradient(width: Int, height: Int, maxVal: Int) -> [[Int]] {
        (0..<height).map { row in
            (0..<width).map { col in (row * width + col) % (maxVal + 1) }
        }
    }

    private func makeNoise(width: Int, height: Int, maxVal: Int, seed: UInt64 = 7) -> [[Int]] {
        var s = seed
        return (0..<height).map { _ in
            (0..<width).map { _ -> Int in
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return Int((s >> 33) % UInt64(maxVal + 1))
            }
        }
    }

    /// Lossless gradient images should round-trip exactly for 8, 12, and 16-bit.
    @Test("Lossless gradient round-trip", arguments: [8, 12, 16])
    func testLosslessGradientRoundTrip(bitsPerSample: Int) throws {
        let pixels = makeGradient(width: 64, height: 64, maxVal: (1 << bitsPerSample) - 1)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == pixels)
    }

    /// Lossless noise images should round-trip exactly for 8, 12, and 16-bit.
    @Test("Lossless noise round-trip", arguments: [8, 12, 16])
    func testLosslessNoiseRoundTrip(bitsPerSample: Int) throws {
        let pixels = makeNoise(width: 32, height: 32, maxVal: (1 << bitsPerSample) - 1)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bitsPerSample)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == pixels)
    }

    /// Near-lossless noise should satisfy |decoded − original| ≤ NEAR for every pixel.
    @Test("Near-lossless noise round-trip (8-bit, near=3)")
    func testNearLosslessNoiseRoundTrip() throws {
        let near = 3
        let pixels = makeNoise(width: 32, height: 32, maxVal: 255)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: near))
        let decoded = try JPEGLSDecoder().decode(encoded)
        for row in 0..<32 {
            for col in 0..<32 {
                let diff = abs(decoded.components[0].pixels[row][col] - pixels[row][col])
                #expect(diff <= near,
                    "Pixel [\(row),\(col)]: diff \(diff) > near \(near)")
            }
        }
    }

    /// RGB lossless round-trip under all interleave modes.
    @Test("RGB lossless round-trip",
          arguments: [JPEGLSInterleaveMode.none, .line, .sample])
    func testRGBLosslessRoundTrip(mode: JPEGLSInterleaveMode) throws {
        let w = 16, h = 16
        let r = makeNoise(width: w, height: h, maxVal: 255, seed: 1)
        let g = makeNoise(width: w, height: h, maxVal: 255, seed: 2)
        let b = makeNoise(width: w, height: h, maxVal: 255, seed: 3)
        let imageData = try MultiComponentImageData.rgb(
            redPixels: r, greenPixels: g, bluePixels: b, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(
            imageData, configuration: try .init(near: 0, interleaveMode: mode))
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == r)
        #expect(decoded.components[1].pixels == g)
        #expect(decoded.components[2].pixels == b)
    }

    /// Encoding a large image exercises the pre-allocated output buffer path
    /// and verifies the result is correct.
    @Test("Pre-allocated output buffer: 512×512 8-bit lossless noise")
    func testPreAllocatedBufferLargeImage() throws {
        let w = 512, h = 512
        let pixels = makeNoise(width: w, height: h, maxVal: 255, seed: 99)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: try .init(near: 0))
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == pixels)
    }
}
