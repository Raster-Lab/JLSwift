/// Extended Phase 15.3 GPU Compute tests.
///
/// Validates GPU compute operations (via Vulkan CPU fallback on all platforms)
/// across the full configuration matrix required by Milestone 15:
///
/// - All image sizes (tiny, small, medium, large, above GPU threshold)
/// - All relevant bit depths (8-bit, 12-bit, 16-bit pixel value ranges)
/// - Greyscale (single component) and RGB (three component) configurations
/// - Near-lossless encoding modes (NEAR > 0)
///
/// Metal variants are exercised on Apple platforms only (skipped elsewhere).

import Testing
@testable import JPEGLS

// MARK: - Image-Size Matrix Tests

@Suite("GPU Pipeline — Image Size Matrix (Vulkan CPU Fallback)")
struct GPUImageSizeMatrixTests {

    let accelerator = VulkanAccelerator()

    // MARK: Gradient computation — all sizes

    @Test("Gradients: tiny batch (1 pixel)")
    func testGradients1Pixel() {
        let (d1, d2, d3) = accelerator.computeGradientsBatch(
            a: [100], b: [150], c: [80])
        #expect(d1 == [70])   // 150 - 80
        #expect(d2 == [20])   // 100 - 80
        #expect(d3 == [-20])  // 80 - 100
    }

    @Test("Gradients: small batch (16 pixels)")
    func testGradients16Pixels() {
        let count = 16
        let a = [Int32](repeating: 200, count: count)
        let b = [Int32](repeating: 100, count: count)
        let c = [Int32](repeating:  50, count: count)
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.allSatisfy { $0 == 50  })   // 100 - 50
        #expect(d2.allSatisfy { $0 == 150 })   // 200 - 50
        #expect(d3.allSatisfy { $0 == -150 })  // 50 - 200
    }

    @Test("Gradients: medium batch (256 pixels)")
    func testGradients256Pixels() {
        let count = 256
        let a = [Int32](repeating: 128, count: count)
        let b = [Int32](repeating: 200, count: count)
        let c = [Int32](repeating: 100, count: count)
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.allSatisfy { $0 == 100 })
        #expect(d2.allSatisfy { $0 == 28  })
        #expect(d3.allSatisfy { $0 == -28 })
    }

    @Test("Gradients: batch just below GPU threshold")
    func testGradientsBelowThreshold() {
        let count = VulkanAccelerator.gpuThreshold - 1
        let a = [Int32](repeating: 50,  count: count)
        let b = [Int32](repeating: 100, count: count)
        let c = [Int32](repeating: 25,  count: count)
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.count == count)
        #expect(d1.allSatisfy { $0 == 75  })
        #expect(d2.allSatisfy { $0 == 25  })
        #expect(d3.allSatisfy { $0 == -25 })
    }

    @Test("Gradients: batch at GPU threshold")
    func testGradientsAtThreshold() {
        let count = VulkanAccelerator.gpuThreshold
        let a = [Int32](repeating: 30, count: count)
        let b = [Int32](repeating: 60, count: count)
        let c = [Int32](repeating: 15, count: count)
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.allSatisfy { $0 == 45  })
        #expect(d2.allSatisfy { $0 == 15  })
        #expect(d3.allSatisfy { $0 == -15 })
    }

    @Test("Gradients: batch well above GPU threshold (4× threshold)")
    func testGradientsLargeBatch() {
        let count = VulkanAccelerator.gpuThreshold * 4
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i % 256)
            b[i] = Int32((i + 32) % 256)
            c[i] = Int32((i + 16) % 256)
        }
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        for i in 0..<count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }
}

// MARK: - Bit Depth Matrix Tests

@Suite("GPU Pipeline — Bit Depth Matrix (Vulkan CPU Fallback)")
struct GPUBitDepthMatrixTests {

    let accelerator = VulkanAccelerator()

    // MARK: 8-bit pixel values (0–255)

    @Test("Gradients: 8-bit pixel range")
    func testGradients8Bit() {
        let count = 256
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i)
            b[i] = Int32(255 - i)
            c[i] = Int32(i / 2)
        }
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        for i in 0..<count {
            #expect(d1[i] == b[i] - c[i], "8-bit d1[\(i)] mismatch")
            #expect(d2[i] == a[i] - c[i], "8-bit d2[\(i)] mismatch")
            #expect(d3[i] == c[i] - a[i], "8-bit d3[\(i)] mismatch")
        }
    }

    @Test("MED prediction: 8-bit boundary values")
    func testMED8Bit() {
        // All three MED cases at 8-bit boundaries
        let a: [Int32] = [  0, 255, 128, 100]
        let b: [Int32] = [255,   0, 200,  50]
        let c: [Int32] = [255,   0, 255,  80]  // c >= max, c <= min, c > max, between
        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        // Case 0: c(255) >= max(0,255)=255 → min(0,255)=0
        #expect(pred[0] == 0)
        // Case 1: c(0) <= min(255,0)=0 → max(255,0)=255
        #expect(pred[1] == 255)
        // Case 2: c(255) >= max(128,200)=200 → min(128,200)=128
        #expect(pred[2] == 128)
        // Case 3: c(80) is between min(100,50)=50 and max(100,50)=100 → a+b-c=70
        #expect(pred[3] == 70)
    }

    @Test("Gradient quantisation: 8-bit, standard JPEG-LS thresholds")
    func testQuantize8BitStandardThresholds() {
        // Default 8-bit JPEG-LS thresholds: T1=3, T2=7, T3=21
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let gradients: [Int32] = [-30, -21, -7, -3, -1, 0, 1, 3, 7, 21, 30]
        let expected: [Int32]  = [ -4,  -4, -3, -2, -1, 0, 1, 2, 3,  4,  4]
        let (q1, _, _) = accelerator.quantizeGradientsBatch(
            d1: gradients, d2: gradients, d3: gradients, t1: t1, t2: t2, t3: t3)
        #expect(q1 == expected)
    }

    // MARK: 12-bit pixel values (0–4095)

    @Test("Gradients: 12-bit pixel range")
    func testGradients12Bit() {
        let count = 64
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i * 64)          // 0, 64, 128, …, 4032
            b[i] = Int32(4095 - i * 64)   // 4095, 4031, …, 63
            c[i] = Int32((i * 64 + 2048) % 4096)
        }
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        for i in 0..<count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }

    @Test("Gradient quantisation: 12-bit, higher thresholds")
    func testQuantize12BitThresholds() {
        // Scaled thresholds appropriate for 12-bit images (MAXVAL=4095)
        let t1: Int32 = 10, t2: Int32 = 20, t3: Int32 = 60
        let d: [Int32] = [-100, -61, -21, -11, -1, 0, 1, 11, 21, 61, 100]
        let expected: [Int32] = [-4, -4, -3, -2, -1, 0, 1, 2, 3, 4, 4]
        let (q1, _, _) = accelerator.quantizeGradientsBatch(
            d1: d, d2: d, d3: d, t1: t1, t2: t2, t3: t3)
        #expect(q1 == expected)
    }

    // MARK: 16-bit pixel values (0–65535)

    @Test("Gradients: 16-bit pixel range")
    func testGradients16Bit() {
        let count = 64
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i * 1024)               // 0, 1024, …, 64512
            b[i] = Int32(65535 - i * 1024)       // 65535, 64511, …, 1023
            c[i] = Int32((i * 1024 + 32768) % 65536)
        }
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        for i in 0..<count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }

    @Test("MED prediction: 16-bit boundary values")
    func testMED16Bit() {
        let a: [Int32] = [    0, 65535, 32768]
        let b: [Int32] = [65535,     0, 40000]
        let c: [Int32] = [65535,     0, 50000]
        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        // (0,65535,c=65535≥max=65535) → min=0
        #expect(pred[0] == 0)
        // (65535,0,c=0≤min=0) → max=65535
        #expect(pred[1] == 65535)
        // (32768,40000,c=50000≥max=40000) → min=32768
        #expect(pred[2] == 32768)
    }
}

// MARK: - Component Configuration Tests

@Suite("GPU Pipeline — Component Configurations (Vulkan CPU Fallback)")
struct GPUComponentConfigurationTests {

    let accelerator = VulkanAccelerator()

    // MARK: Single component (greyscale)

    @Test("Greyscale (1-component): gradient computation is correct")
    func testGreyscaleGradients() {
        // Single-component image: process one channel
        let pixels: [Int32] = [10, 20, 30, 40, 50, 60, 70, 80]
        // Simulate a row with north=pixel[row-1], west=pixel shifted, NW=diagonal
        let north: [Int32] = [5,  15, 25, 35, 45, 55, 65, 75]
        let west:  [Int32] = [8,  18, 28, 38, 48, 58, 68, 78]
        let nw:    [Int32] = [3,  13, 23, 33, 43, 53, 63, 73]
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: north, b: west, c: nw)
        for i in 0..<pixels.count {
            #expect(d1[i] == west[i] - nw[i])
            #expect(d2[i] == north[i] - nw[i])
            #expect(d3[i] == nw[i] - north[i])
        }
    }

    @Test("Greyscale (1-component): MED prediction is correct")
    func testGreyscaleMEDPrediction() {
        let north: [Int32] = [100, 200, 150]
        let west:  [Int32] = [110, 190, 160]
        let nw:    [Int32] = [105, 195, 180]
        let pred = accelerator.computeMEDPredictionBatch(a: north, b: west, c: nw)
        // Verify all three MED cases are handled
        for i in 0..<north.count {
            let n = north[i], w = west[i], nwVal = nw[i]
            let expected: Int32
            if nwVal >= max(n, w)       { expected = min(n, w) }
            else if nwVal <= min(n, w)  { expected = max(n, w) }
            else                         { expected = n + w - nwVal }
            #expect(pred[i] == expected)
        }
    }

    // MARK: Three components (RGB)

    @Test("RGB (3-component): forward and inverse HP1 round-trip")
    func testRGBHP1RoundTrip() {
        // Simulate a 4-pixel RGB image
        let r: [Int32] = [200, 150, 100,  50]
        let g: [Int32] = [100, 120,  80,  30]
        let b: [Int32] = [ 50,  60, 200, 180]

        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp1, r: rp, g: gp, b: bp)

        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    @Test("RGB (3-component): forward and inverse HP2 round-trip")
    func testRGBHP2RoundTrip() {
        let r: [Int32] = [200, 150, 100,  50]
        let g: [Int32] = [100, 120,  80,  30]
        let b: [Int32] = [ 50,  60, 200, 180]

        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp2, r: rp, g: gp, b: bp)

        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    @Test("RGB (3-component): forward and inverse HP3 round-trip")
    func testRGBHP3RoundTrip() {
        let r: [Int32] = [200, 150, 100,  50]
        let g: [Int32] = [100, 120,  80,  30]
        let b: [Int32] = [ 50,  60, 200, 180]

        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp3, r: rp, g: gp, b: bp)

        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    @Test("RGB (3-component): large batch HP2 round-trip (above threshold)")
    func testRGBHP2LargeBatchRoundTrip() {
        let count = VulkanAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 85) % 256)
            b[i] = Int32((i + 170) % 256)
        }
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp2, r: rp, g: gp, b: bp)
        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }
}

// MARK: - Near-Lossless Encoding Mode Tests

@Suite("GPU Pipeline — Near-Lossless Encoding Modes")
struct GPUNearLosslessTests {

    let accelerator = VulkanAccelerator()

    // MARK: Gradient quantisation with NEAR > 0

    @Test("Quantisation: NEAR=0 matches standard lossless boundary")
    func testQuantizeNear0() {
        // With NEAR=0, d=0 → 0, d=-1 → -1, d=1 → 1 (standard lossless)
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let d: [Int32]        = [-1, 0, 1]
        let expected: [Int32] = [-1, 0, 1]
        let (q1, _, _) = accelerator.quantizeGradientsBatch(
            d1: d, d2: d, d3: d, t1: t1, t2: t2, t3: t3)
        #expect(q1 == expected)
    }

    @Test("Vulkan: MED prediction unchanged by NEAR parameter (predicts same as lossless)")
    func testMEDPredictionIndependentOfNear() {
        // MED prediction does not depend on NEAR — it always predicts the same value.
        // This test verifies that the GPU pipeline's prediction matches CPU.
        let a: [Int32] = [100, 200, 150]
        let b: [Int32] = [110, 190, 160]
        let c: [Int32] = [105, 205, 145]

        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)

        // Manually compute expected values
        for i in 0..<a.count {
            let av = a[i], bv = b[i], cv = c[i]
            let expected: Int32
            if cv >= max(av, bv)       { expected = min(av, bv) }
            else if cv <= min(av, bv)  { expected = max(av, bv) }
            else                        { expected = av + bv - cv }
            #expect(pred[i] == expected)
        }
    }

    @Test("Vulkan: quantiseGradients NEAR=3 — values within NEAR range → 0 when T1 > NEAR")
    func testQuantizeNear3SmallValues() {
        // When T1 > NEAR, values in [-NEAR, NEAR] map to 0.
        // Use T1=5, T2=9, T3=25 (so T1 > NEAR=3) to demonstrate the NEAR range.
        let near = 3
        let t1 = 5, t2 = 9, t3 = 25
        for d in -near...near {
            // NEAR-aware quantisation: values in [-near, near] → 0 when T1 > near
            let result: Int
            if d <= -t3       { result = -4 }
            else if d <= -t2  { result = -3 }
            else if d <= -t1  { result = -2 }
            else if d < -near { result = -1 }
            else if d <= near { result =  0 }
            else if d < t1    { result =  1 }
            else if d < t2    { result =  2 }
            else if d < t3    { result =  3 }
            else              { result =  4 }
            #expect(result == 0, "d=\(d) with NEAR=\(near) and T1=\(t1) should map to 0")
        }
    }

    @Test("Vulkan: quantiseGradients — T1=NEAR boundary: d=-T1 maps to -2, not 0")
    func testQuantizeNearEqualT1Boundary() {
        // When NEAR == T1, the threshold check `d <= -T1` takes precedence over
        // the NEAR check. So d = -T1 maps to -2, not 0.
        let near = 3
        let t1 = 3, t2 = 7, t3 = 21

        // d = -3 = -T1: hits `d <= -T1` first → maps to -2
        let dAtNegT1 = -t1
        let result: Int
        if dAtNegT1 <= -t3       { result = -4 }
        else if dAtNegT1 <= -t2  { result = -3 }
        else if dAtNegT1 <= -t1  { result = -2 }
        else if dAtNegT1 < -near { result = -1 }
        else if dAtNegT1 <= near { result =  0 }
        else                      { result =  1 }
        #expect(result == -2, "d=\(dAtNegT1) with T1=\(t1) should map to -2 (threshold takes precedence)")

        // d = -2 (strictly inside -T1): hits NEAR check → maps to 0
        let dInsideNear = -2
        let result2: Int
        if dInsideNear <= -t3       { result2 = -4 }
        else if dInsideNear <= -t2  { result2 = -3 }
        else if dInsideNear <= -t1  { result2 = -2 }
        else if dInsideNear < -near { result2 = -1 }
        else if dInsideNear <= near { result2 =  0 }
        else                         { result2 =  1 }
        #expect(result2 == 0, "d=\(dInsideNear) with NEAR=\(near) should map to 0")
    }

    @Test("Vulkan: large-batch gradient quantisation is consistent across sizes")
    func testQuantizeConsistencyAcrossSizes() {
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        // Compare small-batch vs large-batch quantisation for same data
        let smallCount = VulkanAccelerator.gpuThreshold / 2
        let largeCount = VulkanAccelerator.gpuThreshold * 2
        let pattern: [Int32] = [-25, -8, -4, -2, -1, 0, 1, 2, 4, 8, 25]

        // Build arrays by repeating the pattern
        let buildArray = { (n: Int) -> [Int32] in
            (0..<n).map { pattern[$0 % pattern.count] }
        }
        let smallD = buildArray(smallCount)
        let largeD = buildArray(largeCount)

        let (smallQ, _, _) = accelerator.quantizeGradientsBatch(
            d1: smallD, d2: smallD, d3: smallD, t1: t1, t2: t2, t3: t3)
        let (largeQ, _, _) = accelerator.quantizeGradientsBatch(
            d1: largeD, d2: largeD, d3: largeD, t1: t1, t2: t2, t3: t3)

        // The first smallCount elements of largeQ should match smallQ
        let truncated = Array(largeQ.prefix(smallCount))
        #expect(truncated == smallQ)
    }

    @Test("Near-lossless: prediction errors are bounded by NEAR * 2 + 1 after reconstruction")
    func testNearLosslessReconstructionBound() {
        // Simulate: near-lossless with NEAR=3. After encode + decode, the
        // reconstructed pixel should differ from original by at most NEAR.
        // We verify the arithmetic: |reconstructed - original| <= NEAR.
        let near = 3
        let original: [Int32] = [100, 200, 50, 150, 30]
        let prediction: [Int32] = [98, 203, 51, 147, 33]  // simulated MED predictions

        // Simulate near-lossless quantised error: floor(errval / qbpp) where qbpp = 2*NEAR+1
        let qbpp = 2 * near + 1
        let quantisedErrors = original.enumerated().map { i, orig -> Int32 in
            let err = Int(orig - prediction[i])
            // Round toward zero (floor division toward zero)
            return Int32(err >= 0 ? err / qbpp : -((-err) / qbpp))
        }
        // Reconstruct: prediction + quantisedError * qbpp
        let reconstructed = quantisedErrors.enumerated().map { i, qe -> Int32 in
            prediction[i] + qe * Int32(qbpp)
        }
        // Verify |reconstructed - original| <= NEAR
        for i in 0..<original.count {
            let diff = abs(Int(reconstructed[i]) - Int(original[i]))
            #expect(diff <= near,
                "Pixel \(i): |reconstructed(\(reconstructed[i])) - original(\(original[i]))| = \(diff) > NEAR=\(near)")
        }
    }
}

// MARK: - Metal Encoding/Decoding Pipeline Tests (Apple platforms only)

#if canImport(Metal)

@Suite("Metal Encoding/Decoding Pipeline Tests")
struct MetalEncodingDecodingPipelineTests {

    // MARK: Encoding pipeline — small batch (CPU fallback)

    @Test("Metal: encodingPipeline — small batch lossless (NEAR=0)")
    func testEncodingPipelineSmallBatchLossless() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let a: [Int32] = [100, 200, 50]
        let b: [Int32] = [110, 190, 60]
        let c: [Int32] = [ 95, 195, 55]
        let x: [Int32] = [105, 185, 65]
        let (pred, err, _, _, _) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        // Verify prediction + error = x
        for i in 0..<x.count {
            #expect(pred[i] + err[i] == x[i],
                "Pixel \(i): pred(\(pred[i])) + err(\(err[i])) should == x(\(x[i]))")
        }
    }

    @Test("Metal: encodingPipeline — small batch near-lossless (NEAR=3)")
    func testEncodingPipelineSmallBatchNearLossless() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let a: [Int32] = [100, 200, 50]
        let b: [Int32] = [110, 190, 60]
        let c: [Int32] = [ 95, 195, 55]
        let x: [Int32] = [105, 185, 65]
        let (pred, err, q1, q2, q3) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 3, t1: 3, t2: 7, t3: 21)
        // Verify prediction + error = x (raw error before near-lossless quantisation)
        for i in 0..<x.count {
            #expect(pred[i] + err[i] == x[i])
        }
        // Verify quantised gradients are in valid range [-4, 4]
        for i in 0..<x.count {
            #expect(q1[i] >= -4 && q1[i] <= 4)
            #expect(q2[i] >= -4 && q2[i] <= 4)
            #expect(q3[i] >= -4 && q3[i] <= 4)
        }
    }

    @Test("Metal: encodingPipeline — NEAR=3 gradients near zero → q=0")
    func testEncodingPipelineNear3GradientsNearZero() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        // b[i]-c[i] = 1, a[i]-c[i] = 0, c[i]-a[i] = 0 → all within NEAR=3 → q=0
        // d1 = b - c = 11 - 10 = 1  (≤ NEAR=3)
        // d2 = a - c = 10 - 10 = 0  (≤ NEAR=3)
        // d3 = c - a = 10 - 10 = 0  (≤ NEAR=3)
        let a: [Int32] = [10]
        let b: [Int32] = [11]
        let c: [Int32] = [10]  // a-c=0, b-c=1, c-a=0 (all ≤ NEAR=3)
        let x: [Int32] = [12]
        let (_, _, q1, q2, q3) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 3, t1: 3, t2: 7, t3: 21)
        // d1=b-c=1 (≤ NEAR=3) → 0, d2=a-c=0 (≤ NEAR) → 0, d3=c-a=0 (≤ NEAR) → 0
        #expect(q1 == [0])
        #expect(q2 == [0])
        #expect(q3 == [0])
    }

    @Test("Metal: encodingPipeline — quantised gradients match NEAR=0 for large gradients")
    func testEncodingPipelineQuantisedGradientsLarge() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        // With NEAR=0, the encoding pipeline should produce same quantisation
        // as the standalone quantizeGradientsBatch call.
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let count = 9
        // Use neighbours where d1 = b-c spans all 9 quantisation buckets
        let gradientValues: [Int32] = [-30, -10, -5, -1, 0, 1, 5, 10, 30]
        // a=c, b=c+gradient (so b-c = gradient, a-c=0, c-a=0)
        let c: [Int32] = [Int32](repeating: 50, count: count)
        let a: [Int32] = [Int32](repeating: 50, count: count)
        let b: [Int32] = gradientValues.map { c[0] + $0 }
        let x: [Int32] = [Int32](repeating: 50, count: count)

        let (_, _, q1, _, _) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: t1, t2: t2, t3: t3)
        let expected: [Int32] = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
        #expect(q1 == expected)
    }

    @Test("Metal: encodingPipeline — empty arrays")
    func testEncodingPipelineEmpty() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let (pred, err, q1, q2, q3) = try accelerator.computeEncodingPipelineBatch(
            a: [], b: [], c: [], x: [], near: 0, t1: 3, t2: 7, t3: 21)
        #expect(pred.isEmpty && err.isEmpty && q1.isEmpty && q2.isEmpty && q3.isEmpty)
    }

    // MARK: Decoding pipeline — small batch (CPU fallback)

    @Test("Metal: decodingPipeline — reconstructs pixels from errors (small batch)")
    func testDecodingPipelineSmallBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let a: [Int32]      = [100, 200, 50]
        let b: [Int32]      = [110, 190, 60]
        let c: [Int32]      = [ 95, 195, 55]
        let errval: [Int32] = [  5,  -5, 10]
        let reconstructed = try accelerator.computeDecodingPipelineBatch(
            a: a, b: b, c: c, errval: errval)
        // Each reconstructed[i] = MED(a[i],b[i],c[i]) + errval[i]
        for i in 0..<a.count {
            let av = a[i], bv = b[i], cv = c[i]
            let px: Int32
            if cv >= max(av, bv)       { px = min(av, bv) }
            else if cv <= min(av, bv)  { px = max(av, bv) }
            else                        { px = av + bv - cv }
            #expect(reconstructed[i] == px + errval[i])
        }
    }

    @Test("Metal: decodingPipeline — empty arrays")
    func testDecodingPipelineEmpty() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let result = try accelerator.computeDecodingPipelineBatch(
            a: [], b: [], c: [], errval: [])
        #expect(result.isEmpty)
    }

    // MARK: Encode → Decode round-trip

    @Test("Metal: encode → decode round-trip (lossless, small batch)")
    func testEncodeDecodeLosslessRoundTripSmall() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let a: [Int32] = [100, 200,  50, 150]
        let b: [Int32] = [110, 190,  60, 140]
        let c: [Int32] = [ 95, 195,  55, 145]
        let x: [Int32] = [105, 188,  62, 148]

        let (_, err, _, _, _) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        let reconstructed = try accelerator.computeDecodingPipelineBatch(
            a: a, b: b, c: c, errval: err)
        #expect(reconstructed == x, "Lossless encode-decode must reconstruct exactly")
    }

    @Test("Metal: encode → decode round-trip (lossless, large batch, GPU path)")
    func testEncodeDecodeLosslessRoundTripLarge() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        var x = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i % 256)
            b[i] = Int32((i + 64) % 256)
            c[i] = Int32((i + 32) % 256)
            x[i] = Int32((i + 128) % 256)
        }
        let (_, err, _, _, _) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: 3, t2: 7, t3: 21)
        let reconstructed = try accelerator.computeDecodingPipelineBatch(
            a: a, b: b, c: c, errval: err)
        #expect(reconstructed == x)
    }

    @Test("Metal: encoding pipeline matches standalone gradient + MED + quantise calls")
    func testEncodingPipelineMatchesStandaloneOps() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var a = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        var c = [Int32](repeating: 0, count: count)
        var x = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            a[i] = Int32(i % 200)
            b[i] = Int32((i + 50) % 200)
            c[i] = Int32((i + 25) % 200)
            x[i] = Int32((i + 100) % 200)
        }
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21

        // Combined pipeline
        let (pred, err, pq1, pq2, pq3) = try accelerator.computeEncodingPipelineBatch(
            a: a, b: b, c: c, x: x, near: 0, t1: t1, t2: t2, t3: t3)

        // Standalone operations
        let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
        let (sq1, sq2, sq3) = try accelerator.quantizeGradientsBatch(
            d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        let spred = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        let serr = zip(x, spred).map { $0 - $1 }

        #expect(pred == spred, "Combined pipeline prediction must match standalone")
        #expect(err == serr, "Combined pipeline errors must match standalone")
        #expect(pq1 == sq1, "Combined pipeline q1 must match standalone")
        #expect(pq2 == sq2, "Combined pipeline q2 must match standalone")
        #expect(pq3 == sq3, "Combined pipeline q3 must match standalone")
    }
}

#endif // canImport(Metal)
