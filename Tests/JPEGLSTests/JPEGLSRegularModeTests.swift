/// Tests for JPEG-LS regular mode encoding implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Regular Mode Tests")
struct JPEGLSRegularModeTests {
    
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
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Should initialize without throwing
        #expect(regularMode != nil)
    }
    
    @Test("Initialize with near-lossless parameter")
    func testInitializationNearLossless() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 5)
        
        // Should initialize without throwing
        #expect(regularMode != nil)
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNearParameter() throws {
        let params = try createDefaultParameters()
        
        // NEAR must be in range [0, 255]
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRegularMode(parameters: params, near: -1)
        }
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRegularMode(parameters: params, near: 256)
        }
    }
    
    // MARK: - Gradient Computation Tests
    
    @Test("Compute gradients with typical values")
    func testComputeGradients() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Test with typical neighbor values:
        //   c=100  b=105
        //   a=102  x=?
        let (d1, d2, d3) = regularMode.computeGradients(a: 102, b: 105, c: 100, d: 105)
        
        #expect(d1 == 0)   // D1 = d - b = 105 - 105
        #expect(d2 == 5)   // D2 = b - c = 105 - 100
        #expect(d3 == -2)  // D3 = c - a = 100 - 102
    }
    
    @Test("Compute gradients with flat region")
    func testComputeGradientsFlatRegion() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // All neighbors have same value (flat region)
        let (d1, d2, d3) = regularMode.computeGradients(a: 128, b: 128, c: 128, d: 128)
        
        #expect(d1 == 0)
        #expect(d2 == 0)
        #expect(d3 == 0)
    }
    
    @Test("Compute gradients with edge transition")
    func testComputeGradientsEdge() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Sharp edge:
        //   c=50   b=50
        //   a=200  x=?
        let (d1, d2, d3) = regularMode.computeGradients(a: 200, b: 50, c: 50, d: 50)
        
        #expect(d1 == 0)     // D1 = d - b = 50 - 50
        #expect(d2 == 0)     // D2 = b - c = 50 - 50
        #expect(d3 == -150)  // D3 = c - a = 50 - 200
    }
    
    // MARK: - Gradient Quantization Tests
    
    @Test("Quantize gradient to zero for small values")
    func testQuantizeGradientSmall() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Gradients <= NEAR should quantize to 0
        #expect(regularMode.quantizeGradient(0) == 0)
        
        // With NEAR=0, no gradients quantize to 0 except 0 itself
    }
    
    @Test("Quantize gradient using T1 threshold")
    func testQuantizeGradientT1() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Gradients in range (NEAR, T1] should quantize to ±1
        #expect(regularMode.quantizeGradient(1) == 1)
        #expect(regularMode.quantizeGradient(3) == 1)   // T1 = 3
        #expect(regularMode.quantizeGradient(-1) == -1)
        #expect(regularMode.quantizeGradient(-3) == -1)
    }
    
    @Test("Quantize gradient using T2 threshold")
    func testQuantizeGradientT2() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Gradients in range (T1, T2] should quantize to ±2
        #expect(regularMode.quantizeGradient(4) == 2)
        #expect(regularMode.quantizeGradient(7) == 2)   // T2 = 7
        #expect(regularMode.quantizeGradient(-4) == -2)
        #expect(regularMode.quantizeGradient(-7) == -2)
    }
    
    @Test("Quantize gradient using T3 threshold")
    func testQuantizeGradientT3() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Gradients in range (T2, T3] should quantize to ±3
        #expect(regularMode.quantizeGradient(8) == 3)
        #expect(regularMode.quantizeGradient(21) == 3)   // T3 = 21
        #expect(regularMode.quantizeGradient(-8) == -3)
        #expect(regularMode.quantizeGradient(-21) == -3)
    }
    
    @Test("Quantize gradient beyond T3")
    func testQuantizeGradientLarge() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Gradients > T3 should quantize to ±4
        #expect(regularMode.quantizeGradient(22) == 4)
        #expect(regularMode.quantizeGradient(100) == 4)
        #expect(regularMode.quantizeGradient(-22) == -4)
        #expect(regularMode.quantizeGradient(-100) == -4)
    }
    
    // MARK: - MED Prediction Tests
    
    @Test("MED prediction when c >= max(a, b)")
    func testMEDPredictionCase1() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // When c >= max(a, b), predict min(a, b)
        //   c=150  b=100
        //   a=120  x=?
        let prediction = regularMode.computeMEDPrediction(a: 120, b: 100, c: 150)
        #expect(prediction == 100)  // min(120, 100)
    }
    
    @Test("MED prediction when c <= min(a, b)")
    func testMEDPredictionCase2() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // When c <= min(a, b), predict max(a, b)
        //   c=50   b=100
        //   a=120  x=?
        let prediction = regularMode.computeMEDPrediction(a: 120, b: 100, c: 50)
        #expect(prediction == 120)  // max(120, 100)
    }
    
    @Test("MED prediction in general case")
    func testMEDPredictionCase3() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // Otherwise, predict a + b - c
        // Use c between min(a,b) and max(a,b)
        //   c=115  b=120
        //   a=110  x=?
        // min(a,b)=110, max(a,b)=120, so c=115 is in between
        let prediction = regularMode.computeMEDPrediction(a: 110, b: 120, c: 115)
        #expect(prediction == 115)  // 110 + 120 - 115
    }
    
    @Test("MED prediction with flat region")
    func testMEDPredictionFlat() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // All neighbors same value
        let prediction = regularMode.computeMEDPrediction(a: 128, b: 128, c: 128)
        #expect(prediction == 128)
    }
    
    // MARK: - Bias Correction Tests
    
    @Test("Apply positive bias correction")
    func testBiasCorrectionPositive() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let corrected = regularMode.applyBiasCorrection(
            prediction: 100,
            biasC: 5,
            sign: 1
        )
        #expect(corrected == 105)  // 100 + 1 * 5
    }
    
    @Test("Apply negative bias correction")
    func testBiasCorrectionNegative() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let corrected = regularMode.applyBiasCorrection(
            prediction: 100,
            biasC: 5,
            sign: -1
        )
        #expect(corrected == 95)  // 100 + (-1) * 5
    }
    
    @Test("Bias correction clamped to MAXVAL")
    func testBiasCorrectionClampedMax() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let corrected = regularMode.applyBiasCorrection(
            prediction: 250,
            biasC: 10,
            sign: 1
        )
        #expect(corrected == 255)  // Clamped to MAXVAL
    }
    
    @Test("Bias correction clamped to zero")
    func testBiasCorrectionClampedMin() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let corrected = regularMode.applyBiasCorrection(
            prediction: 5,
            biasC: 10,
            sign: -1
        )
        #expect(corrected == 0)  // Clamped to 0
    }
    
    // MARK: - Prediction Error Tests
    
    @Test("Compute prediction error")
    func testPredictionError() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let error = regularMode.computePredictionError(actual: 120, prediction: 115)
        #expect(error == 5)  // 120 - 115
    }
    
    @Test("Compute negative prediction error")
    func testPredictionErrorNegative() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let error = regularMode.computePredictionError(actual: 100, prediction: 110)
        #expect(error == -10)  // 100 - 110
    }
    
    @Test("Prediction error with modular reduction (positive)")
    func testPredictionErrorModularReductionPositive() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // With MAXVAL=255, RANGE=256
        // If error > 127, it should wrap around
        let error = regularMode.computePredictionError(actual: 250, prediction: 50)
        // Raw error = 200, which is > 127
        // Should wrap: 200 - 256 = -56
        #expect(error == -56)
    }
    
    @Test("Prediction error with modular reduction (negative)")
    func testPredictionErrorModularReductionNegative() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // With MAXVAL=255, RANGE=256
        // If error < -128, it should wrap around
        let error = regularMode.computePredictionError(actual: 50, prediction: 200)
        // Raw error = -150, which is < -128
        // Should wrap: -150 + 256 = 106
        #expect(error == 106)
    }
    
    // MARK: - Error Mapping Tests
    
    @Test("Map positive error to non-negative")
    func testMapErrorPositive() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        #expect(regularMode.mapErrorToNonNegative(0) == 0)    // 2 * 0
        #expect(regularMode.mapErrorToNonNegative(5) == 10)   // 2 * 5
        #expect(regularMode.mapErrorToNonNegative(10) == 20)  // 2 * 10
    }
    
    @Test("Map negative error to non-negative")
    func testMapErrorNegative() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        #expect(regularMode.mapErrorToNonNegative(-1) == 1)   // -2 * (-1) - 1
        #expect(regularMode.mapErrorToNonNegative(-5) == 9)   // -2 * (-5) - 1
        #expect(regularMode.mapErrorToNonNegative(-10) == 19) // -2 * (-10) - 1
    }
    
    // MARK: - Golomb Encoding Tests
    
    @Test("Golomb encode with k=0")
    func testGolombEncodeK0() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        let (unaryLength, remainder) = regularMode.golombEncode(value: 5, k: 0)
        #expect(unaryLength == 5)  // value >> 0 = 5, unary = 5 zeros
        #expect(remainder == 0)    // value & 0 = 0
    }
    
    @Test("Golomb encode with k=2")
    func testGolombEncodeK2() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // value = 13 (binary: 1101)
        // quotient = 13 >> 2 = 3 (binary: 11)
        // remainder = 13 & 3 = 1 (binary: 01)
        let (unaryLength, remainder) = regularMode.golombEncode(value: 13, k: 2)
        #expect(unaryLength == 3)  // quotient = 3, unary = 3 zeros
        #expect(remainder == 1)    // last 2 bits
    }
    
    @Test("Golomb encode with k=4")
    func testGolombEncodeK4() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // value = 25 (binary: 11001)
        // quotient = 25 >> 4 = 1 (binary: 1)
        // remainder = 25 & 15 = 9 (binary: 1001)
        let (unaryLength, remainder) = regularMode.golombEncode(value: 25, k: 4)
        #expect(unaryLength == 1)  // quotient = 1, unary = 1 zero
        #expect(remainder == 9)    // last 4 bits
    }
    
    @Test("Golomb bit length calculation")
    func testGolombBitLength() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        
        // With k=2, value=13:
        // unary length = 4, k bits = 2, total = 6
        let bitLength = regularMode.golombBitLength(value: 13, k: 2)
        #expect(bitLength == 6)
    }
    
    // MARK: - Complete Encoding Pipeline Tests
    
    @Test("Encode pixel in flat region")
    func testEncodePixelFlat() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        var context = try createContextModel()
        
        // Flat region: all pixels same value
        let result = regularMode.encodePixel(
            actual: 128,
            a: 128,
            b: 128,
            c: 128,
            d: 128,
            context: context
        )
        
        // In flat region, prediction should be perfect
        #expect(result.error == 0)
        #expect(result.mappedError == 0)
        
        // Update context for next use
        context.updateContext(
            contextIndex: result.contextIndex,
            predictionError: result.error,
            sign: result.sign
        )
    }
    
    @Test("Encode pixel with small prediction error")
    func testEncodePixelSmallError() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        let context = try createContextModel()
        
        // Encode a pixel with small gradients
        let result = regularMode.encodePixel(
            actual: 125,
            a: 120,
            b: 122,
            c: 118,
            d: 122,
            context: context
        )
        
        // Should have computed a context index
        #expect(result.contextIndex >= 0)
        #expect(result.contextIndex < JPEGLSContextModel.regularContextCount)
        
        // Should have encoded bits
        #expect(result.unaryLength >= 0)
        #expect(result.golombK >= 0)
    }
    
    @Test("Encode pixel at edge")
    func testEncodePixelEdge() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        let context = try createContextModel()
        
        // Vertical edge:
        //   c=100  b=100
        //   a=105  x=102
        // This shows a smooth vertical edge
        let result = regularMode.encodePixel(
            actual: 102,
            a: 105,
            b: 100,
            c: 100,
            d: 100,
            context: context
        )
        
        // Should compute valid context
        #expect(result.contextIndex >= 0)
        #expect(result.contextIndex < JPEGLSContextModel.regularContextCount)
        
        // MED should predict well for this edge case
        // c=100, a=105, b=100: c >= max? No. c <= min? Yes (100<=100). Px = max(105,100) = 105
        // Error = 102 - 105 = -3, which is small
        #expect(abs(result.error) < 10)
    }
    
    @Test("Encoded pixel total bit length")
    func testEncodedPixelBitLength() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        let context = try createContextModel()
        
        let result = regularMode.encodePixel(
            actual: 125,
            a: 120,
            b: 122,
            c: 118,
            d: 122,
            context: context
        )
        
        // Total bit length should equal unary zeros + 1 stop bit + k remainder bits
        #expect(result.totalBitLength == result.unaryLength + 1 + result.golombK)
    }
    
    @Test("Encode multiple pixels and verify context adaptation")
    func testEncodeMultiplePixels() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        var context = try createContextModel()
        
        // Simulate encoding a few pixels in a scan line
        let pixels = [100, 102, 105, 103, 104]
        
        var a = 100  // Initial left neighbor
        var b = 100  // Initial top neighbor
        var c = 100  // Initial diagonal neighbor
        var d = 100  // Initial top-right neighbor
        
        for pixel in pixels {
            let result = regularMode.encodePixel(
                actual: pixel,
                a: a,
                b: b,
                c: c,
                d: d,
                context: context
            )
            
            // Update context with encoding result
            context.updateContext(
                contextIndex: result.contextIndex,
                predictionError: result.error,
                sign: result.sign
            )
            
            // Update neighbors for next pixel (simple linear scan)
            c = b
            b = pixel
            a = pixel
            d = pixel
            
            // Should have valid encoding
            #expect(result.contextIndex >= 0)
            #expect(result.unaryLength >= 0)
        }
    }
    
    // MARK: - Near-Lossless Mode Tests
    
    @Test("Encode in near-lossless mode")
    func testEncodeNearLossless() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 2)
        let context = try JPEGLSContextModel(parameters: params, near: 2)
        
        let result = regularMode.encodePixel(
            actual: 125,
            a: 120,
            b: 122,
            c: 118,
            d: 122,
            context: context
        )
        
        // Should encode successfully in near-lossless mode
        #expect(result.contextIndex >= 0)
        #expect(result.unaryLength >= 0)
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Encode pixel at MAXVAL")
    func testEncodePixelMaxVal() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        let context = try createContextModel()
        
        // All pixels at maximum value
        let result = regularMode.encodePixel(
            actual: 255,
            a: 255,
            b: 255,
            c: 255,
            d: 255,
            context: context
        )
        
        // Perfect prediction in flat region
        #expect(result.error == 0)
        #expect(result.mappedError == 0)
    }
    
    @Test("Encode pixel at zero")
    func testEncodePixelZero() throws {
        let params = try createDefaultParameters()
        let regularMode = try JPEGLSRegularMode(parameters: params, near: 0)
        let context = try createContextModel()
        
        // All pixels at minimum value
        let result = regularMode.encodePixel(
            actual: 0,
            a: 0,
            b: 0,
            c: 0,
            d: 0,
            context: context
        )
        
        // Perfect prediction in flat region
        #expect(result.error == 0)
        #expect(result.mappedError == 0)
    }
}
