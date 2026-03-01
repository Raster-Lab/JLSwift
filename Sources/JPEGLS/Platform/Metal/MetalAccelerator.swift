/// Metal GPU-based acceleration for JPEG-LS operations.
///
/// This implementation leverages Apple's Metal framework to perform GPU-accelerated
/// encoding operations for large images. Metal compute shaders provide massive
/// parallelism for pixel-level operations, making them ideal for processing large
/// medical images and high-resolution data.
///
/// **Note**: This file is conditionally compiled only on Apple platforms where
/// Metal is available (macOS 10.13+, iOS 11+).
///
/// **Architecture**:
/// - GPU is used for batch operations on large image tiles
/// - CPU fallback is used for small images where GPU overhead exceeds benefits
/// - Automatic workload distribution between GPU and CPU based on image size
/// - Efficient memory transfer using shared Metal buffers

#if canImport(Metal)

import Foundation
import Metal

/// Metal GPU-accelerated implementation for JPEG-LS operations.
///
/// Provides GPU-accelerated batch gradient computation, prediction, colour space
/// transformation, and context operations optimised for large images on Apple
/// platforms with Metal support.
///
/// The implementation uses Metal compute shaders to process multiple pixels
/// in parallel on the GPU, significantly improving performance for large images
/// while falling back to CPU for small images where GPU overhead is not justified.
public final class MetalAccelerator: @unchecked Sendable {
    public static let platformName = "Metal"
    
    /// The Metal device used for GPU operations.
    private let device: MTLDevice
    
    /// The command queue for submitting GPU work.
    private let commandQueue: MTLCommandQueue
    
    /// The compute pipeline state for gradient computation.
    private let gradientPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for MED prediction.
    private let predictionPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for gradient quantisation.
    private let quantizeGradientsPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP1 forward colour transform.
    private let colourTransformHP1ForwardPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP1 inverse colour transform.
    private let colourTransformHP1InversePipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP2 forward colour transform.
    private let colourTransformHP2ForwardPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP2 inverse colour transform.
    private let colourTransformHP2InversePipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP3 forward colour transform.
    private let colourTransformHP3ForwardPipelineState: MTLComputePipelineState
    
    /// The compute pipeline state for HP3 inverse colour transform.
    private let colourTransformHP3InversePipelineState: MTLComputePipelineState
    
    /// Minimum number of pixels to use GPU (below this, use CPU fallback).
    /// This threshold is determined empirically based on GPU overhead vs. benefit.
    public static let gpuThreshold = 1024
    
    /// Returns true if Metal is available on this device.
    public static var isSupported: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    /// Initialize a Metal GPU accelerator.
    ///
    /// - Throws: `MetalAcceleratorError` if Metal initialization fails
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalAcceleratorError.metalNotAvailable
        }
        
        guard let queue = device.makeCommandQueue() else {
            throw MetalAcceleratorError.commandQueueCreationFailed
        }
        
        self.device = device
        self.commandQueue = queue
        
        // Create compute pipeline states for all shaders
        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            
            self.gradientPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_gradients")
            self.predictionPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_med_prediction")
            self.quantizeGradientsPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_quantize_gradients")
            self.colourTransformHP1ForwardPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp1_forward")
            self.colourTransformHP1InversePipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp1_inverse")
            self.colourTransformHP2ForwardPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp2_forward")
            self.colourTransformHP2InversePipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp2_inverse")
            self.colourTransformHP3ForwardPipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp3_forward")
            self.colourTransformHP3InversePipelineState = try Self.makePipelineState(
                library: library, device: device, functionName: "compute_colour_transform_hp3_inverse")
            
        } catch let e as MetalAcceleratorError {
            throw e
        } catch {
            throw MetalAcceleratorError.pipelineCreationFailed(error)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Create a compute pipeline state for the named shader function.
    private static func makePipelineState(
        library: MTLLibrary,
        device: MTLDevice,
        functionName: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: functionName) else {
            throw MetalAcceleratorError.shaderFunctionNotFound(functionName)
        }
        return try device.makeComputePipelineState(function: function)
    }
    
    /// Execute a 1-D compute dispatch and wait for completion.
    ///
    /// - Parameters:
    ///   - pipelineState: The compute pipeline state to use.
    ///   - count: Number of elements (threads) to dispatch.
    ///   - configure: Closure that sets buffers/bytes on the encoder before dispatch.
    /// - Throws: `MetalAcceleratorError` if the command buffer fails.
    private func dispatch1D(
        pipelineState: MTLComputePipelineState,
        count: Int,
        configure: (MTLComputeCommandEncoder) -> Void
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalAcceleratorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(pipelineState)
        configure(encoder)
        
        let threadGroupWidth = min(pipelineState.maxTotalThreadsPerThreadgroup, count)
        let threadGroupSize  = MTLSize(width: threadGroupWidth, height: 1, depth: 1)
        let threadGroups     = MTLSize(
            width: (count + threadGroupWidth - 1) / threadGroupWidth,
            height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if commandBuffer.status == .error {
            throw MetalAcceleratorError.commandBufferExecutionFailed
        }
    }
    
    /// Create a read-only Metal buffer from a Swift array.
    private func makeReadBuffer<T>(_ array: [T]) throws -> MTLBuffer {
        let size = array.count * MemoryLayout<T>.stride
        guard let buf = device.makeBuffer(bytes: array, length: size, options: .storageModeShared) else {
            throw MetalAcceleratorError.bufferCreationFailed
        }
        return buf
    }
    
    /// Create a write-only Metal buffer of the given element count.
    private func makeWriteBuffer<T>(count: Int, type: T.Type) throws -> MTLBuffer {
        let size = count * MemoryLayout<T>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            throw MetalAcceleratorError.bufferCreationFailed
        }
        return buf
    }
    
    /// Read the contents of a Metal buffer as a Swift array.
    private func readBuffer<T>(_ buffer: MTLBuffer, count: Int, type: T.Type) -> [T] {
        let pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    // MARK: - Batch Gradient Computation
    
    /// Compute gradients for a batch of pixels using Metal GPU.
    ///
    /// This function dispatches compute shaders to the GPU to compute gradients
    /// for multiple pixels in parallel. For small batches (< gpuThreshold pixels),
    /// falls back to CPU computation to avoid GPU overhead.
    ///
    /// For each pixel position i:
    /// - D1[i] = b[i] - c[i] (horizontal gradient)
    /// - D2[i] = a[i] - c[i] (vertical gradient)
    /// - D3[i] = c[i] - a[i] (diagonal gradient)
    ///
    /// - Parameters:
    ///   - a: Array of north pixel values
    ///   - b: Array of west pixel values
    ///   - c: Array of northwest pixel values
    /// - Returns: A tuple of three arrays containing the computed gradients (d1, d2, d3)
    /// - Throws: `MetalAcceleratorError` if GPU operations fail
    /// - Precondition: All arrays must have the same length
    public func computeGradientsBatch(
        a: [Int32],
        b: [Int32],
        c: [Int32]
    ) throws -> (d1: [Int32], d2: [Int32], d3: [Int32]) {
        precondition(a.count == b.count && b.count == c.count, "Arrays must have same length")
        
        let count = a.count
        guard count > 0 else {
            return ([], [], [])
        }
        
        // Use CPU fallback for small batches
        if count < Self.gpuThreshold {
            return computeGradientsBatchCPU(a: a, b: b, c: c)
        }
        
        let aBuffer  = try makeReadBuffer(a)
        let bBuffer  = try makeReadBuffer(b)
        let cBuffer  = try makeReadBuffer(c)
        let d1Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        let d2Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        let d3Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        
        var elementCount = UInt32(count)
        try dispatch1D(pipelineState: gradientPipelineState, count: count) { encoder in
            encoder.setBuffer(aBuffer,  offset: 0, index: 0)
            encoder.setBuffer(bBuffer,  offset: 0, index: 1)
            encoder.setBuffer(cBuffer,  offset: 0, index: 2)
            encoder.setBuffer(d1Buffer, offset: 0, index: 3)
            encoder.setBuffer(d2Buffer, offset: 0, index: 4)
            encoder.setBuffer(d3Buffer, offset: 0, index: 5)
            encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 6)
        }
        
        return (
            readBuffer(d1Buffer, count: count, type: Int32.self),
            readBuffer(d2Buffer, count: count, type: Int32.self),
            readBuffer(d3Buffer, count: count, type: Int32.self)
        )
    }
    
    // MARK: - Batch MED Prediction
    
    /// Compute MED predictions for a batch of pixels using Metal GPU.
    ///
    /// This function dispatches compute shaders to the GPU to compute MED
    /// predictions for multiple pixels in parallel. Falls back to CPU for
    /// small batches.
    ///
    /// - Parameters:
    ///   - a: Array of north pixel values
    ///   - b: Array of west pixel values
    ///   - c: Array of northwest pixel values
    /// - Returns: Array of predicted pixel values
    /// - Throws: `MetalAcceleratorError` if GPU operations fail
    /// - Precondition: All arrays must have the same length
    public func computeMEDPredictionBatch(
        a: [Int32],
        b: [Int32],
        c: [Int32]
    ) throws -> [Int32] {
        precondition(a.count == b.count && b.count == c.count, "Arrays must have same length")
        
        let count = a.count
        guard count > 0 else {
            return []
        }
        
        // Use CPU fallback for small batches
        if count < Self.gpuThreshold {
            return computeMEDPredictionBatchCPU(a: a, b: b, c: c)
        }
        
        let aBuffer    = try makeReadBuffer(a)
        let bBuffer    = try makeReadBuffer(b)
        let cBuffer    = try makeReadBuffer(c)
        let predBuffer = try makeWriteBuffer(count: count, type: Int32.self)
        
        var elementCount = UInt32(count)
        try dispatch1D(pipelineState: predictionPipelineState, count: count) { encoder in
            encoder.setBuffer(aBuffer,    offset: 0, index: 0)
            encoder.setBuffer(bBuffer,    offset: 0, index: 1)
            encoder.setBuffer(cBuffer,    offset: 0, index: 2)
            encoder.setBuffer(predBuffer, offset: 0, index: 3)
            encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 4)
        }
        
        return readBuffer(predBuffer, count: count, type: Int32.self)
    }
    
    // MARK: - Batch Gradient Quantisation
    
    /// Quantise a batch of gradients to context indices using Metal GPU.
    ///
    /// Maps each gradient to a context index in the range [-4, 4] using the
    /// JPEG-LS threshold parameters T1, T2, T3. Falls back to CPU for small batches.
    ///
    /// - Parameters:
    ///   - d1: First gradient array (horizontal)
    ///   - d2: Second gradient array (vertical)
    ///   - d3: Third gradient array (diagonal)
    ///   - t1: Quantisation threshold 1
    ///   - t2: Quantisation threshold 2
    ///   - t3: Quantisation threshold 3
    /// - Returns: A tuple of three arrays containing the quantised gradients (q1, q2, q3)
    /// - Throws: `MetalAcceleratorError` if GPU operations fail
    /// - Precondition: All gradient arrays must have the same length
    public func quantizeGradientsBatch(
        d1: [Int32], d2: [Int32], d3: [Int32],
        t1: Int32, t2: Int32, t3: Int32
    ) throws -> (q1: [Int32], q2: [Int32], q3: [Int32]) {
        precondition(d1.count == d2.count && d2.count == d3.count, "Arrays must have same length")
        
        let count = d1.count
        guard count > 0 else {
            return ([], [], [])
        }
        
        if count < Self.gpuThreshold {
            return quantizeGradientsBatchCPU(d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        }
        
        let d1Buffer = try makeReadBuffer(d1)
        let d2Buffer = try makeReadBuffer(d2)
        let d3Buffer = try makeReadBuffer(d3)
        let q1Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        let q2Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        let q3Buffer = try makeWriteBuffer(count: count, type: Int32.self)
        
        var elementCount = UInt32(count)
        var t1v = t1, t2v = t2, t3v = t3
        try dispatch1D(pipelineState: quantizeGradientsPipelineState, count: count) { encoder in
            encoder.setBuffer(d1Buffer, offset: 0, index: 0)
            encoder.setBuffer(d2Buffer, offset: 0, index: 1)
            encoder.setBuffer(d3Buffer, offset: 0, index: 2)
            encoder.setBuffer(q1Buffer, offset: 0, index: 3)
            encoder.setBuffer(q2Buffer, offset: 0, index: 4)
            encoder.setBuffer(q3Buffer, offset: 0, index: 5)
            encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 6)
            encoder.setBytes(&t1v, length: MemoryLayout<Int32>.size, index: 7)
            encoder.setBytes(&t2v, length: MemoryLayout<Int32>.size, index: 8)
            encoder.setBytes(&t3v, length: MemoryLayout<Int32>.size, index: 9)
        }
        
        return (
            readBuffer(q1Buffer, count: count, type: Int32.self),
            readBuffer(q2Buffer, count: count, type: Int32.self),
            readBuffer(q3Buffer, count: count, type: Int32.self)
        )
    }
    
    // MARK: - Batch Colour Space Transformation
    
    /// Apply a colour space transformation to a batch of RGB pixels using Metal GPU.
    ///
    /// Dispatches the appropriate HP forward transform (HP1, HP2, or HP3) to the GPU.
    /// Falls back to CPU for small batches or when the transform is `.none`.
    ///
    /// - Parameters:
    ///   - transform: The colour transformation to apply
    ///   - r: Red component array
    ///   - g: Green component array
    ///   - b: Blue component array
    /// - Returns: Transformed (r′, g′, b′) components as `Int32` arrays
    /// - Throws: `MetalAcceleratorError` if GPU operations fail
    /// - Precondition: All arrays must have the same length
    public func applyColourTransformForwardBatch(
        transform: JPEGLSColorTransformation,
        r: [Int32], g: [Int32], b: [Int32]
    ) throws -> (r: [Int32], g: [Int32], b: [Int32]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        
        if transform == .none {
            return (r, g, b)
        }
        
        if count < Self.gpuThreshold {
            return applyColourTransformCPU(transform: transform, r: r, g: g, b: b, forward: true)
        }
        
        let pipelineState: MTLComputePipelineState
        switch transform {
        case .hp1:   pipelineState = colourTransformHP1ForwardPipelineState
        case .hp2:   pipelineState = colourTransformHP2ForwardPipelineState
        case .hp3:   pipelineState = colourTransformHP3ForwardPipelineState
        case .none:  return (r, g, b)  // unreachable — handled above
        }
        
        return try dispatchColourTransform(
            pipelineState: pipelineState, count: count, r: r, g: g, b: b)
    }
    
    /// Apply the inverse colour space transformation to a batch of pixels using Metal GPU.
    ///
    /// Dispatches the appropriate HP inverse transform (HP1, HP2, or HP3) to the GPU.
    /// Falls back to CPU for small batches or when the transform is `.none`.
    ///
    /// - Parameters:
    ///   - transform: The colour transformation to invert
    ///   - r: Transformed red component array (R′)
    ///   - g: Transformed green component array (G′)
    ///   - b: Transformed blue component array (B′)
    /// - Returns: Recovered (r, g, b) components as `Int32` arrays
    /// - Throws: `MetalAcceleratorError` if GPU operations fail
    /// - Precondition: All arrays must have the same length
    public func applyColourTransformInverseBatch(
        transform: JPEGLSColorTransformation,
        r: [Int32], g: [Int32], b: [Int32]
    ) throws -> (r: [Int32], g: [Int32], b: [Int32]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        
        if transform == .none {
            return (r, g, b)
        }
        
        if count < Self.gpuThreshold {
            return applyColourTransformCPU(transform: transform, r: r, g: g, b: b, forward: false)
        }
        
        let pipelineState: MTLComputePipelineState
        switch transform {
        case .hp1:   pipelineState = colourTransformHP1InversePipelineState
        case .hp2:   pipelineState = colourTransformHP2InversePipelineState
        case .hp3:   pipelineState = colourTransformHP3InversePipelineState
        case .none:  return (r, g, b)  // unreachable — handled above
        }
        
        return try dispatchColourTransform(
            pipelineState: pipelineState, count: count, r: r, g: g, b: b)
    }
    
    /// Dispatch a colour transform shader (forward or inverse) and return the result.
    private func dispatchColourTransform(
        pipelineState: MTLComputePipelineState,
        count: Int,
        r: [Int32], g: [Int32], b: [Int32]
    ) throws -> (r: [Int32], g: [Int32], b: [Int32]) {
        let rInBuffer  = try makeReadBuffer(r)
        let gInBuffer  = try makeReadBuffer(g)
        let bInBuffer  = try makeReadBuffer(b)
        let rOutBuffer = try makeWriteBuffer(count: count, type: Int32.self)
        let gOutBuffer = try makeWriteBuffer(count: count, type: Int32.self)
        let bOutBuffer = try makeWriteBuffer(count: count, type: Int32.self)
        
        var elementCount = UInt32(count)
        try dispatch1D(pipelineState: pipelineState, count: count) { encoder in
            encoder.setBuffer(rInBuffer,  offset: 0, index: 0)
            encoder.setBuffer(gInBuffer,  offset: 0, index: 1)
            encoder.setBuffer(bInBuffer,  offset: 0, index: 2)
            encoder.setBuffer(rOutBuffer, offset: 0, index: 3)
            encoder.setBuffer(gOutBuffer, offset: 0, index: 4)
            encoder.setBuffer(bOutBuffer, offset: 0, index: 5)
            encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 6)
        }
        
        return (
            readBuffer(rOutBuffer, count: count, type: Int32.self),
            readBuffer(gOutBuffer, count: count, type: Int32.self),
            readBuffer(bOutBuffer, count: count, type: Int32.self)
        )
    }
    
    // MARK: - CPU Fallback Implementations
    
    /// CPU fallback for gradient computation (used for small batches).
    private func computeGradientsBatchCPU(
        a: [Int32],
        b: [Int32],
        c: [Int32]
    ) -> (d1: [Int32], d2: [Int32], d3: [Int32]) {
        let count = a.count
        var d1 = [Int32](repeating: 0, count: count)
        var d2 = [Int32](repeating: 0, count: count)
        var d3 = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            d1[i] = b[i] - c[i]  // horizontal gradient
            d2[i] = a[i] - c[i]  // vertical gradient
            d3[i] = c[i] - a[i]  // diagonal gradient
        }
        
        return (d1, d2, d3)
    }
    
    /// CPU fallback for MED prediction (used for small batches).
    private func computeMEDPredictionBatchCPU(
        a: [Int32],
        b: [Int32],
        c: [Int32]
    ) -> [Int32] {
        let count = a.count
        var predictions = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            let av = a[i]
            let bv = b[i]
            let cv = c[i]
            
            let minAB = min(av, bv)
            let maxAB = max(av, bv)
            
            if cv >= maxAB {
                predictions[i] = minAB
            } else if cv <= minAB {
                predictions[i] = maxAB
            } else {
                predictions[i] = av + bv - cv
            }
        }
        
        return predictions
    }
    
    /// CPU fallback for gradient quantisation (used for small batches).
    private func quantizeGradientsBatchCPU(
        d1: [Int32], d2: [Int32], d3: [Int32],
        t1: Int32, t2: Int32, t3: Int32
    ) -> (q1: [Int32], q2: [Int32], q3: [Int32]) {
        func quantise(_ d: Int32) -> Int32 {
            if d <= -t3 { return -4 }
            if d <= -t2 { return -3 }
            if d <= -t1 { return -2 }
            if d < 0    { return -1 }
            if d == 0   { return  0 }
            if d < t1   { return  1 }
            if d < t2   { return  2 }
            if d < t3   { return  3 }
            return 4
        }
        let count = d1.count
        var q1 = [Int32](repeating: 0, count: count)
        var q2 = [Int32](repeating: 0, count: count)
        var q3 = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            q1[i] = quantise(d1[i])
            q2[i] = quantise(d2[i])
            q3[i] = quantise(d3[i])
        }
        return (q1, q2, q3)
    }
    
    /// CPU fallback for colour space transformation.
    private func applyColourTransformCPU(
        transform: JPEGLSColorTransformation,
        r: [Int32], g: [Int32], b: [Int32],
        forward: Bool
    ) -> (r: [Int32], g: [Int32], b: [Int32]) {
        let count = r.count
        var outR = [Int32](repeating: 0, count: count)
        var outG = [Int32](repeating: 0, count: count)
        var outB = [Int32](repeating: 0, count: count)
        
        for i in 0..<count {
            let rv = Int(r[i]), gv = Int(g[i]), bv = Int(b[i])
            let result: [Int]
            if forward {
                result = (try? transform.transformForward([rv, gv, bv])) ?? [rv, gv, bv]
            } else {
                result = (try? transform.transformInverse([rv, gv, bv])) ?? [rv, gv, bv]
            }
            outR[i] = Int32(result[0])
            outG[i] = Int32(result[1])
            outB[i] = Int32(result[2])
        }
        return (outR, outG, outB)
    }
}

// MARK: - Error Types

/// Errors that can occur during Metal GPU acceleration.
public enum MetalAcceleratorError: Error, CustomStringConvertible {
    /// Metal is not available on this device.
    case metalNotAvailable
    
    /// Failed to create Metal command queue.
    case commandQueueCreationFailed
    
    /// Failed to find shader function.
    case shaderFunctionNotFound(String)
    
    /// Failed to create compute pipeline state.
    case pipelineCreationFailed(Error)
    
    /// Failed to create Metal buffer.
    case bufferCreationFailed
    
    /// Failed to create command buffer.
    case commandBufferCreationFailed
    
    /// Command buffer execution failed.
    case commandBufferExecutionFailed
    
    public var description: String {
        switch self {
        case .metalNotAvailable:
            return "Metal is not available on this device"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        case .shaderFunctionNotFound(let name):
            return "Shader function '\(name)' not found in Metal library"
        case .pipelineCreationFailed(let error):
            return "Failed to create compute pipeline state: \(error)"
        case .bufferCreationFailed:
            return "Failed to create Metal buffer"
        case .commandBufferCreationFailed:
            return "Failed to create command buffer"
        case .commandBufferExecutionFailed:
            return "Command buffer execution failed"
        }
    }
}

#endif // canImport(Metal)
