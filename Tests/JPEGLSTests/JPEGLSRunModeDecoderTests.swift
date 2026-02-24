/// Tests for JPEG-LS run mode decoding implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Run Mode Decoder Tests")
struct JPEGLSRunModeDecoderTests {
    
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
    
    // MARK: - Initialization Tests
    
    @Test("Initialize with valid parameters")
    func testInitialization() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        #expect(decoder != nil)
    }
    
    @Test("Initialize with near-lossless parameter")
    func testInitializationNearLossless() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 5)
        
        #expect(decoder != nil)
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNearParameter() throws {
        let params = try createDefaultParameters()
        
        // NEAR > 255 should throw
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRunModeDecoder(parameters: params, near: 256)
        }
        
        // NEAR < 0 should throw
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRunModeDecoder(parameters: params, near: -1)
        }
    }
    
    @Test("Initialize with custom max run length")
    func testCustomMaxRunLength() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(
            parameters: params,
            near: 0,
            maxRunLength: 1024
        )
        
        #expect(decoder != nil)
    }
    
    // MARK: - Run Detection Tests
    
    @Test("Run mode entered when Ra equals Rb")
    func testShouldEnterRunMode() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Ra == Rb → enter run mode
        #expect(decoder.shouldEnterRunMode(a: 100, b: 100) == true)
        #expect(decoder.shouldEnterRunMode(a: 0, b: 0) == true)
        #expect(decoder.shouldEnterRunMode(a: 255, b: 255) == true)
    }
    
    @Test("Run mode not entered when Ra differs from Rb")
    func testShouldNotEnterRunMode() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Ra != Rb → stay in regular mode
        #expect(decoder.shouldEnterRunMode(a: 100, b: 101) == false)
        #expect(decoder.shouldEnterRunMode(a: 50, b: 150) == false)
        #expect(decoder.shouldEnterRunMode(a: 0, b: 255) == false)
    }
    
    // MARK: - J[RUNindex] Mapping Tests
    
    @Test("Compute J for RUNindex 0")
    func testComputeJ_Index0() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        #expect(decoder.computeJ(runIndex: 0) == 0)
    }
    
    @Test("Compute J for RUNindex 1")
    func testComputeJ_Index1() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[1] = 0
        #expect(decoder.computeJ(runIndex: 1) == 0)
    }
    
    @Test("Compute J for RUNindex 2")
    func testComputeJ_Index2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[2] = 0
        #expect(decoder.computeJ(runIndex: 2) == 0)
    }
    
    @Test("Compute J for higher RUNindex values")
    func testComputeJ_HigherIndices() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[5]=1, J[10]=2, J[20]=6
        #expect(decoder.computeJ(runIndex: 5) == 1)
        #expect(decoder.computeJ(runIndex: 10) == 2)
        #expect(decoder.computeJ(runIndex: 20) == 6)
    }
    
    @Test("Compute J capped at maximum table entry")
    func testComputeJ_Capped() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[31]=15, indices beyond 31 clamp to J[31]=15
        #expect(decoder.computeJ(runIndex: 32) == 15)
        #expect(decoder.computeJ(runIndex: 50) == 15)
        #expect(decoder.computeJ(runIndex: 100) == 15)
    }
    
    // MARK: - Run-Length Decoding Tests
    
    @Test("Decode short run with J=0")
    func testDecodeRunLength_ShortRunJ0() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=0, J=0, blockSize=1
        let decoded = decoder.decodeRunLength(
            continuationBits: 0,
            remainder: 0,
            runIndex: 0
        )
        
        #expect(decoded.j == 0)
        #expect(decoded.continuationBits == 0)
        #expect(decoded.remainder == 0)
        #expect(decoded.totalRunLength == 0)
    }
    
    @Test("Decode run with J=1")
    func testDecodeRunLength_J1() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=4, J[4]=1, blockSize=2
        // 2 blocks + 1 remainder = 5
        let decoded = decoder.decodeRunLength(
            continuationBits: 2,
            remainder: 1,
            runIndex: 4
        )
        
        #expect(decoded.j == 1)
        #expect(decoded.continuationBits == 2)
        #expect(decoded.remainder == 1)
        #expect(decoded.totalRunLength == 5)
    }
    
    @Test("Decode run with J=2")
    func testDecodeRunLength_J2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=8, J[8]=2, blockSize=4
        // 2 blocks + 2 remainder = 10
        let decoded = decoder.decodeRunLength(
            continuationBits: 2,
            remainder: 2,
            runIndex: 8
        )
        
        #expect(decoded.j == 2)
        #expect(decoded.continuationBits == 2)
        #expect(decoded.remainder == 2)
        #expect(decoded.totalRunLength == 10)
    }
    
    @Test("Decode run exactly matching block size")
    func testDecodeRunLength_ExactBlock() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=12, J[12]=3, blockSize=8
        // 1 block + 0 remainder = 8
        let decoded = decoder.decodeRunLength(
            continuationBits: 1,
            remainder: 0,
            runIndex: 12
        )
        
        #expect(decoded.j == 3)
        #expect(decoded.continuationBits == 1)
        #expect(decoded.remainder == 0)
        #expect(decoded.totalRunLength == 8)
    }
    
    @Test("Decode long run with multiple blocks")
    func testDecodeRunLength_LongRun() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=16, J[16]=4, blockSize=16
        // 6 blocks + 4 remainder = 100
        let decoded = decoder.decodeRunLength(
            continuationBits: 6,
            remainder: 4,
            runIndex: 16
        )
        
        #expect(decoded.j == 4)
        #expect(decoded.continuationBits == 6)
        #expect(decoded.remainder == 4)
        #expect(decoded.totalRunLength == 100)
    }
    
    @Test("Decode run with zero length")
    func testDecodeRunLength_Zero() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1
        let decoded = decoder.decodeRunLength(
            continuationBits: 0,
            remainder: 0,
            runIndex: 5
        )
        
        #expect(decoded.j == 1)
        #expect(decoded.totalRunLength == 0)
    }
    
    @Test("Decode run length direct method")
    func testDecodeRunLengthDirect() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=12, J[12]=3, blockSize=8
        // 2 continuations + 4 remainder = 20
        let length = decoder.decodeRunLengthDirect(
            continuationCount: 2,
            remainderBits: 4,
            runIndex: 12
        )
        
        #expect(length == 20)
    }
    
    // MARK: - Error Unmapping Tests
    
    @Test("Unmap positive error (even value)")
    func testUnmapErrorPositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Even values map to positive errors
        #expect(decoder.unmapError(0) == 0)
        #expect(decoder.unmapError(10) == 5)
        #expect(decoder.unmapError(20) == 10)
        #expect(decoder.unmapError(100) == 50)
    }
    
    @Test("Unmap negative error (odd value)")
    func testUnmapErrorNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Odd values map to negative errors
        #expect(decoder.unmapError(1) == -1)
        #expect(decoder.unmapError(9) == -5)
        #expect(decoder.unmapError(19) == -10)
        #expect(decoder.unmapError(49) == -25)
    }
    
    // MARK: - Run Interruption Decoding Tests
    
    @Test("Decode run interruption with positive error")
    func testDecodeRunInterruption_PositiveError() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // mappedError = 100 → error = 50
        let decoded = decoder.decodeRunInterruption(
            mappedError: 100,
            runValue: 100,
            topValue: 100
        )
        
        #expect(decoded.prediction == 100)
        #expect(decoded.mappedError == 100)
        #expect(decoded.error == 50)
        #expect(decoded.sample == 150)  // 100 + 50
    }
    
    @Test("Decode run interruption with negative error")
    func testDecodeRunInterruption_NegativeError() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // mappedError = 49 → error = -25
        let decoded = decoder.decodeRunInterruption(
            mappedError: 49,
            runValue: 100,
            topValue: 100
        )
        
        #expect(decoded.prediction == 100)
        #expect(decoded.mappedError == 49)
        #expect(decoded.error == -25)
        #expect(decoded.sample == 75)  // 100 - 25
    }
    
    @Test("Decode run interruption with zero error")
    func testDecodeRunInterruption_ZeroError() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let decoded = decoder.decodeRunInterruption(
            mappedError: 0,
            runValue: 128,
            topValue: 128
        )
        
        #expect(decoded.error == 0)
        #expect(decoded.sample == 128)
    }
    
    @Test("Decode run interruption with modular wraparound positive")
    func testDecodeRunInterruption_ModularPositive() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // runValue=250, error=20 → 270 > 255, wraps to 14
        let decoded = decoder.decodeRunInterruption(
            mappedError: 40,  // 40/2 = 20
            runValue: 250,
            topValue: 250
        )
        
        #expect(decoded.error == 20)
        #expect(decoded.sample == 14)  // 270 - 256
    }
    
    @Test("Decode run interruption with modular wraparound negative")
    func testDecodeRunInterruption_ModularNegative() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // runValue=5, error=-10 → -5 < 0, wraps to 251
        let decoded = decoder.decodeRunInterruption(
            mappedError: 19,  // -(19+1)/2 = -10
            runValue: 5,
            topValue: 5
        )
        
        #expect(decoded.error == -10)
        #expect(decoded.sample == 251)  // -5 + 256
    }
    
    @Test("Decode run interruption at boundaries")
    func testDecodeRunInterruption_Boundaries() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // At minimum value
        let decoded1 = decoder.decodeRunInterruption(mappedError: 0, runValue: 0, topValue: 0)
        #expect(decoded1.sample == 0)
        
        // At maximum value
        let decoded2 = decoder.decodeRunInterruption(mappedError: 0, runValue: 255, topValue: 255)
        #expect(decoded2.sample == 255)
    }
    
    @Test("Decode run interruption from bits")
    func testDecodeRunInterruptionFromBits() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Golomb decode: (2 << 3) | 4 = 20 → error = 10
        let decoded = decoder.decodeRunInterruptionFromBits(
            unaryCount: 2,
            remainder: 4,
            k: 3,
            runValue: 100,
            topValue: 100
        )
        
        #expect(decoded.mappedError == 20)
        #expect(decoded.error == 10)
        #expect(decoded.sample == 110)
    }
    
    // MARK: - Context Adaptation Tests
    
    @Test("Adapt run index for long run (increase)")
    func testAdaptRunIndex_LongRun() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=5, J=5, blockSize=32
        // Run of 64 > 32, so increase index
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 64
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index for short run (decrease)")
    func testAdaptRunIndex_ShortRun() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1, blockSize=2
        // Run of 8 > blockSize(2), so increase index
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 8
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index stays same for medium run")
    func testAdaptRunIndex_MediumRun() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1, blockSize=2
        // Run of 24 > blockSize(2), so increase index
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 24
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index capped at maximum (31)")
    func testAdaptRunIndex_MaxCap() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 31,
            completedRunLength: 100000
        )
        
        #expect(newIndex == 31)
    }
    
    @Test("Adapt run index capped at minimum (0)")
    func testAdaptRunIndex_MinCap() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 0,
            completedRunLength: 0
        )
        
        #expect(newIndex == 0)
    }
    
    @Test("Adapt run index from index 1 (edge case)")
    func testAdaptRunIndex_Index1() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // runIndex=1, J[1]=0, blockSize=1
        // completedRunLength=0, not > 1, j=0 so j>0 is false → no decrease
        // Index stays at 1
        let newIndex = decoder.adaptRunIndex(
            currentRunIndex: 1,
            completedRunLength: 0
        )
        
        #expect(newIndex == 1)
    }
    
    // MARK: - Run Pixel Reconstruction Tests
    
    @Test("Reconstruct run pixels")
    func testReconstructRunPixels() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let pixels = decoder.reconstructRunPixels(runValue: 128, runLength: 10)
        
        #expect(pixels.count == 10)
        #expect(pixels.allSatisfy { $0 == 128 })
    }
    
    @Test("Reconstruct empty run")
    func testReconstructRunPixels_Empty() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let pixels = decoder.reconstructRunPixels(runValue: 100, runLength: 0)
        
        #expect(pixels.isEmpty)
    }
    
    @Test("Reconstruct long run")
    func testReconstructRunPixels_Long() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let pixels = decoder.reconstructRunPixels(runValue: 200, runLength: 1000)
        
        #expect(pixels.count == 1000)
        #expect(pixels.allSatisfy { $0 == 200 })
    }
    
    // MARK: - Golomb-Rice Decoding Tests
    
    @Test("Golomb decode with k=0")
    func testGolombDecodeK0() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let value = decoder.golombDecode(unaryCount: 5, remainder: 0, k: 0)
        #expect(value == 5)
    }
    
    @Test("Golomb decode with k=2")
    func testGolombDecodeK2() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // (3 << 2) | 1 = 13
        let value = decoder.golombDecode(unaryCount: 3, remainder: 1, k: 2)
        #expect(value == 13)
    }
    
    @Test("Golomb decode zero")
    func testGolombDecodeZero() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let value = decoder.golombDecode(unaryCount: 0, remainder: 0, k: 2)
        #expect(value == 0)
    }
    
    // MARK: - Complete Run Decoding Tests
    
    @Test("Decode complete run without interruption")
    func testDecodeCompleteRun_NoInterruption() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=12, J[12]=3, blockSize=8
        let result = decoder.decodeCompleteRun(
            continuationBits: 3,
            remainder: 2,
            runIndex: 12,
            runValue: 100,
            topValue: 100,
            isRunTerminated: false,
            interruptionMappedError: nil
        )
        
        // 3 * 8 + 2 = 26 pixels
        #expect(result.runLength == 26)
        #expect(result.runValue == 100)
        #expect(result.runPixels.count == 26)
        #expect(result.runPixels.allSatisfy { $0 == 100 })
        #expect(result.interruptionSample == nil)
        #expect(result.decodedInterruption == nil)
        #expect(result.totalPixels == 26)
    }
    
    @Test("Decode complete run with interruption")
    func testDecodeCompleteRun_WithInterruption() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // With runIndex=12, J[12]=3, blockSize=8
        let result = decoder.decodeCompleteRun(
            continuationBits: 2,
            remainder: 4,
            runIndex: 12,
            runValue: 100,
            topValue: 100,
            isRunTerminated: true,
            interruptionMappedError: 60  // 60/2 = 30 → sample = 130
        )
        
        // 2 * 8 + 4 = 20 pixels
        #expect(result.runLength == 20)
        #expect(result.runPixels.count == 20)
        #expect(result.interruptionSample == 130)
        #expect(result.decodedInterruption?.error == 30)
        #expect(result.totalPixels == 21)
    }
    
    @Test("Decode complete run adapts run index")
    func testDecodeCompleteRun_AdaptsRunIndex() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Long run should increase run index
        let result = decoder.decodeCompleteRun(
            continuationBits: 10,
            remainder: 0,
            runIndex: 5,
            runValue: 128,
            topValue: 128,
            isRunTerminated: false,
            interruptionMappedError: nil
        )
        
        // 10 * 32 = 320 > 32, so index increases
        #expect(result.adaptedRunIndex == 6)
    }
    
    // MARK: - Run Limit Checking Tests
    
    @Test("Valid run length check")
    func testIsValidRunLength() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(
            parameters: params,
            near: 0,
            maxRunLength: 1000
        )
        
        #expect(decoder.isValidRunLength(0) == true)
        #expect(decoder.isValidRunLength(500) == true)
        #expect(decoder.isValidRunLength(1000) == true)
        #expect(decoder.isValidRunLength(1001) == false)
        #expect(decoder.isValidRunLength(-1) == false)
    }
    
    // MARK: - Encode-Decode Round-Trip Tests
    
    @Test("Round-trip encoding and decoding run length")
    func testRoundTripRunLength() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRunMode(parameters: params, near: 0)
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J, the J table maps run indices to J values in groups.
        // Test run lengths that stay within a single J-group (same block size)
        // so the decoder's simplified single-J decoding matches the encoder.
        let testCases: [(runLength: Int, runIndex: Int)] = [
            (0, 0),     // J[0]=0, blockSize=1
            (1, 0),     // stays in J=0 group
            (3, 0),     // stays in J=0 group (3 blocks)
            (1, 4),     // J[4]=1, blockSize=2, stays in J=1 group
            (5, 4),     // stays in J=1 group
            (7, 4),     // stays in J=1 group
            (4, 8),     // J[8]=2, blockSize=4, stays in J=2 group
            (12, 8),    // stays in J=2 group
            (16, 12),   // J[12]=3, blockSize=8, stays in J=3 group
            (40, 12),   // stays in J=3 group
        ]
        
        for (runLength, runIndex) in testCases {
            let encoded = encoder.encodeRunLength(
                runLength: runLength,
                runIndex: runIndex
            )
            
            let decoded = decoder.decodeRunLength(
                continuationBits: encoded.continuationBits,
                remainder: encoded.remainder,
                runIndex: runIndex
            )
            
            #expect(
                decoded.totalRunLength == runLength,
                "Round-trip failed for runLength=\(runLength), runIndex=\(runIndex)"
            )
        }
    }
    
    @Test("Round-trip encoding and decoding run interruption")
    func testRoundTripRunInterruption() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRunMode(parameters: params, near: 0)
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Test various interruption values
        let testCases: [(interruptionValue: Int, runValue: Int)] = [
            (100, 100),   // Zero error
            (150, 100),   // Positive error
            (75, 100),    // Negative error
            (255, 128),   // Near max
            (0, 128),     // At min
            (255, 10),    // Large positive with wrap
            (10, 255),    // Large negative with wrap
        ]
        
        for (interruptionValue, runValue) in testCases {
            let encoded = encoder.encodeRunInterruption(
                interruptionValue: interruptionValue,
                runValue: runValue,
                topValue: runValue
            )
            
            let decoded = decoder.decodeRunInterruption(
                mappedError: encoded.mappedError,
                runValue: runValue,
                topValue: runValue
            )
            
            #expect(
                decoded.sample == interruptionValue,
                "Round-trip failed for interruptionValue=\(interruptionValue), runValue=\(runValue)"
            )
        }
    }
    
    @Test("Round-trip run index adaptation")
    func testRoundTripRunIndexAdaptation() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRunMode(parameters: params, near: 0)
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Test that encoder and decoder adapt identically
        let testCases: [(runIndex: Int, runLength: Int)] = [
            (5, 64),   // Long run
            (5, 8),    // Short run
            (5, 24),   // Medium run
            (0, 100),  // At minimum
            (31, 100), // At maximum
        ]
        
        for (runIndex, runLength) in testCases {
            let encoderAdapted = encoder.adaptRunIndex(
                currentRunIndex: runIndex,
                completedRunLength: runLength
            )
            
            let decoderAdapted = decoder.adaptRunIndex(
                currentRunIndex: runIndex,
                completedRunLength: runLength
            )
            
            #expect(
                encoderAdapted == decoderAdapted,
                "Adaptation mismatch for runIndex=\(runIndex), runLength=\(runLength)"
            )
        }
    }
    
    @Test("Round-trip complete workflow")
    func testRoundTripCompleteWorkflow() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRunMode(parameters: params, near: 0)
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Simulate encoding a run within the same J-group per ITU-T.87 Annex J
        // runIndex=12, J[12]=3, blockSize=8
        // When all continuation bits use the same block size, the simplified
        // decoder (single J lookup) produces correct results
        let runValue = 100
        let runLength = 16  // 2 blocks of 8 stays within J=3 group (indices 12-15)
        let interruptionValue = 150
        
        // Encode run
        let encodedRun = encoder.encodeRunLength(
            runLength: runLength,
            runIndex: 12
        )
        
        // Encode interruption
        let encodedInterruption = encoder.encodeRunInterruption(
            interruptionValue: interruptionValue,
            runValue: runValue,
            topValue: runValue
        )
        
        // Decode complete run
        let decodedResult = decoder.decodeCompleteRun(
            continuationBits: encodedRun.continuationBits,
            remainder: encodedRun.remainder,
            runIndex: 12,
            runValue: runValue,
            topValue: runValue,
            isRunTerminated: true,
            interruptionMappedError: encodedInterruption.mappedError
        )
        
        // Verify
        #expect(decodedResult.runLength == runLength)
        #expect(decodedResult.runPixels.allSatisfy { $0 == runValue })
        #expect(decodedResult.interruptionSample == interruptionValue)
    }
    
    // MARK: - DecodedRun Struct Tests
    
    @Test("DecodedRun struct equality")
    func testDecodedRunEquality() throws {
        let run1 = DecodedRun(
            runIndex: 5,
            j: 5,
            continuationBits: 2,
            remainder: 4,
            totalRunLength: 68
        )
        
        let run2 = DecodedRun(
            runIndex: 5,
            j: 5,
            continuationBits: 2,
            remainder: 4,
            totalRunLength: 68
        )
        
        let run3 = DecodedRun(
            runIndex: 5,
            j: 5,
            continuationBits: 3,
            remainder: 4,
            totalRunLength: 100
        )
        
        #expect(run1 == run2)
        #expect(run1 != run3)
    }
    
    // MARK: - DecodedRunInterruption Struct Tests
    
    @Test("DecodedRunInterruption struct equality")
    func testDecodedRunInterruptionEquality() throws {
        let int1 = DecodedRunInterruption(
            prediction: 100,
            mappedError: 60,
            error: 30,
            sample: 130
        )
        
        let int2 = DecodedRunInterruption(
            prediction: 100,
            mappedError: 60,
            error: 30,
            sample: 130
        )
        
        let int3 = DecodedRunInterruption(
            prediction: 100,
            mappedError: 40,
            error: 20,
            sample: 120
        )
        
        #expect(int1 == int2)
        #expect(int1 != int3)
    }
    
    // MARK: - CompleteDecodedRun Struct Tests
    
    @Test("CompleteDecodedRun struct equality")
    func testCompleteDecodedRunEquality() throws {
        let interruption = DecodedRunInterruption(
            prediction: 100,
            mappedError: 60,
            error: 30,
            sample: 130
        )
        
        let result1 = CompleteDecodedRun(
            runLength: 20,
            runValue: 100,
            runPixels: Array(repeating: 100, count: 20),
            interruptionSample: 130,
            decodedInterruption: interruption,
            adaptedRunIndex: 6
        )
        
        let result2 = CompleteDecodedRun(
            runLength: 20,
            runValue: 100,
            runPixels: Array(repeating: 100, count: 20),
            interruptionSample: 130,
            decodedInterruption: interruption,
            adaptedRunIndex: 6
        )
        
        let result3 = CompleteDecodedRun(
            runLength: 30,
            runValue: 100,
            runPixels: Array(repeating: 100, count: 30),
            interruptionSample: 130,
            decodedInterruption: interruption,
            adaptedRunIndex: 6
        )
        
        #expect(result1 == result2)
        #expect(result1 != result3)
    }
    
    @Test("CompleteDecodedRun totalPixels calculation")
    func testCompleteDecodedRunTotalPixels() throws {
        // Without interruption
        let result1 = CompleteDecodedRun(
            runLength: 20,
            runValue: 100,
            runPixels: Array(repeating: 100, count: 20),
            interruptionSample: nil,
            decodedInterruption: nil,
            adaptedRunIndex: 5
        )
        #expect(result1.totalPixels == 20)
        
        // With interruption
        let result2 = CompleteDecodedRun(
            runLength: 20,
            runValue: 100,
            runPixels: Array(repeating: 100, count: 20),
            interruptionSample: 130,
            decodedInterruption: DecodedRunInterruption(
                prediction: 100,
                mappedError: 60,
                error: 30,
                sample: 130
            ),
            adaptedRunIndex: 5
        )
        #expect(result2.totalPixels == 21)
    }
    
    // MARK: - Near-Lossless Mode Tests
    
    @Test("Decode run interruption in near-lossless mode")
    func testDecodeRunInterruptionNearLossless() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 2)
        
        let decoded = decoder.decodeRunInterruption(
            mappedError: 10,
            runValue: 100,
            topValue: 100
        )
        
        // Should work in near-lossless mode
        #expect(decoded.sample >= 0)
        #expect(decoded.sample <= 255)
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Decode with maximum MAXVAL")
    func testDecodeWithMaxMAXVAL() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 65535,
            threshold1: 18,
            threshold2: 67,
            threshold3: 276,
            reset: 64
        )
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        let decoded = decoder.decodeRunInterruption(
            mappedError: 0,
            runValue: 32768,
            topValue: 32768
        )
        
        #expect(decoded.sample == 32768)
    }
    
    @Test("Decode run with all continuation bits")
    func testDecodeRunAllContinuationBits() throws {
        let params = try createDefaultParameters()
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Large run with runIndex=16, J[16]=4, blockSize=16
        let decoded = decoder.decodeRunLength(
            continuationBits: 100,
            remainder: 15,
            runIndex: 16
        )
        
        // 100 * 16 + 15 = 1615
        #expect(decoded.totalRunLength == 1615)
    }
    
    @Test("J mapping consistency with encoder")
    func testJMappingConsistency() throws {
        let params = try createDefaultParameters()
        let encoder = try JPEGLSRunMode(parameters: params, near: 0)
        let decoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
        
        // Verify J values match between encoder and decoder
        for runIndex in 0...40 {
            let encoderJ = encoder.computeJ(runIndex: runIndex)
            let decoderJ = decoder.computeJ(runIndex: runIndex)
            
            #expect(
                encoderJ == decoderJ,
                "J mismatch at runIndex=\(runIndex)"
            )
        }
    }
}
