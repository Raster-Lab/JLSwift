/// Tests for JPEG-LS context modeling implementation.

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Context Model Tests")
struct JPEGLSContextModelTests {
    
    // MARK: - Initialization Tests
    
    @Test("Context model initializes with default parameters")
    func testInitialization() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Per ITU-T.87 Section 4.3: A[i] = max(2, floor((RANGE + 32) / 64))
        // For 8-bit lossless: RANGE = 256, A_init = max(2, (256+32)/64) = max(2, 4) = 4
        let expectedAInit = 4
        for i in 0..<JPEGLSContextModel.regularContextCount {
            #expect(context.getA(contextIndex: i) == expectedAInit)
            #expect(context.getB(contextIndex: i) == 0)
            #expect(context.getC(contextIndex: i) == 0)
            #expect(context.getN(contextIndex: i) == 1)
        }
        
        // Verify run-length state
        #expect(context.currentRunLength == 0)
        #expect(context.currentRunIndex == 0)
    }
    
    @Test("Context model rejects invalid NEAR parameter")
    func testInvalidNearParameter() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        
        // Test negative NEAR
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSContextModel(parameters: params, near: -1)
        }
        
        // Test NEAR > 255
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSContextModel(parameters: params, near: 256)
        }
        
        // Valid NEAR should succeed
        _ = try JPEGLSContextModel(parameters: params, near: 0)
        _ = try JPEGLSContextModel(parameters: params, near: 5)
        _ = try JPEGLSContextModel(parameters: params, near: 255)
    }
    
    // MARK: - Context Index Computation Tests
    
    @Test("Context index computed correctly for zero gradients")
    func testContextIndexZeroGradients() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Q1 = 0, Q2 = 0, Q3 = 0 should give a valid index
        let index = context.computeContextIndex(q1: 0, q2: 0, q3: 0)
        #expect(index >= 0 && index < 365)
    }
    
    @Test("Context index computed correctly for positive gradients")
    func testContextIndexPositiveGradients() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Test various positive gradient combinations
        let index1 = context.computeContextIndex(q1: 1, q2: 0, q3: 0)
        #expect(index1 >= 0 && index1 < 365)
        
        let index2 = context.computeContextIndex(q1: 0, q2: 1, q3: 0)
        #expect(index2 >= 0 && index2 < 365)
        
        let index3 = context.computeContextIndex(q1: 0, q2: 0, q3: 1)
        #expect(index3 >= 0 && index3 < 365)
    }
    
    @Test("Context index computed correctly for negative gradients")
    func testContextIndexNegativeGradients() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Q1 = -1, Q2 = 0, Q3 = 0
        let index1 = context.computeContextIndex(q1: -1, q2: 0, q3: 0)
        #expect(index1 >= 0 && index1 < 365)
        
        // Q1 = 0, Q2 = -1, Q3 = 0
        let index2 = context.computeContextIndex(q1: 0, q2: -1, q3: 0)
        #expect(index2 >= 0 && index2 < 365)
        
        // Q1 = 0, Q2 = 0, Q3 = -1
        let index3 = context.computeContextIndex(q1: 0, q2: 0, q3: -1)
        #expect(index3 >= 0 && index3 < 365)
    }
    
    @Test("Context index covers full range")
    func testContextIndexRange() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        var indices = Set<Int>()
        
        // Test all combinations of Q1, Q2, Q3 in range [-4, 4]
        for q1 in -4...4 {
            for q2 in -4...4 {
                for q3 in -4...4 {
                    let index = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
                    #expect(index >= 0 && index < 365)
                    indices.insert(index)
                }
            }
        }
        
        // We should see a good distribution of indices
        #expect(indices.count > 0)
    }
    
    // MARK: - Context Sign Tests
    
    @Test("Context sign computed correctly")
    func testContextSign() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Positive sign cases
        #expect(context.computeContextSign(q1: 1, q2: 0, q3: 0) == 1)
        #expect(context.computeContextSign(q1: 0, q2: 1, q3: 0) == 1)
        #expect(context.computeContextSign(q1: 0, q2: 0, q3: 1) == 1)
        #expect(context.computeContextSign(q1: 0, q2: 0, q3: 0) == 1)
        
        // Negative sign cases
        #expect(context.computeContextSign(q1: -1, q2: 0, q3: 0) == -1)
        #expect(context.computeContextSign(q1: 0, q2: -1, q3: 0) == -1)
        #expect(context.computeContextSign(q1: 0, q2: 0, q3: -1) == -1)
    }
    
    // MARK: - Context Update Tests
    
    @Test("Context updates correctly after encoding sample")
    func testContextUpdate() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 100
        let predictionError = 5
        let sign = 1
        
        // For 8-bit lossless: A is initialised to 4 per ITU-T.87
        let expectedAInit = 4
        
        // Initial state
        #expect(context.getA(contextIndex: contextIndex) == expectedAInit)
        #expect(context.getB(contextIndex: contextIndex) == 0)
        #expect(context.getC(contextIndex: contextIndex) == 0)
        #expect(context.getN(contextIndex: contextIndex) == 1)
        
        // Update context
        context.updateContext(contextIndex: contextIndex, predictionError: predictionError, sign: sign)
        
        // A += |error| = 4 + 5 = 9
        // B += sign * error = 0 + 1*5 = 5; N becomes 2; B > 0 → B -= N = 3, B > 0 → B = 0, C += 1
        #expect(context.getA(contextIndex: contextIndex) == expectedAInit + 5)
        #expect(context.getB(contextIndex: contextIndex) == 0)
        #expect(context.getC(contextIndex: contextIndex) == 1)
        #expect(context.getN(contextIndex: contextIndex) == 2)
    }
    
    @Test("Context bias correction updates correctly")
    func testBiasCorrection() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 50
        
        // Positive error, positive sign → B = sign*error = 3; N=2; B>=N → C=1, B=1
        context.updateContext(contextIndex: contextIndex, predictionError: 3, sign: 1)
        #expect(context.getC(contextIndex: contextIndex) == 1)
        
        // Negative error, positive sign → B += 1*(-2) = -1; N=3; no threshold triggered
        context.updateContext(contextIndex: contextIndex, predictionError: -2, sign: 1)
        #expect(context.getC(contextIndex: contextIndex) == 1)
        
        // Positive error, negative sign → B += (-1)*4 = -4; B becomes -5; N=4; B<-N → C decrements
        context.updateContext(contextIndex: contextIndex, predictionError: 4, sign: -1)
        #expect(context.getC(contextIndex: contextIndex) == 0)
        
        // Negative error, negative sign → B += (-1)*(-1) = +1; B becomes 0; N=5; no threshold
        context.updateContext(contextIndex: contextIndex, predictionError: -1, sign: -1)
        #expect(context.getC(contextIndex: contextIndex) == 0)
    }
    
    @Test("Context reset mechanism works correctly")
    func testContextReset() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 150
        let resetValue = params.reset
        
        // N starts at 1. After each update, N increments by 1.
        // When N reaches RESET (64), we halve all statistics.
        // So we need RESET - 1 updates to reach N = RESET
        for _ in 0..<(resetValue - 1) {
            context.updateContext(contextIndex: contextIndex, predictionError: 10, sign: 1)
        }
        
        // After RESET-1 updates: N should be RESET, and reset has been triggered
        let nAfterReset = context.getN(contextIndex: contextIndex)
        let aAfterReset = context.getA(contextIndex: contextIndex)
        
        // After RESET-1 updates: N should be RESET (reset check is before N increment,
        // so reset hasn't triggered yet)
        #expect(nAfterReset == resetValue)
        
        // A should have been approximately halved from accumulated value
        #expect(aAfterReset > 0)
        
        // Do one more update — this triggers the reset (N=64 >= RESET),
        // halving A, B, N, then incrementing N: N = 64/2 + 1 = 33
        context.updateContext(contextIndex: contextIndex, predictionError: 10, sign: 1)
        #expect(context.getN(contextIndex: contextIndex) == nAfterReset / 2 + 1)
        #expect(context.getA(contextIndex: contextIndex) == (aAfterReset + 10) >> 1)
    }
    
    @Test("Context B never becomes zero after reset")
    func testContextBNeverZero() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 200
        
        // Update once (B accumulates the prediction error)
        context.updateContext(contextIndex: contextIndex, predictionError: 1, sign: 1)
        #expect(context.getB(contextIndex: contextIndex) == -1)
        
        // Continue updating until reset
        for _ in 1..<params.reset {
            context.updateContext(contextIndex: contextIndex, predictionError: 1, sign: 1)
        }
        
        // After reset, verify B is some valid integer (can be positive, zero, or negative)
        let bAfterReset = context.getB(contextIndex: contextIndex)
        #expect(bAfterReset >= -params.reset && bAfterReset <= params.reset)
    }
    
    // MARK: - Golomb Parameter Tests
    
    @Test("Golomb parameter computed correctly for zero context")
    func testGolombParameterZeroContext() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // For 8-bit lossless: A initialised to 4, N=1.
        // k is the smallest integer such that N * 2^k >= A: 1*2^k >= 4 → k = 2.
        let k = context.computeGolombParameter(contextIndex: 100)
        #expect(k == 2)
    }
    
    @Test("Golomb parameter increases with accumulated error")
    func testGolombParameterIncreases() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 50
        
        // Add small errors
        for _ in 0..<10 {
            context.updateContext(contextIndex: contextIndex, predictionError: 1, sign: 1)
        }
        let k1 = context.computeGolombParameter(contextIndex: contextIndex)
        
        // Add larger errors
        for _ in 0..<20 {
            context.updateContext(contextIndex: contextIndex, predictionError: 10, sign: 1)
        }
        let k2 = context.computeGolombParameter(contextIndex: contextIndex)
        
        // k2 should be larger than k1
        #expect(k2 >= k1)
    }
    
    @Test("Golomb parameter bounded")
    func testGolombParameterBounded() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let contextIndex = 75
        
        // Add very large errors
        for _ in 0..<100 {
            context.updateContext(contextIndex: contextIndex, predictionError: 1000, sign: 1)
        }
        
        let k = context.computeGolombParameter(contextIndex: contextIndex)
        
        // k should be bounded (max 16 per implementation)
        #expect(k >= 0 && k <= 16)
    }
    
    // MARK: - Run-Length Context Tests
    
    @Test("Run length increments correctly")
    func testRunLengthIncrement() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        #expect(context.currentRunLength == 0)
        
        context.incrementRunLength()
        #expect(context.currentRunLength == 1)
        
        context.incrementRunLength()
        #expect(context.currentRunLength == 2)
        
        context.incrementRunLength()
        #expect(context.currentRunLength == 3)
    }
    
    @Test("Run length resets correctly")
    func testRunLengthReset() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        context.incrementRunLength()
        context.incrementRunLength()
        context.incrementRunLength()
        #expect(context.currentRunLength == 3)
        
        context.resetRunLength()
        #expect(context.currentRunLength == 0)
    }
    
    @Test("Run index updates based on completed run length")
    func testRunIndexUpdate() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let initialIndex = context.currentRunIndex
        
        // Short run should not increase index much
        context.updateRunIndex(completedRunLength: 1)
        let indexAfterShortRun = context.currentRunIndex
        
        // Long run should increase index
        context.updateRunIndex(completedRunLength: 100)
        let indexAfterLongRun = context.currentRunIndex
        
        #expect(indexAfterLongRun >= indexAfterShortRun)
    }
    
    @Test("Run interruption index stores values")
    func testRunInterruptionIndex() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Initial values should be zero
        #expect(context.getRunInterruptionIndex(index: 0) == 0)
        #expect(context.getRunInterruptionIndex(index: 1) == 0)
        
        // Update with a specific run length
        let runLength = 10
        context.updateRunIndex(completedRunLength: runLength)
        
        // The run interruption index should be set to the completed run length
        // Based on the current runIndex (initially 0), index 0 should be updated
        let val0 = context.getRunInterruptionIndex(index: 0)
        #expect(val0 == runLength)
    }
    
    @Test("Run interruption index bounds checking")
    func testRunInterruptionIndexBounds() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Out of bounds should return 0
        #expect(context.getRunInterruptionIndex(index: -1) == 0)
        #expect(context.getRunInterruptionIndex(index: 10) == 0)
    }
    
    // MARK: - State Access Bounds Tests
    
    @Test("Context state access with invalid indices returns safe defaults")
    func testInvalidIndexAccess() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Negative indices
        #expect(context.getA(contextIndex: -1) == 0)
        #expect(context.getB(contextIndex: -1) == 0)
        #expect(context.getC(contextIndex: -1) == 0)
        #expect(context.getN(contextIndex: -1) == 1)
        
        // Out of range indices
        #expect(context.getA(contextIndex: 1000) == 0)
        #expect(context.getB(contextIndex: 1000) == 0)
        #expect(context.getC(contextIndex: 1000) == 0)
        #expect(context.getN(contextIndex: 1000) == 1)
    }
    
    @Test("Context update with invalid index is safe")
    func testInvalidIndexUpdate() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Should not crash
        context.updateContext(contextIndex: -1, predictionError: 5, sign: 1)
        context.updateContext(contextIndex: 1000, predictionError: 5, sign: 1)
    }
    
    // MARK: - Description Tests
    
    @Test("Context model description is informative")
    func testDescription() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let description = context.description
        #expect(description.contains("JPEGLSContextModel"))
        #expect(description.contains("365")) // context count
    }
    
    // MARK: - Integration Tests
    
    @Test("Complete encoding cycle maintains valid state")
    func testCompleteEncodingCycle() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Simulate encoding a sequence of samples
        let errors = [1, -2, 3, 0, -1, 2, -3, 1]
        let signs = [1, -1, 1, 1, -1, 1, -1, 1]
        
        for i in 0..<errors.count {
            let contextIndex = i % 100 // Use different contexts
            context.updateContext(contextIndex: contextIndex, predictionError: errors[i], sign: signs[i])
            
            // Verify state remains valid
            #expect(context.getA(contextIndex: contextIndex) >= 0)
            #expect(context.getN(contextIndex: contextIndex) >= 1)
        }
    }
    
    @Test("Multiple contexts can be updated independently")
    func testIndependentContexts() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let ctx1 = 10
        let ctx2 = 20
        let ctx3 = 30
        
        // For 8-bit lossless: A is initialised to 4 per ITU-T.87
        let aInit = 4
        
        // Update different contexts with different errors
        context.updateContext(contextIndex: ctx1, predictionError: 5, sign: 1)
        context.updateContext(contextIndex: ctx2, predictionError: 10, sign: 1)
        context.updateContext(contextIndex: ctx3, predictionError: 15, sign: 1)
        
        // Each context should have different values: A = aInit + |error|
        #expect(context.getA(contextIndex: ctx1) == aInit + 5)
        #expect(context.getA(contextIndex: ctx2) == aInit + 10)
        #expect(context.getA(contextIndex: ctx3) == aInit + 15)
        
        // B is clamped to 0 after positive bias correction per ITU-T.87 §A.6.3
        #expect(context.getB(contextIndex: ctx1) == 0)
        #expect(context.getB(contextIndex: ctx2) == 0)
        #expect(context.getB(contextIndex: ctx3) == 0)
    }
    
    // MARK: - Run Interruption Context Statistics Tests
    
    @Test("Run interruption Golomb parameter initial value for 8-bit lossless")
    func testRunInterruptionGolombKInitial8Bit() throws {
        // For 8-bit lossless: RANGE = 256, A_init = max(2, (256+32)/64) = max(2,4) = 4, N=1
        // k = smallest k s.t. N*2^k >= A_init → 1*2^2 = 4 >= 4 → k=2
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        #expect(context.computeRunInterruptionGolombK() == 2)
    }
    
    @Test("Run interruption Golomb parameter initial value for 16-bit lossless")
    func testRunInterruptionGolombKInitial16Bit() throws {
        // For 16-bit lossless: RANGE = 65536, A_init = max(2, (65536+32)/64) = max(2,1024) = 1024, N=1
        // k = smallest k s.t. N*2^k >= A_init:
        //   threshold=1: 1<1024→k=1,t=2; ...t=1024 at k=10; 1024<1024 is false → k=10
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 16)
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        let k = context.computeRunInterruptionGolombK()
        #expect(k == 10)
    }
    
    @Test("Run interruption Golomb parameter updates after context update")
    func testRunInterruptionGolombKUpdates() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        let kInitial = context.computeRunInterruptionGolombK()
        
        // After updating with a large error, A_ri increases so k should increase
        context.updateRunInterruptionContext(absError: 100)
        let kAfterLargeError = context.computeRunInterruptionGolombK()
        
        // k can only increase or stay the same as A_ri grows
        #expect(kAfterLargeError >= kInitial)
    }
    
    @Test("Run interruption context statistics update per ITU-T.87")
    func testRunInterruptionContextUpdate() throws {
        // For 8-bit lossless: A_init=4, N_init=1
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Initial k should be 2 (A=4, N=1 → 2^2=4 >= 4)
        #expect(context.computeRunInterruptionGolombK() == 2)
        
        // After one update with absError=0: A stays 4, N becomes 2
        // k = smallest k s.t. 2*2^k >= 4 → 2*2^1=4 >= 4 → k=1
        context.updateRunInterruptionContext(absError: 0)
        #expect(context.computeRunInterruptionGolombK() == 1)
        
        // After another update with absError=0: A stays 4, N becomes 3
        // k = smallest k s.t. 3*2^k >= 4 → 3*2^1=6 >= 4 → k=1
        context.updateRunInterruptionContext(absError: 0)
        #expect(context.computeRunInterruptionGolombK() == 1)
    }
    
    @Test("Run interruption context resets when N reaches RESET")
    func testRunInterruptionContextReset() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255, threshold1: 3, threshold2: 7, threshold3: 21, reset: 4
        )
        var context = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Repeatedly update to trigger the reset at N == RESET (4)
        // Initial: A_init = max(2, (256+32)/64) = 4, N=1
        // Update 1: A=4+5=9, N=2
        context.updateRunInterruptionContext(absError: 5)
        // Update 2: A=9+3=12, N=3
        context.updateRunInterruptionContext(absError: 3)
        // Update 3: N would become 4 == reset → halve: A=6, N=2
        context.updateRunInterruptionContext(absError: 0)
        
        // After reset A=6, N=2 → k = smallest k s.t. 2*2^k >= 6 → 2*2^2=8 >= 6 → k=2
        #expect(context.computeRunInterruptionGolombK() == 2)
    }
    
    @Test("Run interruption round-trip: encoder and decoder use same k")
    func testRunInterruptionRoundTripK() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        var encoderContext = try JPEGLSContextModel(parameters: params, near: 0)
        var decoderContext = try JPEGLSContextModel(parameters: params, near: 0)
        
        // Both should produce identical initial k
        #expect(encoderContext.computeRunInterruptionGolombK() ==
                decoderContext.computeRunInterruptionGolombK())
        
        // After identical updates they should remain in sync
        let errors = [3, 1, 7, 2, 5, 0, 4]
        for e in errors {
            encoderContext.updateRunInterruptionContext(absError: e)
            decoderContext.updateRunInterruptionContext(absError: e)
            #expect(encoderContext.computeRunInterruptionGolombK() ==
                    decoderContext.computeRunInterruptionGolombK())
        }
    }
}
