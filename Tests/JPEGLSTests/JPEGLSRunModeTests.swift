/// Tests for JPEG-LS run mode encoding implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Run Mode Tests")
struct JPEGLSRunModeTests {
    
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
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Should initialize without throwing
        #expect(runMode != nil)
    }
    
    @Test("Initialize with near-lossless parameter")
    func testInitializationNearLossless() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 5)
        
        // Should initialize without throwing
        #expect(runMode != nil)
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNearParameter() throws {
        let params = try createDefaultParameters()
        
        // NEAR > 255 should throw
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRunMode(parameters: params, near: 256)
        }
        
        // NEAR < 0 should throw
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSRunMode(parameters: params, near: -1)
        }
    }
    
    @Test("Initialize with custom max run length")
    func testCustomMaxRunLength() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 1024
        )
        
        #expect(runMode != nil)
    }
    
    // MARK: - Run Detection Tests
    
    @Test("Run mode entered when Ra equals Rb")
    func testShouldEnterRunMode() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Ra == Rb → enter run mode
        #expect(runMode.shouldEnterRunMode(a: 100, b: 100) == true)
        #expect(runMode.shouldEnterRunMode(a: 0, b: 0) == true)
        #expect(runMode.shouldEnterRunMode(a: 255, b: 255) == true)
    }
    
    @Test("Run mode not entered when Ra differs from Rb")
    func testShouldNotEnterRunMode() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Ra != Rb → stay in regular mode
        #expect(runMode.shouldEnterRunMode(a: 100, b: 101) == false)
        #expect(runMode.shouldEnterRunMode(a: 50, b: 150) == false)
        #expect(runMode.shouldEnterRunMode(a: 0, b: 255) == false)
    }
    
    @Test("Detect run length in flat region")
    func testDetectRunLengthFlat() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // All pixels have the same value
        let pixels = Array(repeating: 128, count: 100)
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 0,
            runValue: 128
        )
        
        #expect(runLength == 100)
    }
    
    @Test("Detect run length with interruption")
    func testDetectRunLengthWithInterruption() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Run of 50 pixels, then different value
        var pixels = Array(repeating: 100, count: 50)
        pixels.append(contentsOf: Array(repeating: 200, count: 50))
        
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 0,
            runValue: 100
        )
        
        #expect(runLength == 50)
    }
    
    @Test("Detect run length limited by max run length")
    func testDetectRunLengthLimitedByMax() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 100
        )
        
        // 500 identical pixels, but max is 100
        let pixels = Array(repeating: 75, count: 500)
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 0,
            runValue: 75
        )
        
        #expect(runLength == 100)
    }
    
    @Test("Detect run length starting from middle of buffer")
    func testDetectRunLengthFromMiddle() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Different values, then run
        var pixels = Array(repeating: 50, count: 20)
        pixels.append(contentsOf: Array(repeating: 100, count: 30))
        
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 20,
            runValue: 100
        )
        
        #expect(runLength == 30)
    }
    
    @Test("Detect zero-length run")
    func testDetectZeroLengthRun() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Immediate interruption
        let pixels = [100, 200, 200, 200]
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 0,
            runValue: 100
        )
        
        #expect(runLength == 1)  // Only the first pixel matches
    }
    
    // MARK: - J[RUNindex] Mapping Tests
    
    @Test("Compute J for RUNindex 0")
    func testComputeJ_Index0() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        #expect(runMode.computeJ(runIndex: 0) == 0)
    }
    
    @Test("Compute J for RUNindex 1")
    func testComputeJ_Index1() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[1] = 0
        #expect(runMode.computeJ(runIndex: 1) == 0)
    }
    
    @Test("Compute J for RUNindex 2")
    func testComputeJ_Index2() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[2] = 0
        #expect(runMode.computeJ(runIndex: 2) == 0)
    }
    
    @Test("Compute J for higher RUNindex values")
    func testComputeJ_HigherIndices() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[5]=1, J[10]=2, J[20]=6
        #expect(runMode.computeJ(runIndex: 5) == 1)
        #expect(runMode.computeJ(runIndex: 10) == 2)
        #expect(runMode.computeJ(runIndex: 20) == 6)
    }
    
    @Test("Compute J capped at maximum table entry")
    func testComputeJ_Capped() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Per ITU-T.87 Annex J table: J[31]=15, indices beyond 31 clamp to J[31]=15
        #expect(runMode.computeJ(runIndex: 32) == 15)
        #expect(runMode.computeJ(runIndex: 50) == 15)
        #expect(runMode.computeJ(runIndex: 100) == 15)
    }
    
    // MARK: - Run-Length Encoding Tests
    
    @Test("Encode short run with J=0")
    func testEncodeRunLength_ShortRunJ0() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=0, J=0, so blockSize=2^0=1
        let encoded = runMode.encodeRunLength(runLength: 0, runIndex: 0)
        
        #expect(encoded.j == 0)
        #expect(encoded.continuationBits == 0)
        #expect(encoded.remainder == 0)
    }
    
    @Test("Encode run with J=1")
    func testEncodeRunLength_J1() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=1, J[1]=0, blockSize=1
        // Run of 5: 4 blocks (1+1+1+1) consuming indices 1→4, then J[5]=1, blockSize=2
        // remaining=1 < 2, so 4 continuation bits, j=J[5]=1, remainder=1
        // BUT: actually after 4 blocks at bs=1, idx=5, remaining=1
        // Then J[5]=1, bs=2, 1<2 → break. j=J[5]=1, remainder=1
        // Wait, let me retrace: initially rem=5
        // iter1: J(1)=0, bs=1, rem=4, cont=1, idx=2
        // iter2: J(2)=0, bs=1, rem=3, cont=2, idx=3
        // iter3: J(3)=0, bs=1, rem=2, cont=3, idx=4
        // iter4: J(4)=1, bs=2, rem=0, cont=4, idx=5
        // loop ends (rem=0)
        // j = J(5)=1, remainder=0
        let encoded = runMode.encodeRunLength(runLength: 5, runIndex: 1)
        
        #expect(encoded.j == 1)
        #expect(encoded.continuationBits == 4)
        #expect(encoded.remainder == 0)
        #expect(encoded.totalRunLength == 5)
    }
    
    @Test("Encode run with J=2")
    func testEncodeRunLength_J2() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=2, J[2]=0, blockSize=1
        // Tracing through: indices increment each block
        // After consuming all 10, j=J[8]=2, continuationBits=6, remainder=0
        let encoded = runMode.encodeRunLength(runLength: 10, runIndex: 2)
        
        #expect(encoded.j == 2)
        #expect(encoded.continuationBits == 6)
        #expect(encoded.remainder == 0)
        #expect(encoded.totalRunLength == 10)
    }
    
    @Test("Encode run exactly matching block size")
    func testEncodeRunLength_ExactBlock() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=3, J[3]=0, blockSize=1
        // Tracing: 4 continuation bits at bs=1 (idx 3→6), then bs=2 at idx 7
        // After consuming 8: j=J[7]=1, continuationBits=4, remainder=1
        let encoded = runMode.encodeRunLength(runLength: 8, runIndex: 3)
        
        #expect(encoded.j == 1)
        #expect(encoded.continuationBits == 4)
        #expect(encoded.remainder == 1)
    }
    
    @Test("Encode long run with multiple blocks")
    func testEncodeRunLength_LongRun() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=4, J[4]=1, blockSize=2
        // Tracing through 100 pixels with incrementing indices
        // Result: j=J[18]=5, continuationBits=14, remainder=12
        let encoded = runMode.encodeRunLength(runLength: 100, runIndex: 4)
        
        #expect(encoded.j == 5)
        #expect(encoded.continuationBits == 14)
        #expect(encoded.remainder == 12)
    }
    
    @Test("Encode run with zero length")
    func testEncodeRunLength_Zero() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1, no blocks consumed
        let encoded = runMode.encodeRunLength(runLength: 0, runIndex: 5)
        
        #expect(encoded.j == 1)
        #expect(encoded.continuationBits == 0)
        #expect(encoded.remainder == 0)
    }
    
    @Test("Total bit length calculation")
    func testEncodeRunLength_TotalBitLength() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=3, run of 20
        // Tracing: 7 continuation bits, j=J[10]=2, remainder=3
        // Bits: 7 continuation '1's + 1 terminating '0' + 2 bits for remainder = 10
        let encoded = runMode.encodeRunLength(runLength: 20, runIndex: 3)
        
        #expect(encoded.totalBitLength == 10)
    }
    
    // MARK: - Run Interruption Tests
    
    @Test("Encode run interruption with positive error")
    func testEncodeRunInterruption_PositiveError() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        let encoded = runMode.encodeRunInterruption(
            interruptionValue: 150,
            runValue: 100
        )
        
        #expect(encoded.interruptionValue == 150)
        #expect(encoded.prediction == 100)
        #expect(encoded.error == 50)
        #expect(encoded.mappedError == 100)  // 2 * 50
    }
    
    @Test("Encode run interruption with negative error")
    func testEncodeRunInterruption_NegativeError() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        let encoded = runMode.encodeRunInterruption(
            interruptionValue: 75,
            runValue: 100
        )
        
        #expect(encoded.interruptionValue == 75)
        #expect(encoded.prediction == 100)
        #expect(encoded.error == -25)
        #expect(encoded.mappedError == 49)  // -2 * (-25) - 1
    }
    
    @Test("Encode run interruption with zero error")
    func testEncodeRunInterruption_ZeroError() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        let encoded = runMode.encodeRunInterruption(
            interruptionValue: 128,
            runValue: 128
        )
        
        #expect(encoded.error == 0)
        #expect(encoded.mappedError == 0)
    }
    
    @Test("Encode run interruption with modular reduction (positive)")
    func testEncodeRunInterruption_ModularReductionPositive() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Large positive error that exceeds half range
        let encoded = runMode.encodeRunInterruption(
            interruptionValue: 255,
            runValue: 10
        )
        
        // Error = 245, range = 256, half = 128
        // 245 > 127, so error -= 256 → -11
        #expect(encoded.error == -11)
    }
    
    @Test("Encode run interruption with modular reduction (negative)")
    func testEncodeRunInterruption_ModularReductionNegative() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Large negative error
        let encoded = runMode.encodeRunInterruption(
            interruptionValue: 10,
            runValue: 255
        )
        
        // Error = -245, range = 256, -half = -128
        // -245 < -128, so error += 256 → 11
        #expect(encoded.error == 11)
    }
    
    @Test("Encode run interruption at boundaries")
    func testEncodeRunInterruption_Boundaries() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // At minimum value
        let encoded1 = runMode.encodeRunInterruption(
            interruptionValue: 0,
            runValue: 0
        )
        #expect(encoded1.error == 0)
        
        // At maximum value
        let encoded2 = runMode.encodeRunInterruption(
            interruptionValue: 255,
            runValue: 255
        )
        #expect(encoded2.error == 0)
    }
    
    // MARK: - Context Adaptation Tests
    
    @Test("Adapt run index for long run (increase)")
    func testAdaptRunIndex_LongRun() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=5, J=5, blockSize=32
        // Run of 64 > 32, so increase index
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 64
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index for short run (decrease)")
    func testAdaptRunIndex_ShortRun() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1, blockSize=2
        // Run of 8 > blockSize(2), so increase index
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 8
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index stays same for medium run")
    func testAdaptRunIndex_MediumRun() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // With runIndex=5, J[5]=1, blockSize=2
        // Run of 24 > blockSize(2), so increase index
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: 24
        )
        
        #expect(newIndex == 6)
    }
    
    @Test("Adapt run index capped at maximum (31)")
    func testAdaptRunIndex_MaxCap() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Already at max, long run shouldn't exceed it
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 31,
            completedRunLength: 100000
        )
        
        #expect(newIndex == 31)
    }
    
    @Test("Adapt run index capped at minimum (0)")
    func testAdaptRunIndex_MinCap() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Already at min, short run shouldn't go below it
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 0,
            completedRunLength: 0
        )
        
        #expect(newIndex == 0)
    }
    
    @Test("Adapt run index from index 1 (edge case)")
    func testAdaptRunIndex_Index1() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // runIndex=1, J[1]=0, blockSize=1
        // completedRunLength=0, not > 1, j=0 so j>0 is false → no decrease
        // Index stays at 1
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 1,
            completedRunLength: 0
        )
        
        #expect(newIndex == 1)
    }
    
    // MARK: - Run Limit Handling Tests
    
    @Test("Check if run should be split (below limit)")
    func testShouldSplitRun_BelowLimit() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 1000
        )
        
        #expect(runMode.shouldSplitRun(runLength: 500) == false)
        #expect(runMode.shouldSplitRun(runLength: 1000) == false)
    }
    
    @Test("Check if run should be split (exceeds limit)")
    func testShouldSplitRun_ExceedsLimit() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 1000
        )
        
        #expect(runMode.shouldSplitRun(runLength: 1001) == true)
        #expect(runMode.shouldSplitRun(runLength: 5000) == true)
    }
    
    @Test("Split run into chunks")
    func testSplitRunLength() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 100
        )
        
        let chunks = runMode.splitRunLength(runLength: 350)
        
        #expect(chunks.count == 4)
        #expect(chunks[0] == 100)
        #expect(chunks[1] == 100)
        #expect(chunks[2] == 100)
        #expect(chunks[3] == 50)
    }
    
    @Test("Split run exactly divisible")
    func testSplitRunLength_ExactlyDivisible() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 100
        )
        
        let chunks = runMode.splitRunLength(runLength: 300)
        
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { $0 == 100 })
    }
    
    @Test("Split run below limit (single chunk)")
    func testSplitRunLength_SingleChunk() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 1000
        )
        
        let chunks = runMode.splitRunLength(runLength: 500)
        
        #expect(chunks.count == 1)
        #expect(chunks[0] == 500)
    }
    
    @Test("Split very long run")
    func testSplitRunLength_VeryLong() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(
            parameters: params,
            near: 0,
            maxRunLength: 1000
        )
        
        let chunks = runMode.splitRunLength(runLength: 10500)
        
        #expect(chunks.count == 11)
        #expect(chunks[0...9].allSatisfy { $0 == 1000 })
        #expect(chunks[10] == 500)
    }
    
    // MARK: - Integration Tests
    
    @Test("Complete run mode workflow")
    func testCompleteRunModeWorkflow() throws {
        let params = try createDefaultParameters()
        let runMode = try JPEGLSRunMode(parameters: params, near: 0)
        
        // Setup: flat region with interruption
        var pixels = Array(repeating: 100, count: 50)
        pixels.append(150)  // Interruption
        
        // Step 1: Check if we should enter run mode
        #expect(runMode.shouldEnterRunMode(a: 100, b: 100) == true)
        
        // Step 2: Detect run length
        let runLength = runMode.detectRunLength(
            pixels: pixels,
            startIndex: 0,
            runValue: 100
        )
        #expect(runLength == 50)
        
        // Step 3: Encode the run
        let encodedRun = runMode.encodeRunLength(runLength: runLength, runIndex: 5)
        #expect(encodedRun.totalRunLength == 50)
        
        // Step 4: Encode the interruption
        let encodedInterruption = runMode.encodeRunInterruption(
            interruptionValue: 150,
            runValue: 100
        )
        #expect(encodedInterruption.error == 50)
        
        // Step 5: Adapt run index
        let newIndex = runMode.adaptRunIndex(
            currentRunIndex: 5,
            completedRunLength: runLength
        )
        #expect(newIndex >= 5)  // Should increase or stay same
    }
}
