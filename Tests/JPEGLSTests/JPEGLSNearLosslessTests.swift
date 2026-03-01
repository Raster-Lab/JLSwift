/// Tests for JPEG-LS near-lossless encoding implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Near-Lossless Mode Tests")
struct JPEGLSNearLosslessTests {
    
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
    func createContextModel(near: Int = 2) throws -> JPEGLSContextModel {
        let params = try createDefaultParameters()
        return try JPEGLSContextModel(parameters: params, near: near)
    }
    
    // MARK: - Initialization Tests
    
    @Test("Initialize with valid near parameter")
    func testInitialization() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        #expect(encoder.quantizationDivisor == 5)  // 2 * 2 + 1 = 5
        #expect(encoder.range > 0)
    }
    
    @Test("Initialize with NEAR=1")
    func testInitializationNear1() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 1)
        
        #expect(encoder.quantizationDivisor == 3)  // 2 * 1 + 1 = 3
    }
    
    @Test("Initialize with maximum NEAR=255")
    func testInitializationNear255() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 255)
        
        #expect(encoder.quantizationDivisor == 511)  // 2 * 255 + 1 = 511
    }
    
    @Test("Invalid NEAR parameter 0 throws error")
    func testInvalidNearParameter0() throws {
        let params = try createDefaultParameters()
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSNearLossless(parameters: params, near: 0)
        }
    }
    
    @Test("Invalid NEAR parameter negative throws error")
    func testInvalidNearParameterNegative() throws {
        let params = try createDefaultParameters()
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSNearLossless(parameters: params, near: -1)
        }
    }
    
    @Test("Invalid NEAR parameter 256 throws error")
    func testInvalidNearParameter256() throws {
        let params = try createDefaultParameters()
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSNearLossless(parameters: params, near: 256)
        }
    }
    
    // MARK: - Quantization Divisor Tests
    
    @Test("Quantization divisor calculation")
    func testQuantizationDivisor() throws {
        let params = try createDefaultParameters()
        
        // Test several NEAR values
        for near in [1, 2, 3, 5, 10, 50, 127, 255] {
            let encoder = try JPEGLSNearLossless(parameters: params, near: near)
            #expect(encoder.quantizationDivisor == 2 * near + 1)
        }
    }
    
    // MARK: - Range Calculation Tests
    
    @Test("Range calculation for NEAR=2, MAXVAL=255")
    func testRangeCalculation() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // RANGE = floor((255 + 2*2) / 5) + 1 = floor(259/5) + 1 = 51 + 1 = 52
        #expect(encoder.range == 52)
    }
    
    @Test("Range calculation for NEAR=1")
    func testRangeCalculationNear1() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 1)
        
        // RANGE = floor((255 + 2) / 3) + 1 = floor(257/3) + 1 = 85 + 1 = 86
        #expect(encoder.range == 86)
    }
    
    // MARK: - Modified Threshold Tests
    
    @Test("Modified thresholds are computed correctly")
    func testModifiedThresholds() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // T1 = 3, qbpp = 5: T'1 = max(3/5, 1) = max(0, 1) = 1
        #expect(encoder.modifiedThreshold1 >= 1)
        
        // T2 = 7, qbpp = 5: T'2 = max(7/5, 1) = max(1, 1) = 1
        #expect(encoder.modifiedThreshold2 >= 1)
        
        // T3 = 21, qbpp = 5: T'3 = max(21/5, 1) = max(4, 1) = 4
        #expect(encoder.modifiedThreshold3 >= 1)
        
        // Thresholds must maintain ordering
        #expect(encoder.modifiedThreshold1 <= encoder.modifiedThreshold2)
        #expect(encoder.modifiedThreshold2 <= encoder.modifiedThreshold3)
    }
    
    @Test("Modified thresholds with large NEAR")
    func testModifiedThresholdsLargeNear() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 50)
        
        // With NEAR=50, qbpp=101, all thresholds should be 1
        #expect(encoder.modifiedThreshold1 == 1)
        #expect(encoder.modifiedThreshold2 == 1)
        #expect(encoder.modifiedThreshold3 == 1)
    }
    
    // MARK: - Prediction Error Quantization Tests
    
    @Test("Quantize positive prediction error")
    func testQuantizePositiveError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // qbpp = 5
        // Errval' = floor((Errval + NEAR) / qbpp)
        
        // Error = 0: (0 + 2) / 5 = 0
        #expect(encoder.quantizePredictionError(0) == 0)
        
        // Error = 3: (3 + 2) / 5 = 1
        #expect(encoder.quantizePredictionError(3) == 1)
        
        // Error = 7: (7 + 2) / 5 = 1
        #expect(encoder.quantizePredictionError(7) == 1)
        
        // Error = 8: (8 + 2) / 5 = 2
        #expect(encoder.quantizePredictionError(8) == 2)
        
        // Error = 12: (12 + 2) / 5 = 2
        #expect(encoder.quantizePredictionError(12) == 2)
    }
    
    @Test("Quantize negative prediction error")
    func testQuantizeNegativeError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // qbpp = 5
        // Errval' = -floor((|Errval| + NEAR) / qbpp) for Errval < 0
        
        // Error = -1: -(1 + 2) / 5 = -0
        #expect(encoder.quantizePredictionError(-1) == 0)
        
        // Error = -2: -(2 + 2) / 5 = -0
        #expect(encoder.quantizePredictionError(-2) == 0)
        
        // Error = -3: -(3 + 2) / 5 = -1
        #expect(encoder.quantizePredictionError(-3) == -1)
        
        // Error = -8: -(8 + 2) / 5 = -2
        #expect(encoder.quantizePredictionError(-8) == -2)
    }
    
    @Test("Quantization with NEAR=1")
    func testQuantizationNear1() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 1)
        
        // qbpp = 3
        // Error = 1: (1 + 1) / 3 = 0
        #expect(encoder.quantizePredictionError(1) == 0)
        
        // Error = 2: (2 + 1) / 3 = 1
        #expect(encoder.quantizePredictionError(2) == 1)
        
        // Error = -2: -(2 + 1) / 3 = -1
        #expect(encoder.quantizePredictionError(-2) == -1)
    }
    
    // MARK: - Dequantization Tests
    
    @Test("Dequantize prediction error")
    func testDequantize() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // qbpp = 5
        #expect(encoder.dequantizePredictionError(0) == 0)
        #expect(encoder.dequantizePredictionError(1) == 5)
        #expect(encoder.dequantizePredictionError(2) == 10)
        #expect(encoder.dequantizePredictionError(-1) == -5)
        #expect(encoder.dequantizePredictionError(-2) == -10)
    }
    
    @Test("Quantization and dequantization symmetry")
    func testQuantizationSymmetry() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // For any quantized value, dequantization gives a multiple of qbpp
        for quantized in -10...10 {
            let dequantized = encoder.dequantizePredictionError(quantized)
            #expect(dequantized == quantized * encoder.quantizationDivisor)
        }
    }
    
    // MARK: - Reconstructed Value Tests
    
    @Test("Compute reconstructed value")
    func testReconstructedValue() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Prediction = 100, quantized error = 2
        // Dequantized = 2 * 5 = 10
        // Reconstructed = 100 + 10 = 110
        let reconstructed = encoder.computeReconstructedValue(prediction: 100, quantizedError: 2)
        #expect(reconstructed == 110)
    }
    
    @Test("Reconstructed value clamped to MAXVAL")
    func testReconstructedValueClampedMax() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Prediction = 251, quantized error = 1
        // Dequantized = 1 * 5 = 5
        // Reconstructed = 251 + 5 = 256; 256 ≤ MAXVAL(255)+NEAR(2)=257 so no ITU-T.87 wrap
        // clamp(256, 0, 255) = 255
        let reconstructed = encoder.computeReconstructedValue(prediction: 251, quantizedError: 1)
        #expect(reconstructed == 255)
    }
    
    @Test("Reconstructed value clamped to zero")
    func testReconstructedValueClampedMin() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Prediction = 3, quantized error = -1
        // Dequantized = -1 * 5 = -5
        // Reconstructed = 3 - 5 = -2; -2 >= -NEAR(-2) so no ITU-T.87 wrap
        // clamp(-2, 0, 255) = 0
        let reconstructed = encoder.computeReconstructedValue(prediction: 3, quantizedError: -1)
        #expect(reconstructed == 0)
    }
    
    // MARK: - Error Bounds Validation Tests
    
    @Test("Error bounds validation passes for small errors")
    func testErrorBoundsValid() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Error within NEAR bounds
        #expect(encoder.validateErrorBounds(original: 100, reconstructed: 100))
        #expect(encoder.validateErrorBounds(original: 100, reconstructed: 101))
        #expect(encoder.validateErrorBounds(original: 100, reconstructed: 102))
        #expect(encoder.validateErrorBounds(original: 100, reconstructed: 99))
        #expect(encoder.validateErrorBounds(original: 100, reconstructed: 98))
    }
    
    @Test("Error bounds validation fails for large errors")
    func testErrorBoundsInvalid() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Error exceeds NEAR bounds
        #expect(!encoder.validateErrorBounds(original: 100, reconstructed: 103))
        #expect(!encoder.validateErrorBounds(original: 100, reconstructed: 97))
        #expect(!encoder.validateErrorBounds(original: 100, reconstructed: 110))
    }
    
    @Test("Compute reconstruction error")
    func testReconstructionError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        #expect(encoder.computeReconstructionError(original: 100, reconstructed: 100) == 0)
        #expect(encoder.computeReconstructionError(original: 100, reconstructed: 102) == 2)
        #expect(encoder.computeReconstructionError(original: 100, reconstructed: 98) == 2)
        #expect(encoder.computeReconstructionError(original: 100, reconstructed: 105) == 5)
    }
    
    // MARK: - Modular Reduction Tests
    
    @Test("Modular reduction within bounds")
    func testModularReductionWithinBounds() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // RANGE = 52
        // Values within [-RANGE/2, (RANGE-1)/2] = [-26, 25] should not change
        #expect(encoder.applyModularReduction(0) == 0)
        #expect(encoder.applyModularReduction(10) == 10)
        #expect(encoder.applyModularReduction(-10) == -10)
        #expect(encoder.applyModularReduction(25) == 25)
        #expect(encoder.applyModularReduction(-26) == -26)
    }
    
    @Test("Modular reduction wraps positive values")
    func testModularReductionPositive() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // RANGE = 52
        // Values > 25 should wrap: error -= RANGE
        #expect(encoder.applyModularReduction(26) == -26)
        #expect(encoder.applyModularReduction(30) == -22)
        #expect(encoder.applyModularReduction(51) == -1)
    }
    
    @Test("Modular reduction wraps negative values")
    func testModularReductionNegative() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // RANGE = 52
        // Values < -26 should wrap: error += RANGE
        #expect(encoder.applyModularReduction(-27) == 25)
        #expect(encoder.applyModularReduction(-30) == 22)
        #expect(encoder.applyModularReduction(-52) == 0)
    }
    
    // MARK: - Error Mapping Tests
    
    @Test("Map positive error to non-negative")
    func testMapPositiveError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        #expect(encoder.mapErrorToNonNegative(0) == 0)
        #expect(encoder.mapErrorToNonNegative(1) == 2)
        #expect(encoder.mapErrorToNonNegative(5) == 10)
        #expect(encoder.mapErrorToNonNegative(10) == 20)
    }
    
    @Test("Map negative error to non-negative")
    func testMapNegativeError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        #expect(encoder.mapErrorToNonNegative(-1) == 1)
        #expect(encoder.mapErrorToNonNegative(-2) == 3)
        #expect(encoder.mapErrorToNonNegative(-5) == 9)
        #expect(encoder.mapErrorToNonNegative(-10) == 19)
    }
    
    @Test("Unmap error back to signed")
    func testUnmapError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Even values map to positive
        #expect(encoder.unmapErrorToSigned(0) == 0)
        #expect(encoder.unmapErrorToSigned(2) == 1)
        #expect(encoder.unmapErrorToSigned(10) == 5)
        
        // Odd values map to negative
        #expect(encoder.unmapErrorToSigned(1) == -1)
        #expect(encoder.unmapErrorToSigned(3) == -2)
        #expect(encoder.unmapErrorToSigned(9) == -5)
    }
    
    @Test("Map and unmap are inverse operations")
    func testMapUnmapInverse() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        for error in -50...50 {
            let mapped = encoder.mapErrorToNonNegative(error)
            let unmapped = encoder.unmapErrorToSigned(mapped)
            #expect(unmapped == error)
        }
    }
    
    // MARK: - Gradient Quantization Tests
    
    @Test("Quantize gradient within NEAR")
    func testQuantizeGradientWithinNear() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Gradients with |d| <= NEAR should quantize to 0
        #expect(encoder.quantizeGradient(0) == 0)
        #expect(encoder.quantizeGradient(1) == 0)
        #expect(encoder.quantizeGradient(2) == 0)
        #expect(encoder.quantizeGradient(-1) == 0)
        #expect(encoder.quantizeGradient(-2) == 0)
    }
    
    @Test("Quantize gradient beyond NEAR")
    func testQuantizeGradientBeyondNear() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Gradients with |d| > NEAR should quantize to non-zero
        #expect(encoder.quantizeGradient(3) != 0)
        #expect(encoder.quantizeGradient(-3) != 0)
        #expect(encoder.quantizeGradient(10) != 0)
        #expect(encoder.quantizeGradient(-10) != 0)
    }
    
    @Test("Quantize gradient range is [-4, 4]")
    func testQuantizeGradientRange() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        
        // Test a wide range of gradients
        for gradient in -200...200 {
            let quantized = encoder.quantizeGradient(gradient)
            #expect(quantized >= -4 && quantized <= 4)
        }
    }
    
    // MARK: - Complete Encoding Pipeline Tests
    
    @Test("Encode pixel in flat region")
    func testEncodePixelFlat() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Flat region: all pixels same value
        let result = encoder.encodePixel(
            actual: 128,
            a: 128,
            b: 128,
            c: 128,
            context: context
        )
        
        // In flat region, prediction should be good
        #expect(result.quantizedError == 0)
        #expect(result.mappedError == 0)
        #expect(result.reconstructed == 128)
        #expect(result.errorWithinBounds)
    }
    
    @Test("Encode pixel with small error")
    func testEncodePixelSmallError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Small error within NEAR bounds
        let result = encoder.encodePixel(
            actual: 130,
            a: 128,
            b: 128,
            c: 128,
            context: context
        )
        
        // Error of 2 should be within NEAR bounds
        #expect(result.errorWithinBounds)
        #expect(abs(result.reconstructed - 130) <= 2)
    }
    
    @Test("Encode pixel with larger error")
    func testEncodePixelLargerError() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Larger error that gets quantized
        let result = encoder.encodePixel(
            actual: 140,
            a: 128,
            b: 128,
            c: 128,
            context: context
        )
        
        // Reconstructed value should be within NEAR of original
        #expect(result.errorWithinBounds)
        #expect(abs(result.reconstructed - 140) <= 2)
    }
    
    @Test("Encode pixel at edge")
    func testEncodePixelEdge() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Vertical edge
        let result = encoder.encodePixel(
            actual: 102,
            a: 105,
            b: 100,
            c: 100,
            context: context
        )
        
        #expect(result.contextIndex >= 0)
        #expect(result.contextIndex < JPEGLSContextModel.regularContextCount)
        #expect(result.errorWithinBounds)
    }
    
    @Test("Encode multiple pixels and verify reconstruction")
    func testEncodeMultiplePixels() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        var context = try createContextModel(near: 2)
        
        // Simulate encoding a few pixels
        let originals = [100, 102, 105, 103, 104, 107, 100, 98]
        var reconstructed = 100  // Initial neighbor value
        
        for original in originals {
            let result = encoder.encodePixel(
                actual: original,
                a: reconstructed,
                b: reconstructed,
                c: reconstructed,
                context: context
            )
            
            // Update context
            context.updateContext(
                contextIndex: result.contextIndex,
                predictionError: result.quantizedError,
                sign: result.sign
            )
            
            // Verify error bounds
            #expect(result.errorWithinBounds)
            #expect(abs(result.reconstructed - original) <= 2)
            
            // Use reconstructed value for next pixel (decoder tracking)
            reconstructed = result.reconstructed
        }
    }
    
    @Test("Encoded pixel total bit length")
    func testEncodedPixelBitLength() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        let result = encoder.encodePixel(
            actual: 130,
            a: 128,
            b: 128,
            c: 128,
            context: context
        )
        
        // Total bit length should be positive and reasonable
        #expect(result.totalBitLength > 0)
        #expect(result.totalBitLength < 100)  // Reasonable upper bound
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Encode pixel at MAXVAL")
    func testEncodePixelMaxVal() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        let result = encoder.encodePixel(
            actual: 255,
            a: 255,
            b: 255,
            c: 255,
            context: context
        )
        
        #expect(result.reconstructed == 255)
        #expect(result.errorWithinBounds)
    }
    
    @Test("Encode pixel at zero")
    func testEncodePixelZero() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        let result = encoder.encodePixel(
            actual: 0,
            a: 0,
            b: 0,
            c: 0,
            context: context
        )
        
        #expect(result.reconstructed == 0)
        #expect(result.errorWithinBounds)
    }
    
    @Test("Encode pixel near MAXVAL boundary")
    func testEncodePixelNearMaxVal() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Test that clamping works correctly near MAXVAL
        let result = encoder.encodePixel(
            actual: 254,
            a: 253,
            b: 253,
            c: 253,
            context: context
        )
        
        #expect(result.reconstructed <= 255)
        #expect(result.reconstructed >= 0)
        #expect(result.errorWithinBounds)
    }
    
    @Test("Encode pixel near zero boundary")
    func testEncodePixelNearZero() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        let context = try createContextModel(near: 2)
        
        // Test that clamping works correctly near zero
        let result = encoder.encodePixel(
            actual: 2,
            a: 3,
            b: 3,
            c: 3,
            context: context
        )
        
        #expect(result.reconstructed >= 0)
        #expect(result.reconstructed <= 255)
        #expect(result.errorWithinBounds)
    }
    
    // MARK: - NearLosslessConfiguration Tests
    
    @Test("Configuration initialization")
    func testConfigurationInit() throws {
        let config = try NearLosslessConfiguration(near: 2, bitsPerSample: 8)
        
        #expect(config.near == 2)
        #expect(config.bitsPerSample == 8)
        #expect(config.maxValue == 255)
    }
    
    @Test("Configuration with invalid NEAR")
    func testConfigurationInvalidNear() {
        #expect(throws: JPEGLSError.self) {
            _ = try NearLosslessConfiguration(near: 0, bitsPerSample: 8)
        }
        
        #expect(throws: JPEGLSError.self) {
            _ = try NearLosslessConfiguration(near: 256, bitsPerSample: 8)
        }
    }
    
    @Test("Configuration with invalid bits per sample")
    func testConfigurationInvalidBits() {
        #expect(throws: JPEGLSError.self) {
            _ = try NearLosslessConfiguration(near: 2, bitsPerSample: 1)
        }
        
        #expect(throws: JPEGLSError.self) {
            _ = try NearLosslessConfiguration(near: 2, bitsPerSample: 17)
        }
    }
    
    @Test("Configuration creates encoder")
    func testConfigurationCreateEncoder() throws {
        let config = try NearLosslessConfiguration(near: 2, bitsPerSample: 8)
        let encoder = try config.createEncoder()
        
        #expect(encoder.quantizationDivisor == 5)
    }
    
    @Test("Configuration creates preset parameters")
    func testConfigurationCreateParams() throws {
        let config = try NearLosslessConfiguration(near: 2, bitsPerSample: 8)
        let params = try config.createPresetParameters()
        
        #expect(params.maxValue == 255)
    }
    
    @Test("Configuration compression improvement estimate")
    func testConfigurationCompressionImprovement() throws {
        let config = try NearLosslessConfiguration(near: 2, bitsPerSample: 8)
        
        // Improvement should be positive
        #expect(config.estimatedCompressionImprovement > 1.0)
    }
    
    // MARK: - JPEGLSPresetParameters Extension Tests
    
    @Test("Preset parameters modified thresholds")
    func testPresetModifiedThresholds() throws {
        let params = try createDefaultParameters()
        let (t1, t2, t3) = params.computeModifiedThresholds(near: 2)
        
        #expect(t1 >= 1)
        #expect(t2 >= 1)
        #expect(t3 >= 1)
        #expect(t1 <= t2)
        #expect(t2 <= t3)
    }
    
    @Test("Modified thresholds with NEAR=0 (lossless)")
    func testPresetModifiedThresholdsLossless() throws {
        let params = try createDefaultParameters()
        let (t1, t2, t3) = params.computeModifiedThresholds(near: 0)
        
        // With NEAR=0, divisor = 1, thresholds unchanged (capped at original)
        #expect(t1 == params.threshold1)
        #expect(t2 == params.threshold2)
        #expect(t3 == params.threshold3)
    }
    
    // MARK: - 12-bit and 16-bit Tests
    
    @Test("Near-lossless with 12-bit samples")
    func testNearLossless12Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 12)
        let encoder = try JPEGLSNearLossless(parameters: params, near: 10)
        let context = try JPEGLSContextModel(parameters: params, near: 10)
        
        // Test with 12-bit values (0-4095)
        let result = encoder.encodePixel(
            actual: 2048,
            a: 2040,
            b: 2040,
            c: 2040,
            context: context
        )
        
        #expect(result.errorWithinBounds)
        #expect(abs(result.reconstructed - 2048) <= 10)
    }
    
    @Test("Near-lossless with 16-bit samples")
    func testNearLossless16Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 16)
        let encoder = try JPEGLSNearLossless(parameters: params, near: 50)
        let context = try JPEGLSContextModel(parameters: params, near: 50)
        
        // Test with 16-bit values (0-65535)
        let result = encoder.encodePixel(
            actual: 32768,
            a: 32700,
            b: 32700,
            c: 32700,
            context: context
        )
        
        #expect(result.errorWithinBounds)
        #expect(abs(result.reconstructed - 32768) <= 50)
    }
    
    // MARK: - Stress Tests
    
    @Test("Encode random sequence maintains error bounds")
    func testEncodeRandomSequence() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSNearLossless(parameters: params, near: 2)
        var context = try createContextModel(near: 2)
        
        // Test with pseudo-random sequence
        var value = 100
        var reconstructed = 100
        
        for i in 0..<100 {
            // Generate pseudo-random change
            value = (value + (i * 17 + 13) % 20 - 10)
            value = max(0, min(255, value))
            
            let result = encoder.encodePixel(
                actual: value,
                a: reconstructed,
                b: reconstructed,
                c: reconstructed,
                context: context
            )
            
            context.updateContext(
                contextIndex: result.contextIndex,
                predictionError: result.quantizedError,
                sign: result.sign
            )
            
            #expect(result.errorWithinBounds, "Error bounds violated at iteration \(i)")
            reconstructed = result.reconstructed
        }
    }
    
    @Test("Different NEAR values all maintain bounds")
    func testDifferentNearValues() throws {
        let params = try createDefaultParameters()
        let testPixels = [(actual: 130, neighbors: 120), (actual: 100, neighbors: 115), (actual: 200, neighbors: 180)]
        
        for near in [1, 2, 5, 10, 20, 50] {
            let encoder = try JPEGLSNearLossless(parameters: params, near: near)
            let context = try JPEGLSContextModel(parameters: params, near: near)
            
            for (actual, neighbors) in testPixels {
                let result = encoder.encodePixel(
                    actual: actual,
                    a: neighbors,
                    b: neighbors,
                    c: neighbors,
                    context: context
                )
                
                #expect(result.errorWithinBounds, "NEAR=\(near) failed for actual=\(actual)")
                #expect(abs(result.reconstructed - actual) <= near,
                       "Reconstruction error exceeded NEAR=\(near)")
            }
        }
    }
}
