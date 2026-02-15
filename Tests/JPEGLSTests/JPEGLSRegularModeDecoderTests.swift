/// Tests for JPEG-LS regular mode decoding implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Regular Mode Decoder Tests")
struct JPEGLSRegularModeDecoderTests {
    
    // MARK: - Test Helpers
    
    /// Create default preset parameters for testing
    func createDefaultParameters() throws -> JPEGLSPresetParameters {
        return try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 3,
            threshold2: 7,
            threshold3: 21,
            reset: 64
        )
    }
    
    /// Create a context model for testing
    func createContextModel() throws -> JPEGLSContextModel {
        let params = try createDefaultParameters()
        return try JPEGLSContextModel(parameters: params, near: 0)
    }
    
    // MARK: - Initialization Tests
    
    @Test("Initialize with valid parameters")
    func testInitialization() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Should initialize without throwing
        #expect(decoder != nil)
    }
    
    @Test("Initialize with near-lossless parameter")
    func testInitializationNearLossless() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 5)
        
        // Should initialize without throwing
        #expect(decoder != nil)
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNearParameter() throws {
        let params = try createDefaultParameters()
        
        // NEAR must be in range [0, 255]
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRegularModeDecoder(parameters: params, near: -1)
        }
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRegularModeDecoder(parameters: params, near: 256)
        }
    }
    
    // MARK: - Gradient Computation Tests
    
    @Test("Compute gradients with typical values")
    func testComputeGradients() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Test with typical neighbor values:
        //   c=100  b=105
        //   a=102  x=?
        let (d1, d2, d3) = decoder.computeGradients(a: 102, b: 105, c: 100)
        
        #expect(d1 == 3)   // D1 = b - a = 105 - 102
        #expect(d2 == -5)  // D2 = c - b = 100 - 105
        #expect(d3 == -2)  // D3 = c - a = 100 - 102
    }
    
    @Test("Compute gradients with flat region")
    func testComputeGradientsFlatRegion() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // All neighbors have same value (flat region)
        let (d1, d2, d3) = decoder.computeGradients(a: 128, b: 128, c: 128)
        
        #expect(d1 == 0)
        #expect(d2 == 0)
        #expect(d3 == 0)
    }
    
    @Test("Compute gradients with edge transition")
    func testComputeGradientsEdge() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Sharp edge
        let (d1, d2, d3) = decoder.computeGradients(a: 200, b: 50, c: 50)
        
        #expect(d1 == -150)  // D1 = b - a = 50 - 200
        #expect(d2 == 0)     // D2 = c - b = 50 - 50
        #expect(d3 == -150)  // D3 = c - a = 50 - 200
    }
    
    // MARK: - Gradient Quantization Tests
    
    @Test("Quantize gradient to zero for small values")
    func testQuantizeGradientSmall() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Gradients == 0 quantize to 0
        #expect(decoder.quantizeGradient(0) == 0)
    }
    
    @Test("Quantize gradient using T1 threshold")
    func testQuantizeGradientT1() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Gradients in range (NEAR, T1] should quantize to ±1
        #expect(decoder.quantizeGradient(1) == 1)
        #expect(decoder.quantizeGradient(3) == 1)   // T1 = 3
        #expect(decoder.quantizeGradient(-1) == -1)
        #expect(decoder.quantizeGradient(-3) == -1)
    }
    
    @Test("Quantize gradient using T2 threshold")
    func testQuantizeGradientT2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Gradients in range (T1, T2] should quantize to ±2
        #expect(decoder.quantizeGradient(4) == 2)
        #expect(decoder.quantizeGradient(7) == 2)   // T2 = 7
        #expect(decoder.quantizeGradient(-4) == -2)
        #expect(decoder.quantizeGradient(-7) == -2)
    }
    
    @Test("Quantize gradient using T3 threshold")
    func testQuantizeGradientT3() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Gradients in range (T2, T3] should quantize to ±3
        #expect(decoder.quantizeGradient(8) == 3)
        #expect(decoder.quantizeGradient(21) == 3)   // T3 = 21
        #expect(decoder.quantizeGradient(-8) == -3)
        #expect(decoder.quantizeGradient(-21) == -3)
    }
    
    @Test("Quantize gradient beyond T3")
    func testQuantizeGradientLarge() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Gradients > T3 should quantize to ±4
        #expect(decoder.quantizeGradient(22) == 4)
        #expect(decoder.quantizeGradient(100) == 4)
        #expect(decoder.quantizeGradient(-22) == -4)
        #expect(decoder.quantizeGradient(-100) == -4)
    }
    
    // MARK: - MED Prediction Tests
    
    @Test("MED prediction when c >= max(a, b)")
    func testMEDPredictionCase1() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // When c >= max(a, b), predict min(a, b)
        let prediction = decoder.computeMEDPrediction(a: 120, b: 100, c: 150)
        #expect(prediction == 100)  // min(120, 100)
    }
    
    @Test("MED prediction when c <= min(a, b)")
    func testMEDPredictionCase2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // When c <= min(a, b), predict max(a, b)
        let prediction = decoder.computeMEDPrediction(a: 120, b: 100, c: 50)
        #expect(prediction == 120)  // max(120, 100)
    }
    
    @Test("MED prediction in general case")
    func testMEDPredictionCase3() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Otherwise, predict a + b - c
        let prediction = decoder.computeMEDPrediction(a: 110, b: 120, c: 115)
        #expect(prediction == 115)  // 110 + 120 - 115
    }
    
    @Test("MED prediction with flat region")
    func testMEDPredictionFlat() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // All neighbors same value
        let prediction = decoder.computeMEDPrediction(a: 128, b: 128, c: 128)
        #expect(prediction == 128)
    }
    
    // MARK: - Bias Correction Tests
    
    @Test("Apply positive bias correction")
    func testBiasCorrectionPositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let corrected = decoder.applyBiasCorrection(
            prediction: 100,
            biasC: 5,
            sign: 1
        )
        #expect(corrected == 105)  // 100 + 1 * 5
    }
    
    @Test("Apply negative bias correction")
    func testBiasCorrectionNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let corrected = decoder.applyBiasCorrection(
            prediction: 100,
            biasC: 5,
            sign: -1
        )
        #expect(corrected == 95)  // 100 + (-1) * 5
    }
    
    @Test("Bias correction clamped to MAXVAL")
    func testBiasCorrectionClampedMax() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let corrected = decoder.applyBiasCorrection(
            prediction: 250,
            biasC: 10,
            sign: 1
        )
        #expect(corrected == 255)  // Clamped to MAXVAL
    }
    
    @Test("Bias correction clamped to zero")
    func testBiasCorrectionClampedMin() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let corrected = decoder.applyBiasCorrection(
            prediction: 5,
            biasC: 10,
            sign: -1
        )
        #expect(corrected == 0)  // Clamped to 0
    }
    
    // MARK: - Golomb-Rice Decoding Tests
    
    @Test("Golomb decode with k=0")
    func testGolombDecodeK0() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // value = (unaryCount << k) | remainder
        // With k=0, unaryCount=5, remainder=0: value = 5
        let value = decoder.golombDecode(unaryCount: 5, remainder: 0, k: 0)
        #expect(value == 5)
    }
    
    @Test("Golomb decode with k=2")
    func testGolombDecodeK2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // value = (3 << 2) | 1 = 12 | 1 = 13
        let value = decoder.golombDecode(unaryCount: 3, remainder: 1, k: 2)
        #expect(value == 13)
    }
    
    @Test("Golomb decode with k=4")
    func testGolombDecodeK4() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // value = (1 << 4) | 9 = 16 | 9 = 25
        let value = decoder.golombDecode(unaryCount: 1, remainder: 9, k: 4)
        #expect(value == 25)
    }
    
    @Test("Golomb decode zero value")
    func testGolombDecodeZero() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // value = (0 << k) | 0 = 0
        let value = decoder.golombDecode(unaryCount: 0, remainder: 0, k: 2)
        #expect(value == 0)
    }
    
    @Test("Golomb bit length calculation")
    func testGolombBitLength() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // With k=2, value=13:
        // quotient = 13 >> 2 = 3
        // unary length = 3 + 1 = 4
        // total = 4 + 2 = 6
        let bitLength = decoder.golombBitLength(value: 13, k: 2)
        #expect(bitLength == 6)
    }
    
    // MARK: - Error Unmapping Tests
    
    @Test("Unmap positive error (even value)")
    func testUnmapErrorPositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Even values map to positive errors
        #expect(decoder.unmapError(0) == 0)     // 0 / 2 = 0
        #expect(decoder.unmapError(10) == 5)    // 10 / 2 = 5
        #expect(decoder.unmapError(20) == 10)   // 20 / 2 = 10
    }
    
    @Test("Unmap negative error (odd value)")
    func testUnmapErrorNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Odd values map to negative errors
        #expect(decoder.unmapError(1) == -1)    // -(1+1)/2 = -1
        #expect(decoder.unmapError(9) == -5)    // -(9+1)/2 = -5
        #expect(decoder.unmapError(19) == -10)  // -(19+1)/2 = -10
    }
    
    @Test("Error unmapping is inverse of mapping")
    func testUnmapIsInverseOfMap() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: 0)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // Test round-trip for various errors
        for error in [-50, -10, -5, -1, 0, 1, 5, 10, 50] {
            let mapped = encoder.mapErrorToNonNegative(error)
            let unmapped = decoder.unmapError(mapped)
            #expect(unmapped == error, "Round-trip failed for error \(error)")
        }
    }
    
    // MARK: - Sample Reconstruction Tests
    
    @Test("Reconstruct sample with positive error")
    func testReconstructSamplePositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let sample = decoder.reconstructSample(prediction: 100, error: 5)
        #expect(sample == 105)  // 100 + 5
    }
    
    @Test("Reconstruct sample with negative error")
    func testReconstructSampleNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        let sample = decoder.reconstructSample(prediction: 100, error: -5)
        #expect(sample == 95)  // 100 - 5
    }
    
    @Test("Reconstruct sample at upper boundary")
    func testReconstructSampleUpperBoundary() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // prediction=250, error=5 should give 255 (at MAXVAL boundary)
        let sample = decoder.reconstructSample(prediction: 250, error: 5)
        #expect(sample == 255)
    }
    
    @Test("Reconstruct sample at lower boundary")
    func testReconstructSampleLowerBoundary() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // prediction=5, error=-5 should give 0 (at zero boundary)
        let sample = decoder.reconstructSample(prediction: 5, error: -5)
        #expect(sample == 0)
    }
    
    @Test("Reconstruct sample with modular wraparound positive")
    func testReconstructSampleModularPositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // With RANGE=256, if prediction + error > MAXVAL, we wrap around
        // prediction=250, error=20 -> 270, 270 > 255, so 270 - 256 = 14
        let sample = decoder.reconstructSample(prediction: 250, error: 20)
        #expect(sample == 14)  // Wraparound due to modular arithmetic
    }
    
    @Test("Reconstruct sample with modular wraparound negative")
    func testReconstructSampleModularNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        
        // With RANGE=256, if prediction + error < 0, we wrap around
        // prediction=5, error=-10 -> -5, -5 < 0, so -5 + 256 = 251
        let sample = decoder.reconstructSample(prediction: 5, error: -10)
        #expect(sample == 251)  // Wraparound due to modular arithmetic
    }
    
    // MARK: - Complete Decoding Pipeline Tests
    
    @Test("Decode pixel in flat region")
    func testDecodePixelFlat() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // Flat region: all neighbors same value, mappedError = 0
        let result = decoder.decodePixel(
            mappedError: 0,
            a: 128,
            b: 128,
            c: 128,
            context: context
        )
        
        // In flat region with zero error, should reconstruct same value
        #expect(result.error == 0)
        #expect(result.sample == 128)
    }
    
    @Test("Decode pixel with small positive error")
    func testDecodePixelSmallPositiveError() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // mappedError = 10 -> error = 5
        let result = decoder.decodePixel(
            mappedError: 10,
            a: 120,
            b: 120,
            c: 120,
            context: context
        )
        
        #expect(result.error == 5)
        #expect(result.sample == 125)  // 120 + 5
    }
    
    @Test("Decode pixel with small negative error")
    func testDecodePixelSmallNegativeError() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // mappedError = 9 -> error = -5
        let result = decoder.decodePixel(
            mappedError: 9,
            a: 120,
            b: 120,
            c: 120,
            context: context
        )
        
        #expect(result.error == -5)
        #expect(result.sample == 115)  // 120 - 5
    }
    
    @Test("Decoded pixel has valid context index")
    func testDecodedPixelContextIndex() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        let result = decoder.decodePixel(
            mappedError: 4,
            a: 100,
            b: 105,
            c: 102,
            context: context
        )
        
        // Should have computed a valid context index
        #expect(result.contextIndex >= 0)
        #expect(result.contextIndex < JPEGLSContextModel.regularContextCount)
    }
    
    // MARK: - Encode-Decode Round-Trip Tests
    
    @Test("Round-trip encoding and decoding")
    func testRoundTripEncodeDecode() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: 0)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        var context = try createContextModel()
        
        // Original pixel values
        let actualPixel = 125
        let a = 120
        let b = 122
        let c = 118
        
        // Encode
        let encoded = encoder.encodePixel(
            actual: actualPixel,
            a: a,
            b: b,
            c: c,
            context: context
        )
        
        // Decode using the mapped error from encoding
        let decoded = decoder.decodePixel(
            mappedError: encoded.mappedError,
            a: a,
            b: b,
            c: c,
            context: context
        )
        
        // Should recover the original pixel
        #expect(decoded.sample == actualPixel, "Round-trip failed: encoded \(actualPixel), decoded \(decoded.sample)")
        
        // Update context
        context.updateContext(
            contextIndex: encoded.contextIndex,
            predictionError: encoded.error,
            sign: encoded.sign
        )
    }
    
    @Test("Round-trip with multiple pixels")
    func testRoundTripMultiplePixels() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: 0)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        var encodeContext = try createContextModel()
        var decodeContext = try createContextModel()
        
        // Test pixels with various values
        let pixels = [100, 102, 105, 103, 104, 150, 200, 50, 128]
        
        var a = 100  // Initial neighbors
        var b = 100
        var c = 100
        
        for actualPixel in pixels {
            // Encode
            let encoded = encoder.encodePixel(
                actual: actualPixel,
                a: a,
                b: b,
                c: c,
                context: encodeContext
            )
            
            // Decode
            let decoded = decoder.decodePixel(
                mappedError: encoded.mappedError,
                a: a,
                b: b,
                c: c,
                context: decodeContext
            )
            
            // Verify round-trip
            #expect(decoded.sample == actualPixel, "Round-trip failed for pixel \(actualPixel): got \(decoded.sample)")
            
            // Update both contexts identically
            encodeContext.updateContext(
                contextIndex: encoded.contextIndex,
                predictionError: encoded.error,
                sign: encoded.sign
            )
            decodeContext.updateContext(
                contextIndex: decoded.contextIndex,
                predictionError: decoded.error,
                sign: decoded.sign
            )
            
            // Update neighbors for next pixel
            c = b
            b = actualPixel
            a = actualPixel
        }
    }
    
    @Test("Round-trip at value boundaries")
    func testRoundTripBoundaries() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: 0)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // Test boundary values
        let boundaryTests: [(actual: Int, a: Int, b: Int, c: Int)] = [
            (0, 0, 0, 0),       // All zero
            (255, 255, 255, 255), // All max
            (0, 128, 128, 128),   // Zero in middle region
            (255, 128, 128, 128), // Max in middle region
            (128, 0, 0, 0),       // Middle from zero
            (128, 255, 255, 255), // Middle from max
        ]
        
        for (actual, a, b, c) in boundaryTests {
            let encoded = encoder.encodePixel(actual: actual, a: a, b: b, c: c, context: context)
            let decoded = decoder.decodePixel(mappedError: encoded.mappedError, a: a, b: b, c: c, context: context)
            
            #expect(decoded.sample == actual, "Boundary test failed: expected \(actual), got \(decoded.sample)")
        }
    }
    
    // MARK: - Helper Method Tests
    
    @Test("Get Golomb parameter")
    func testGetGolombParameter() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        let k = decoder.getGolombParameter(a: 120, b: 120, c: 120, context: context)
        
        // Should return non-negative Golomb parameter
        #expect(k >= 0)
    }
    
    @Test("Get context index")
    func testGetContextIndex() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        let index = decoder.getContextIndex(a: 120, b: 120, c: 120, context: context)
        
        // Should return valid context index
        #expect(index >= 0)
        #expect(index < JPEGLSContextModel.regularContextCount)
    }
    
    @Test("Get context sign")
    func testGetContextSign() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        let sign = decoder.getContextSign(a: 120, b: 120, c: 120, context: context)
        
        // Should return +1 or -1
        #expect(sign == 1 || sign == -1)
    }
    
    @Test("Decode pixel from bits")
    func testDecodePixelFromBits() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: 0)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        let actual = 125
        let a = 120
        let b = 122
        let c = 118
        
        // Encode to get unary and remainder
        let encoded = encoder.encodePixel(actual: actual, a: a, b: b, c: c, context: context)
        
        // Decode using unary count (unaryLength - 1) and remainder
        let decoded = decoder.decodePixelFromBits(
            unaryCount: encoded.unaryLength - 1,  // quotient
            remainder: encoded.remainder,
            a: a,
            b: b,
            c: c,
            context: context
        )
        
        #expect(decoded.sample == actual)
    }
    
    // MARK: - Near-Lossless Mode Tests
    
    @Test("Decode in near-lossless mode")
    func testDecodeNearLossless() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 2)
        let context = try JPEGLSContextModel(parameters: params, near: 2)
        
        let result = decoder.decodePixel(
            mappedError: 4,
            a: 120,
            b: 122,
            c: 118,
            context: context
        )
        
        // Should decode successfully in near-lossless mode
        #expect(result.contextIndex >= 0)
        #expect(result.sample >= 0)
        #expect(result.sample <= 255)
    }
    
    @Test("Near-lossless round-trip within tolerance")
    func testNearLosslessRoundTrip() throws {
        let near = 2
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRegularMode(parameters: params, near: near)
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: near)
        let context = try JPEGLSContextModel(parameters: params, near: near)
        
        let actual = 125
        let a = 120
        let b = 122
        let c = 118
        
        // Encode
        let encoded = encoder.encodePixel(actual: actual, a: a, b: b, c: c, context: context)
        
        // Decode
        let decoded = decoder.decodePixel(mappedError: encoded.mappedError, a: a, b: b, c: c, context: context)
        
        // In near-lossless, decoded should be within NEAR of actual
        let diff = abs(decoded.sample - actual)
        #expect(diff <= near, "Near-lossless error \(diff) exceeds NEAR=\(near)")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Decode pixel at MAXVAL")
    func testDecodePixelMaxVal() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // All pixels at maximum value, zero error
        let result = decoder.decodePixel(
            mappedError: 0,
            a: 255,
            b: 255,
            c: 255,
            context: context
        )
        
        #expect(result.error == 0)
        #expect(result.sample == 255)
    }
    
    @Test("Decode pixel at zero")
    func testDecodePixelZero() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
        let context = try createContextModel()
        
        // All pixels at minimum value, zero error
        let result = decoder.decodePixel(
            mappedError: 0,
            a: 0,
            b: 0,
            c: 0,
            context: context
        )
        
        #expect(result.error == 0)
        #expect(result.sample == 0)
    }
    
    @Test("DecodedPixel struct equality")
    func testDecodedPixelEquality() throws {
        let pixel1 = DecodedPixel(
            contextIndex: 100,
            sign: 1,
            prediction: 120,
            mappedError: 10,
            error: 5,
            sample: 125
        )
        
        let pixel2 = DecodedPixel(
            contextIndex: 100,
            sign: 1,
            prediction: 120,
            mappedError: 10,
            error: 5,
            sample: 125
        )
        
        let pixel3 = DecodedPixel(
            contextIndex: 100,
            sign: 1,
            prediction: 120,
            mappedError: 10,
            error: 5,
            sample: 126  // Different sample
        )
        
        #expect(pixel1 == pixel2)
        #expect(pixel1 != pixel3)
    }
}
