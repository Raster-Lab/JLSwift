/// JPEG-LS run mode encoding implementation per ITU-T.87.
///
/// Run mode is used to efficiently encode runs of identical pixel values,
/// which are common in flat/uniform image regions. The algorithm tracks run
/// lengths and adapts its encoding strategy based on observed run patterns.

import Foundation

/// Run mode encoder for JPEG-LS compression.
///
/// The run mode encoder is triggered when Ra == Rb (left and top neighbors
/// are equal), suggesting a flat region. It implements:
/// 1. Run-length detection by scanning ahead for matching pixels
/// 2. Adaptive run-length encoding using J[RUNindex] mapping
/// 3. Run interruption sample encoding when runs terminate
/// 4. Context-based RUNindex adaptation for efficiency
public struct JPEGLSRunMode: Sendable {
    // MARK: - Properties
    
    /// Preset parameters controlling thresholds and limits
    private let parameters: JPEGLSPresetParameters
    
    /// Near-lossless parameter (0 for lossless mode)
    private let near: Int
    
    /// Maximum run length that can be encoded in one iteration
    /// Per ITU-T.87, this is typically limited to prevent excessive lookahead
    private let maxRunLength: Int
    
    // MARK: - Initialization
    
    /// Initialize run mode encoder with preset parameters.
    ///
    /// - Parameters:
    ///   - parameters: Preset parameters (thresholds, MAXVAL, RESET)
    ///   - near: Near-lossless parameter (0 for lossless mode)
    ///   - maxRunLength: Maximum run length to encode (default: 65536)
    /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is invalid
    public init(
        parameters: JPEGLSPresetParameters,
        near: Int = 0,
        maxRunLength: Int = 65536
    ) throws {
        guard near >= 0 && near <= 255 else {
            throw JPEGLSError.invalidNearParameter(near: near)
        }
        
        self.parameters = parameters
        self.near = near
        self.maxRunLength = maxRunLength
    }
    
    // MARK: - Run Detection
    
    /// Check if run mode should be entered.
    ///
    /// Per ITU-T.87 Section 4.5.1, run mode is entered when:
    /// - Ra == Rb (left and top neighbors are equal)
    ///
    /// This indicates a potentially flat region where run-length encoding
    /// will be more efficient than regular mode.
    ///
    /// - Parameters:
    ///   - a: Left neighbor pixel value (Ra)
    ///   - b: Top neighbor pixel value (Rb)
    /// - Returns: True if run mode should be entered
    public func shouldEnterRunMode(a: Int, b: Int) -> Bool {
        // Run mode entry condition per ITU-T.87 Section 4.5.1
        return a == b
    }
    
    /// Detect run length by scanning ahead for matching pixels.
    ///
    /// Scans the pixel buffer to count consecutive pixels that match
    /// the run value (Ra == Rb). The scan terminates when:
    /// - A different pixel value is encountered (run interruption)
    /// - The maximum run length is reached
    /// - The end of the scan line is reached
    ///
    /// - Parameters:
    ///   - pixels: Array of pixel values to scan
    ///   - startIndex: Index to start scanning from
    ///   - runValue: Expected pixel value for the run (Ra == Rb)
    /// - Returns: Number of consecutive matching pixels
    public func detectRunLength(
        pixels: [Int],
        startIndex: Int,
        runValue: Int
    ) -> Int {
        var runLength = 0
        let limit = min(pixels.count, startIndex + maxRunLength)
        
        // Scan ahead to count matching pixels
        for i in startIndex..<limit {
            if pixels[i] == runValue {
                runLength += 1
            } else {
                // Run interrupted
                break
            }
        }
        
        return runLength
    }
    
    // MARK: - J[RUNindex] Mapping
    
    /// Compute the number of bits required to encode a run length.
    ///
    /// Per ITU-T.87 Section 4.5.2, J[RUNindex] determines the bit allocation:
    /// - J[0] = 0 (very short runs use 0 bits for the count part)
    /// - J[1] = 1
    /// - J[2] = 2
    /// - J[i] = min(i, 32) for i > 2
    ///
    /// The J array adapts to the typical run length patterns in the image.
    ///
    /// - Parameter runIndex: Current run index (0 to 31)
    /// - Returns: Number of bits for encoding run length
    public func computeJ(runIndex: Int) -> Int {
        // J[RUNindex] mapping per ITU-T.87 Section 4.5.2
        switch runIndex {
        case 0:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        default:
            return min(runIndex, 32)
        }
    }
    
    // MARK: - Run-Length Encoding
    
    /// Encode a run of matching pixels.
    ///
    /// Per ITU-T.87 Section 4.5, run encoding consists of:
    /// 1. Determine J = J[RUNindex] (number of bits)
    /// 2. While run continues and exceeds 2^J samples:
    ///    - Output a '1' bit (indicating continuation)
    ///    - Subtract 2^J from run length
    /// 3. When run length < 2^J:
    ///    - Output a '0' bit (indicating termination)
    ///    - Output run length remainder in J bits
    ///
    /// - Parameters:
    ///   - runLength: Total length of the run
    ///   - runIndex: Current run index (determines J value)
    /// - Returns: Encoded run result with bit sequences
    public func encodeRunLength(runLength: Int, runIndex: Int) -> EncodedRun {
        let j = computeJ(runIndex: runIndex)
        let blockSize = 1 << j  // 2^J
        
        var remainingLength = runLength
        var continuationBits = 0
        
        // Count how many blocks of 2^J we can encode
        while remainingLength >= blockSize {
            continuationBits += 1
            remainingLength -= blockSize
        }
        
        // The remainder is encoded in J bits
        let remainder = remainingLength
        
        return EncodedRun(
            runIndex: runIndex,
            j: j,
            continuationBits: continuationBits,
            remainder: remainder,
            totalRunLength: runLength
        )
    }
    
    // MARK: - Run Interruption
    
    /// Encode a run interruption sample.
    ///
    /// When a run is interrupted by a different pixel value, that pixel
    /// is encoded using a prediction and error mapping similar to regular mode,
    /// but using a special run-interruption context.
    ///
    /// Per ITU-T.87 Section 4.5.4:
    /// - Predict the interruption value using the run value (Ra == Rb)
    /// - Compute prediction error: Errval = x - Ra
    /// - Map to non-negative: MErrval
    /// - Encode using Golomb-Rice with run-interruption context
    ///
    /// - Parameters:
    ///   - interruptionValue: Actual pixel value that interrupted the run
    ///   - runValue: The value of the run (Ra == Rb)
    /// - Returns: Encoded interruption result
    public func encodeRunInterruption(
        interruptionValue: Int,
        runValue: Int
    ) -> EncodedRunInterruption {
        // Simple prediction: use the run value
        let prediction = runValue
        
        // Compute prediction error
        var error = interruptionValue - prediction
        
        // Apply modular reduction if near-lossless
        let range = parameters.maxValue + 1
        if error > (range - 1) / 2 {
            error -= range
        } else if error < -(range / 2) {
            error += range
        }
        
        // Map to non-negative for Golomb coding
        let mappedError = mapErrorToNonNegative(error)
        
        return EncodedRunInterruption(
            interruptionValue: interruptionValue,
            prediction: prediction,
            error: error,
            mappedError: mappedError
        )
    }
    
    /// Map prediction error to non-negative value for Golomb coding.
    ///
    /// Per ITU-T.87 Section 4.4.1:
    /// - If Errval >= 0: MErrval = 2 × Errval
    /// - If Errval < 0: MErrval = -2 × Errval - 1
    ///
    /// - Parameter error: Signed prediction error
    /// - Returns: Mapped non-negative error value
    private func mapErrorToNonNegative(_ error: Int) -> Int {
        if error >= 0 {
            return 2 * error
        } else {
            return -2 * error - 1
        }
    }
    
    // MARK: - Context Adaptation
    
    /// Update run index based on completed run length.
    ///
    /// Per ITU-T.87 Section 4.5.3, the run index adapts based on:
    /// - Longer runs → increase RUNindex (up to maximum of 31)
    /// - Shorter runs → decrease RUNindex (down to minimum of 0)
    ///
    /// This adaptation allows the encoder to efficiently handle varying
    /// run length patterns in different image regions.
    ///
    /// - Parameters:
    ///   - currentRunIndex: Current run index before adaptation
    ///   - completedRunLength: Length of the just-completed run
    /// - Returns: Updated run index
    public func adaptRunIndex(
        currentRunIndex: Int,
        completedRunLength: Int
    ) -> Int {
        // Already at maximum, can't increase
        if currentRunIndex >= 31 {
            return 31
        }
        
        // Already at minimum, can't decrease
        if currentRunIndex <= 0 {
            return 0
        }
        
        let j = computeJ(runIndex: currentRunIndex)
        let blockSize = 1 << j  // 2^J
        
        var newRunIndex = currentRunIndex
        
        // Increase index if run was long
        if completedRunLength > blockSize {
            newRunIndex = min(currentRunIndex + 1, 31)
        }
        // Decrease index if run was short
        else if j > 0 && completedRunLength < (1 << (j - 1)) {
            newRunIndex = max(currentRunIndex - 1, 0)
        }
        
        return newRunIndex
    }
    
    // MARK: - Run Limit Handling
    
    /// Check if run length exceeds the maximum limit.
    ///
    /// Long runs may need to be split into multiple encoded segments
    /// to prevent excessive buffer lookahead or encoding complexity.
    ///
    /// - Parameter runLength: Detected run length
    /// - Returns: True if run should be split
    public func shouldSplitRun(runLength: Int) -> Bool {
        return runLength > maxRunLength
    }
    
    /// Split a long run into encodable chunks.
    ///
    /// When a run exceeds the maximum length, it's split into multiple
    /// segments that can be encoded separately.
    ///
    /// - Parameter runLength: Total run length to split
    /// - Returns: Array of chunk sizes
    public func splitRunLength(runLength: Int) -> [Int] {
        var chunks: [Int] = []
        var remaining = runLength
        
        while remaining > 0 {
            let chunkSize = min(remaining, maxRunLength)
            chunks.append(chunkSize)
            remaining -= chunkSize
        }
        
        return chunks
    }
}

// MARK: - Encoded Run Result

/// Result of encoding a run of identical pixels.
///
/// Contains the encoded bit sequences and metadata for bitstream writing.
public struct EncodedRun: Sendable {
    /// Run index used for encoding (determines J value)
    public let runIndex: Int
    
    /// J value (number of bits for remainder encoding)
    public let j: Int
    
    /// Number of '1' continuation bits (each represents 2^J pixels)
    public let continuationBits: Int
    
    /// Remainder value to encode in J bits
    public let remainder: Int
    
    /// Total run length encoded
    public let totalRunLength: Int
    
    /// Total number of bits required for encoding
    public var totalBitLength: Int {
        // continuationBits '1's + one '0' + J bits for remainder
        return continuationBits + 1 + j
    }
}

// MARK: - Encoded Run Interruption Result

/// Result of encoding a run interruption sample.
///
/// When a run is interrupted, the differing pixel is encoded with
/// its prediction error using a special context.
public struct EncodedRunInterruption: Sendable {
    /// Actual pixel value that interrupted the run
    public let interruptionValue: Int
    
    /// Predicted value (typically the run value)
    public let prediction: Int
    
    /// Signed prediction error
    public let error: Int
    
    /// Mapped non-negative error (MErrval)
    public let mappedError: Int
}
