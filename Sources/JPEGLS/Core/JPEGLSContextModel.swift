/// JPEG-LS context modeling implementation per ITU-T.87 Section 4.
///
/// Context modeling is at the heart of JPEG-LS compression. It maintains
/// adaptive statistics for different local contexts to achieve efficient
/// entropy coding of prediction errors.

import Foundation

/// Context state for JPEG-LS adaptive encoding/decoding.
///
/// The JPEG-LS standard uses 365 regular-mode contexts, each maintaining
/// its own statistics that adapt during encoding/decoding. These statistics
/// include accumulated error (A), sample count (B), bias correction (C),
/// and occurrence counter (N) for reset operations.
public struct JPEGLSContextModel: Sendable {
    // MARK: - Constants
    
    /// Number of regular-mode contexts as defined by ITU-T.87
    public static let regularContextCount = 365
    
    /// Number of run-length contexts
    public static let runContextCount = 2
    
    // MARK: - Context State Arrays
    
    /// Accumulated prediction error sum for each context.
    /// Used to compute the bias correction term.
    private var contextA: [Int]
    
    /// Context occurrence counter.
    /// Tracks how many times each context has been used.
    private var contextB: [Int]
    
    /// Bias correction value for each context.
    /// Represents the accumulated bias in prediction errors.
    private var contextC: [Int]
    
    /// Sample counter for reset operations.
    /// When N reaches the RESET value, context statistics are halved.
    private var contextN: [Int]
    
    // MARK: - Run-Length State
    
    /// Run interruption context index array (J[])
    /// Used for run-length encoding context selection.
    private var runInterruptionIndex: [Int]
    
    /// Run interruption accumulated absolute error (A_ri) per ITU-T.87 §4.5.3.
    /// Index 0 = RItype 0 (Ra ≠ Rb), Index 1 = RItype 1 (Ra ≈ Rb).
    private var runInterruptionA: [Int]
    
    /// Run interruption sample count (N_ri) per ITU-T.87 §4.5.3.
    /// Index 0 = RItype 0, Index 1 = RItype 1.
    private var runInterruptionN: [Int]
    
    /// Run interruption negative error count (nn) per ITU-T.87.
    /// Used for map computation in run interruption coding.
    /// Index 0 = RItype 0, Index 1 = RItype 1.
    private var runInterruptionNN: [Int]
    
    /// Current run length counter
    private var runLength: Int
    
    /// Maximum run length index (RUNindex)
    private var runIndex: Int
    
    // MARK: - Parameters
    
    /// Preset parameters controlling context behaviour
    private let parameters: JPEGLSPresetParameters
    
    /// Near-lossless parameter (0 for lossless)
    private let near: Int
    
    /// A[i] initial value per ITU-T.87 Section 4.3: max(2, floor((RANGE + 32) / 64))
    private let aInit: Int
    
    // MARK: - Initialization
    
    /// Initialize context model with preset parameters.
    ///
    /// - Parameters:
    ///   - parameters: Preset parameters (thresholds, MAXVAL, RESET)
    ///   - near: Near-lossless parameter (0 for lossless mode)
    /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is invalid
    public init(parameters: JPEGLSPresetParameters, near: Int = 0) throws {
        guard near >= 0 && near <= 255 else {
            throw JPEGLSError.invalidNearParameter(near: near)
        }
        
        self.parameters = parameters
        self.near = near
        
        // Compute RANGE per ITU-T.87 Section 4.2.1
        let range: Int
        if near == 0 {
            range = parameters.maxValue + 1
        } else {
            let qbpp = (near << 1) | 1
            range = (parameters.maxValue + 2 * near) / qbpp + 1
        }
        
        // Compute A initial value per ITU-T.87 Section 4.3:
        // A[i] = max(2, floor((RANGE + 32) / 64))
        self.aInit = max(2, (range + 32) / 64)
        
        // Initialize context arrays to default values per ITU-T.87 Section 4.3
        self.contextA = Array(repeating: 0, count: Self.regularContextCount)
        self.contextB = Array(repeating: 0, count: Self.regularContextCount)
        self.contextC = Array(repeating: 0, count: Self.regularContextCount)
        self.contextN = Array(repeating: 1, count: Self.regularContextCount)
        
        // Initialize run-length state
        self.runInterruptionIndex = Array(repeating: 0, count: Self.runContextCount)
        // Initialise run interruption statistics per ITU-T.87 §4.5.3 / CharLS.
        // Two contexts: index 0 for RItype=0, index 1 for RItype=1.
        let riAInit = max(2, (range + 32) / 64)
        self.runInterruptionA = [riAInit, riAInit]
        self.runInterruptionN = [1, 1]
        self.runInterruptionNN = [0, 0]
        self.runLength = 0
        self.runIndex = 0
        
        // Set initial context values according to ITU-T.87
        initializeContexts()
    }
    
    /// Initialize all context statistics to their default values.
    ///
    /// Per ITU-T.87 Section 4.3, contexts are initialised with:
    /// - A[i] = max(2, floor((RANGE + 32) / 64))
    /// - B[i] = 0
    /// - C[i] = 0
    /// - N[i] = 1
    private mutating func initializeContexts() {
        for i in 0..<Self.regularContextCount {
            contextA[i] = aInit
            contextB[i] = 0
            contextC[i] = 0
            contextN[i] = 1
        }
    }
    
    // MARK: - Context Index Computation
    
    /// Compute the context index from quantized gradients.
    ///
    /// The JPEG-LS standard uses 365 regular contexts, computed from
    /// three quantized gradients Q1, Q2, Q3 (each in range [-4, 4]).
    /// Per ITU-T.87 Section 4.3.1, symmetry properties are used to map
    /// the 9×9×9 = 729 possible combinations to 365 unique contexts.
    ///
    /// The mapping uses sign correction to ensure positive gradients,
    /// resulting in indices in the range [0, 364].
    ///
    /// - Parameters:
    ///   - q1: First quantized gradient (range: -4 to 4)
    ///   - q2: Second quantized gradient (range: -4 to 4)
    ///   - q3: Third quantized gradient (range: -4 to 4)
    /// - Returns: Context index (range: 0 to 364)
    public func computeContextIndex(q1: Int, q2: Int, q3: Int) -> Int {
        // Apply sign reversal symmetry per ITU-T.87 Section 4.3.1
        let sign = computeContextSign(q1: q1, q2: q2, q3: q3)
        
        // Normalise gradients so that the first non-zero value is positive.
        // After this step Q1 is in [0, 4]; Q2 and Q3 are in [-4, 4].
        let q1Adj = q1 * sign
        let q2Adj = q2 * sign
        let q3Adj = q3 * sign
        
        // Compute context index per ITU-T.87 Section 4.3.1:
        // Qt = 81 × Q1 + 9 × Q2 + Q3
        // After normalisation Qt lies in [0, 364] (365 distinct regular contexts).
        let index = 81 * q1Adj + 9 * q2Adj + q3Adj
        
        return max(0, min(index, Self.regularContextCount - 1))
    }
    
    /// Compute context sign for bias correction.
    ///
    /// The sign is used to determine the direction of bias correction
    /// based on the gradient pattern.
    ///
    /// - Parameters:
    ///   - q1: First quantized gradient
    ///   - q2: Second quantized gradient
    ///   - q3: Third quantized gradient
    /// - Returns: Context sign (+1 or -1)
    public func computeContextSign(q1: Int, q2: Int, q3: Int) -> Int {
        if q1 < 0 || (q1 == 0 && q2 < 0) || (q1 == 0 && q2 == 0 && q3 < 0) {
            return -1
        }
        return 1
    }
    
    // MARK: - Context State Access
    
    /// Get the accumulated error for a context.
    ///
    /// - Parameter contextIndex: Context index (0 to 364)
    /// - Returns: Accumulated error value
    public func getA(contextIndex: Int) -> Int {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return 0
        }
        return contextA[contextIndex]
    }
    
    /// Get the occurrence counter for a context.
    ///
    /// - Parameter contextIndex: Context index (0 to 364)
    /// - Returns: Occurrence counter value
    public func getB(contextIndex: Int) -> Int {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return 0
        }
        return contextB[contextIndex]
    }
    
    /// Get the bias correction for a context.
    ///
    /// - Parameter contextIndex: Context index (0 to 364)
    /// - Returns: Bias correction value
    public func getC(contextIndex: Int) -> Int {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return 0
        }
        return contextC[contextIndex]
    }
    
    /// Get the reset counter for a context.
    ///
    /// - Parameter contextIndex: Context index (0 to 364)
    /// - Returns: Reset counter value
    public func getN(contextIndex: Int) -> Int {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return 1
        }
        return contextN[contextIndex]
    }
    
    // MARK: - Context Update
    
    /// Update context statistics after encoding/decoding a sample.
    ///
    /// This method updates the A, B, C, and N arrays according to ITU-T.87
    /// Section 4.3. When N reaches RESET, statistics are halved to maintain
    /// adaptivity over the entire image.
    ///
    /// - Parameters:
    ///   - contextIndex: Context index (0 to 364)
    ///   - predictionError: The prediction error for this sample
    ///   - sign: Context sign (+1 or -1)
    public mutating func updateContext(contextIndex: Int, predictionError: Int, sign: Int) {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return
        }
        
        // Update A (accumulated absolute prediction error) per ITU-T.87
        contextA[contextIndex] += abs(predictionError)
        
        // Update B per ITU-T.87 §A.6.2: B[Q] += Errval × (2·NEAR + 1)
        // The caller passes predictionError = sign × Errval (sign-denormalised),
        // so sign × predictionError = Errval (sign-normalised error per the standard).
        let errval = sign * predictionError
        let bIncrement = errval * (2 * near + 1)
        contextB[contextIndex] += bIncrement
        
        // Reset when N reaches RESET value per ITU-T.87 Section A.6.2
        // Reset check happens BEFORE N is incremented (per standard and CharLS).
        if contextN[contextIndex] >= parameters.reset {
            contextA[contextIndex] = contextA[contextIndex] >> 1
            contextB[contextIndex] = contextB[contextIndex] >> 1
            contextN[contextIndex] = contextN[contextIndex] >> 1
            
            // Ensure N doesn't become zero
            if contextN[contextIndex] == 0 {
                contextN[contextIndex] = 1
            }
        }
        
        // Increment N (after reset check, before bias correction)
        contextN[contextIndex] += 1
        
        // Bias correction per ITU-T.87 Section A.6.3 (code segment A.13)
        let n = contextN[contextIndex]
        if contextB[contextIndex] + n <= 0 {
            contextB[contextIndex] += n
            if contextB[contextIndex] <= -n {
                contextB[contextIndex] = -n + 1
            }
            if contextC[contextIndex] > -128 {
                contextC[contextIndex] -= 1
            }
        } else if contextB[contextIndex] > 0 {
            contextB[contextIndex] -= n
            if contextB[contextIndex] > 0 {
                contextB[contextIndex] = 0
            }
            if contextC[contextIndex] < 127 {
                contextC[contextIndex] += 1
            }
        }
    }
    
    // MARK: - Golomb Parameter Calculation
    
    /// Compute the Golomb-Rice parameter k for a given context.
    ///
    /// The parameter k is used in Golomb-Rice coding and is computed
    /// from the accumulated error A and occurrence counter B.
    ///
    /// - Parameter contextIndex: Context index (0 to 364)
    /// - Returns: Golomb parameter k (non-negative integer)
    public func computeGolombParameter(contextIndex: Int) -> Int {
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else {
            return 0
        }
        
        let a = contextA[contextIndex]
        let n = contextN[contextIndex]  // Use N (occurrence counter), not B
        
        guard n > 0 else {
            return 0
        }
        
        var k = 0
        var threshold = n
        
        while threshold < a && k < 16 {
            threshold = threshold << 1
            k += 1
        }
        
        return k
    }
    
    /// Compute error correction for k=0 map swap per ITU-T.87 §A.5.2 / CharLS.
    ///
    /// Returns `bit_wise_sign(2*B[Q] + N[Q] - 1)`, i.e. −1 when
    /// `2*B[Q] + N[Q] <= 0` and 0 otherwise.  This matches the CharLS
    /// reference implementation (`regular_mode_context::get_error_correction`).
    /// Only applied when k=0 and near=0 (lossless mode).
    ///
    /// - Parameters:
    ///   - contextIndex: Context index (0 to 364)
    ///   - k: Current Golomb-Rice parameter
    /// - Returns: Error correction value (-1 or 0) for XOR with signed error
    public func getErrorCorrection(contextIndex: Int, k: Int) -> Int {
        guard k == 0 && near == 0 else { return 0 }
        guard contextIndex >= 0 && contextIndex < Self.regularContextCount else { return 0 }
        let b = contextB[contextIndex]
        let n = contextN[contextIndex]
        return (2 * b + n - 1) < 0 ? -1 : 0
    }
    
    // MARK: - Run-Length Context
    
    /// Get the current run length.
    public var currentRunLength: Int {
        return runLength
    }
    
    /// Get the current run index.
    public var currentRunIndex: Int {
        return runIndex
    }
    
    /// Increment run length counter.
    ///
    /// This is called for each pixel in a run of identical values.
    public mutating func incrementRunLength() {
        runLength += 1
    }
    
    /// Reset run length counter.
    ///
    /// Called when a run is interrupted or completed.
    public mutating func resetRunLength() {
        runLength = 0
    }
    
    /// Update run index based on run length.
    ///
    /// The run index determines which run-length context to use.
    ///
    /// - Parameter completedRunLength: Length of the completed run
    public mutating func updateRunIndex(completedRunLength: Int) {
        // Update J[RUNindex] per ITU-T.87 run-length coding
        if completedRunLength > 0 {
            let contextIdx = runIndex < Self.runContextCount ? runIndex : Self.runContextCount - 1
            runInterruptionIndex[contextIdx] = completedRunLength
            
            // Update runIndex based on completed run length
            // Longer runs increase runIndex, shorter runs decrease it
            if completedRunLength > (1 << runIndex) {
                runIndex = min(runIndex + 1, 31)
            } else if completedRunLength < (1 << (runIndex - 1)) && runIndex > 0 {
                runIndex -= 1
            }
        }
    }
    
    /// Set the run index directly.
    ///
    /// Used by the decoder when the run index is updated during run length decoding.
    ///
    /// - Parameter index: New run index value (0 to 31)
    public mutating func setRunIndex(_ index: Int) {
        runIndex = max(0, min(31, index))
    }
    
    /// Decrement the run index by 1 (minimum 0).
    ///
    /// Per CharLS, the run index is decremented after a run interruption
    /// pixel has been decoded — not during run-length reading.
    public mutating func decrementRunIndex() {
        if runIndex > 0 {
            runIndex -= 1
        }
    }
    
    /// Get run interruption index value.
    ///
    /// - Parameter index: Run context index (0 or 1)
    /// - Returns: Run interruption index value
    public func getRunInterruptionIndex(index: Int) -> Int {
        guard index >= 0 && index < Self.runContextCount else {
            return 0
        }
        return runInterruptionIndex[index]
    }
    
    // MARK: - Run Interruption Context Statistics
    
    /// Compute the Golomb-Rice parameter k for run interruption coding.
    ///
    /// Per ITU-T.87 §4.5.3 / CharLS `run_mode_context::compute_golomb_coding_parameter`:
    /// For RItype=1: temp = A + (N >> 1), find smallest k such that N × 2^k ≥ temp
    /// For RItype=0: temp = A, find smallest k such that N × 2^k ≥ temp
    ///
    /// - Parameter riType: Run interruption type (0 or 1)
    /// - Returns: Golomb-Rice parameter k (non-negative integer)
    public func computeRunInterruptionGolombK(riType: Int = 0) -> Int {
        let idx = min(max(riType, 0), 1)
        let n = runInterruptionN[idx]
        let a = runInterruptionA[idx]
        guard n > 0 else { return 0 }
        let temp = a + (n >> 1) * idx
        var k = 0
        var threshold = n
        while threshold < temp && k < 32 {
            threshold <<= 1
            k += 1
        }
        return k
    }
    
    /// Compute the error value from mapped error for run interruption.
    ///
    /// Per CharLS `run_mode_context::compute_error_value`:
    /// Uses nn (negative error count) and k to determine the sign of the error.
    ///
    /// - Parameters:
    ///   - temp: MErrval + riType (the adjusted mapped error)
    ///   - k: Golomb-Rice parameter
    ///   - riType: Run interruption type (0 or 1)
    /// - Returns: Signed error value
    public func computeRunInterruptionErrorValue(temp: Int, k: Int, riType: Int) -> Int {
        let idx = min(max(riType, 0), 1)
        let map = (temp & 1) != 0
        let errorValueAbs = (temp + (map ? 1 : 0)) / 2
        let nn = runInterruptionNN[idx]
        let n = runInterruptionN[idx]
        
        if (k != 0 || (2 * nn >= n)) == map {
            return -errorValueAbs
        }
        return errorValueAbs
    }
    
    /// Compute the map value for run interruption error mapping (encoder).
    ///
    /// Per CharLS `run_mode_context::compute_map`:
    ///
    /// - Parameters:
    ///   - errorValue: Signed error value
    ///   - k: Golomb-Rice parameter
    ///   - riType: Run interruption type (0 or 1)
    /// - Returns: true if map applies
    public func computeRunInterruptionMap(errorValue: Int, k: Int, riType: Int) -> Bool {
        let idx = min(max(riType, 0), 1)
        let nn = runInterruptionNN[idx]
        let n = runInterruptionN[idx]
        
        if k == 0 && errorValue > 0 && 2 * nn < n { return true }
        if errorValue < 0 && 2 * nn >= n { return true }
        if errorValue < 0 && k != 0 { return true }
        return false
    }
    
    /// Update run interruption context statistics after coding one interruption sample.
    ///
    /// Per CharLS `run_mode_context::update_variables` (Code segment A.23):
    /// - Track negative error count (nn)
    /// - Update A using (eMappedErrorValue + 1 - riType) >> 1
    /// - Reset when N reaches RESET
    ///
    /// - Parameters:
    ///   - errorValue: Signed prediction error
    ///   - eMappedErrorValue: The raw Golomb-decoded mapped error (before riType offset)
    ///   - riType: Run interruption type (0 or 1)
    public mutating func updateRunInterruptionContext(errorValue: Int, eMappedErrorValue: Int, riType: Int) {
        let idx = min(max(riType, 0), 1)
        
        if errorValue < 0 {
            runInterruptionNN[idx] += 1
        }
        
        runInterruptionA[idx] += (eMappedErrorValue + 1 - idx) >> 1
        
        if runInterruptionN[idx] == parameters.reset {
            runInterruptionA[idx] >>= 1
            runInterruptionN[idx] >>= 1
            runInterruptionNN[idx] >>= 1
        }
        
        runInterruptionN[idx] += 1
    }
    
    /// Legacy update method for backward compatibility with existing tests.
    ///
    /// - Parameter absError: Absolute value of the prediction error
    @available(*, deprecated, message: "Use updateRunInterruptionContext(errorValue:eMappedErrorValue:riType:)")
    public mutating func updateRunInterruptionContext(absError: Int) {
        updateRunInterruptionContext(errorValue: absError > 0 ? absError : -absError,
                                    eMappedErrorValue: 2 * absError,
                                    riType: 0)
    }
}

// MARK: - CustomStringConvertible

extension JPEGLSContextModel: CustomStringConvertible {
    /// Human-readable description of the context model state
    public var description: String {
        return "JPEGLSContextModel(contexts: \(Self.regularContextCount), near: \(near), reset: \(parameters.reset))"
    }
}
