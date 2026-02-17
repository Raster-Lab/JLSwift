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
/// Provides GPU-accelerated batch gradient computation, prediction, and
/// context operations optimized for large images on Apple platforms with Metal support.
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
        
        // Create compute pipeline states for shaders
        do {
            let library = try device.makeDefaultLibrary(bundle: .module)
            
            guard let gradientFunction = library.makeFunction(name: "compute_gradients") else {
                throw MetalAcceleratorError.shaderFunctionNotFound("compute_gradients")
            }
            
            guard let predictionFunction = library.makeFunction(name: "compute_med_prediction") else {
                throw MetalAcceleratorError.shaderFunctionNotFound("compute_med_prediction")
            }
            
            self.gradientPipelineState = try device.makeComputePipelineState(function: gradientFunction)
            self.predictionPipelineState = try device.makeComputePipelineState(function: predictionFunction)
            
        } catch {
            throw MetalAcceleratorError.pipelineCreationFailed(error)
        }
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
        
        // Create Metal buffers for input and output data
        let bufferSize = count * MemoryLayout<Int32>.stride
        
        guard let aBuffer = device.makeBuffer(bytes: a, length: bufferSize, options: .storageModeShared),
              let bBuffer = device.makeBuffer(bytes: b, length: bufferSize, options: .storageModeShared),
              let cBuffer = device.makeBuffer(bytes: c, length: bufferSize, options: .storageModeShared),
              let d1Buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let d2Buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let d3Buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw MetalAcceleratorError.bufferCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalAcceleratorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(gradientPipelineState)
        encoder.setBuffer(aBuffer, offset: 0, index: 0)
        encoder.setBuffer(bBuffer, offset: 0, index: 1)
        encoder.setBuffer(cBuffer, offset: 0, index: 2)
        encoder.setBuffer(d1Buffer, offset: 0, index: 3)
        encoder.setBuffer(d2Buffer, offset: 0, index: 4)
        encoder.setBuffer(d3Buffer, offset: 0, index: 5)
        
        var elementCount = UInt32(count)
        encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 6)
        
        // Calculate thread group sizes
        let threadGroupSize = MTLSize(
            width: min(gradientPipelineState.maxTotalThreadsPerThreadgroup, count),
            height: 1,
            depth: 1
        )
        let threadGroups = MTLSize(
            width: (count + threadGroupSize.width - 1) / threadGroupSize.width,
            height: 1,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Check for errors
        if commandBuffer.status == .error {
            throw MetalAcceleratorError.commandBufferExecutionFailed
        }
        
        // Read results from GPU buffers
        let d1Pointer = d1Buffer.contents().bindMemory(to: Int32.self, capacity: count)
        let d2Pointer = d2Buffer.contents().bindMemory(to: Int32.self, capacity: count)
        let d3Pointer = d3Buffer.contents().bindMemory(to: Int32.self, capacity: count)
        
        let d1 = Array(UnsafeBufferPointer(start: d1Pointer, count: count))
        let d2 = Array(UnsafeBufferPointer(start: d2Pointer, count: count))
        let d3 = Array(UnsafeBufferPointer(start: d3Pointer, count: count))
        
        return (d1, d2, d3)
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
        
        // Create Metal buffers
        let bufferSize = count * MemoryLayout<Int32>.stride
        
        guard let aBuffer = device.makeBuffer(bytes: a, length: bufferSize, options: .storageModeShared),
              let bBuffer = device.makeBuffer(bytes: b, length: bufferSize, options: .storageModeShared),
              let cBuffer = device.makeBuffer(bytes: c, length: bufferSize, options: .storageModeShared),
              let predBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw MetalAcceleratorError.bufferCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalAcceleratorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(predictionPipelineState)
        encoder.setBuffer(aBuffer, offset: 0, index: 0)
        encoder.setBuffer(bBuffer, offset: 0, index: 1)
        encoder.setBuffer(cBuffer, offset: 0, index: 2)
        encoder.setBuffer(predBuffer, offset: 0, index: 3)
        
        var elementCount = UInt32(count)
        encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.size, index: 4)
        
        // Calculate thread group sizes
        let threadGroupSize = MTLSize(
            width: min(predictionPipelineState.maxTotalThreadsPerThreadgroup, count),
            height: 1,
            depth: 1
        )
        let threadGroups = MTLSize(
            width: (count + threadGroupSize.width - 1) / threadGroupSize.width,
            height: 1,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        // Execute and wait for completion
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Check for errors
        if commandBuffer.status == .error {
            throw MetalAcceleratorError.commandBufferExecutionFailed
        }
        
        // Read results
        let predPointer = predBuffer.contents().bindMemory(to: Int32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: predPointer, count: count))
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
