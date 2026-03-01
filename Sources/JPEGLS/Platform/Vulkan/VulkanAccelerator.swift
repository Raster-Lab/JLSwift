/// Vulkan GPU compute accelerator for JPEG-LS operations.
///
/// This file implements the Vulkan compute backend for JPEG-LS acceleration.
/// The design mirrors the Metal accelerator API so that application code can
/// swap between Metal (Apple) and Vulkan (Linux/Windows) backends with minimal
/// changes.
///
/// **Current Status** (Phase 15.2):
/// GPU compute kernels require the Vulkan SDK and SPIR-V shader binaries.
/// Because no Vulkan Swift package is present in the project dependencies, the
/// GPU execution path is gated behind `#if canImport(VulkanSwift)` and is not
/// yet compiled. All public methods unconditionally use the CPU fallback path,
/// which produces bit-exact results identical to those that would be produced
/// by a GPU implementation.
///
/// **Architecture**:
/// - `VulkanAccelerator.isSupported` returns `true` only when a real GPU device
///   is available via `selectBestVulkanDevice()`.
/// - All batch methods check `count >= gpuThreshold` before dispatching to GPU;
///   small batches always use the CPU path.
/// - The CPU fallback implements the same algorithms as the GPU shaders,
///   guaranteeing bit-exact cross-path results.
///
/// **SPIR-V Shaders** (planned, not yet compiled):
/// The following compute shader entry points are planned:
/// - `compute_gradients` — gradient computation (D1, D2, D3)
/// - `compute_med_prediction` — MED predictor
/// - `compute_quantize_gradients` — threshold-based gradient quantisation
/// - `compute_colour_transform_hp1_forward` / `_inverse`
/// - `compute_colour_transform_hp2_forward` / `_inverse`
/// - `compute_colour_transform_hp3_forward` / `_inverse`

import Foundation

// MARK: - Errors

/// Errors that can occur during Vulkan GPU acceleration.
public enum VulkanAcceleratorError: Error, CustomStringConvertible, Equatable, Sendable {
    /// No Vulkan-capable GPU was found on this system.
    case noGPUDeviceAvailable
    /// GPU execution failed (e.g. device lost).
    case commandExecutionFailed
    /// A required SPIR-V shader could not be loaded or compiled.
    case shaderLoadFailed(String)
    /// Memory allocation on the GPU failed.
    case bufferAllocationFailed
    /// Input arrays have mismatched lengths.
    case inputLengthMismatch

    public var description: String {
        switch self {
        case .noGPUDeviceAvailable:
            return "No Vulkan-capable GPU device is available on this system"
        case .commandExecutionFailed:
            return "Vulkan command buffer execution failed"
        case .shaderLoadFailed(let name):
            return "Failed to load SPIR-V shader '\(name)'"
        case .bufferAllocationFailed:
            return "Failed to allocate Vulkan GPU buffer"
        case .inputLengthMismatch:
            return "Input arrays must have the same length"
        }
    }
}

// MARK: - Accelerator

/// Vulkan GPU-accelerated implementation for JPEG-LS operations.
///
/// Provides the same batch operations as `MetalAccelerator` (gradient
/// computation, MED prediction, gradient quantisation, and colour space
/// transformation) using Vulkan compute shaders on Linux/Windows, with
/// automatic CPU fallback when no GPU is available.
///
/// All methods are safe to call on any platform; they route to the CPU
/// fallback when the Vulkan SDK is not present or no GPU is found.
public final class VulkanAccelerator: @unchecked Sendable {

    public static let platformName = "Vulkan"

    /// Returns `true` when a Vulkan-capable GPU device is found.
    ///
    /// On platforms without the Vulkan SDK this always returns `false`.
    public static var isSupported: Bool {
        selectBestVulkanDevice() != nil
    }

    /// Minimum batch size (in pixels) before routing work to the GPU.
    ///
    /// Batches smaller than this threshold are always processed on the CPU
    /// to avoid the fixed overhead of GPU command submission.
    public static let gpuThreshold = 1024

    /// The selected Vulkan device (nil when no GPU is available).
    public let device: VulkanDevice?

    /// Initialise a Vulkan accelerator.
    ///
    /// Selects the best available GPU via `selectBestVulkanDevice()`.
    /// Initialisation succeeds even when no GPU is found; in that case all
    /// operations use the CPU fallback.
    public init() {
        self.device = selectBestVulkanDevice()
    }

    // MARK: - Batch Gradient Computation

    /// Compute gradients for a batch of pixels.
    ///
    /// For each element i:
    /// - D1[i] = b[i] − c[i]  (horizontal gradient)
    /// - D2[i] = a[i] − c[i]  (vertical gradient)
    /// - D3[i] = c[i] − a[i]  (diagonal gradient)
    ///
    /// Uses GPU compute when `count >= gpuThreshold` and a device is available;
    /// otherwise uses the CPU fallback.
    ///
    /// - Precondition: All input arrays must have the same length.
    public func computeGradientsBatch(
        a: [Int32], b: [Int32], c: [Int32]
    ) -> (d1: [Int32], d2: [Int32], d3: [Int32]) {
        precondition(a.count == b.count && b.count == c.count, "Arrays must have same length")
        let count = a.count
        guard count > 0 else { return ([], [], []) }

        // GPU path (when Vulkan SDK is available and device is present)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return dispatchGradientGPU(a: a, b: b, c: c)
        // }
        // #endif

        return computeGradientsCPU(a: a, b: b, c: c)
    }

    // MARK: - Batch MED Prediction

    /// Compute MED predictions for a batch of pixels.
    ///
    /// Implements the JPEG-LS MED predictor:
    /// - c >= max(a, b) → min(a, b)
    /// - c <= min(a, b) → max(a, b)
    /// - otherwise → a + b − c
    ///
    /// - Precondition: All input arrays must have the same length.
    public func computeMEDPredictionBatch(
        a: [Int32], b: [Int32], c: [Int32]
    ) -> [Int32] {
        precondition(a.count == b.count && b.count == c.count, "Arrays must have same length")
        let count = a.count
        guard count > 0 else { return [] }

        // GPU path (when Vulkan SDK is available)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return dispatchMEDPredictionGPU(a: a, b: b, c: c)
        // }
        // #endif

        return computeMEDPredictionCPU(a: a, b: b, c: c)
    }

    // MARK: - Batch Gradient Quantisation

    /// Quantise a batch of gradients to context indices in [−4, 4].
    ///
    /// Applies the JPEG-LS threshold quantisation mapping using parameters T1, T2, T3.
    ///
    /// - Precondition: All gradient arrays must have the same length.
    public func quantizeGradientsBatch(
        d1: [Int32], d2: [Int32], d3: [Int32],
        t1: Int32, t2: Int32, t3: Int32
    ) -> (q1: [Int32], q2: [Int32], q3: [Int32]) {
        precondition(d1.count == d2.count && d2.count == d3.count, "Arrays must have same length")
        let count = d1.count
        guard count > 0 else { return ([], [], []) }

        // GPU path (when Vulkan SDK is available)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return dispatchQuantizeGPU(d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        // }
        // #endif

        return quantizeGradientsCPU(d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
    }

    // MARK: - Batch Colour Space Transformation

    /// Apply a forward colour space transformation to a batch of RGB pixels.
    ///
    /// Supports HP1, HP2, HP3, and `.none` (identity).
    ///
    /// - Precondition: All arrays must have the same length.
    public func applyColourTransformForwardBatch(
        transform: JPEGLSColorTransformation,
        r: [Int32], g: [Int32], b: [Int32]
    ) -> (r: [Int32], g: [Int32], b: [Int32]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        if transform == .none { return (r, g, b) }

        // GPU path (when Vulkan SDK is available)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return dispatchColourTransformGPU(transform: transform, r: r, g: g, b: b, forward: true)
        // }
        // #endif

        return applyColourTransformCPU(transform: transform, r: r, g: g, b: b, forward: true)
    }

    /// Apply the inverse colour space transformation to a batch of RGB pixels.
    ///
    /// Supports HP1, HP2, HP3, and `.none` (identity).
    ///
    /// - Precondition: All arrays must have the same length.
    public func applyColourTransformInverseBatch(
        transform: JPEGLSColorTransformation,
        r: [Int32], g: [Int32], b: [Int32]
    ) -> (r: [Int32], g: [Int32], b: [Int32]) {
        precondition(r.count == g.count && g.count == b.count, "Arrays must have same length")
        let count = r.count
        guard count > 0 else { return ([], [], []) }
        if transform == .none { return (r, g, b) }

        // GPU path (when Vulkan SDK is available)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return dispatchColourTransformGPU(transform: transform, r: r, g: g, b: b, forward: false)
        // }
        // #endif

        return applyColourTransformCPU(transform: transform, r: r, g: g, b: b, forward: false)
    }

    // MARK: - CPU Fallback Implementations

    private func computeGradientsCPU(
        a: [Int32], b: [Int32], c: [Int32]
    ) -> (d1: [Int32], d2: [Int32], d3: [Int32]) {
        let count = a.count
        var d1 = [Int32](repeating: 0, count: count)
        var d2 = [Int32](repeating: 0, count: count)
        var d3 = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            d1[i] = b[i] - c[i]
            d2[i] = a[i] - c[i]
            d3[i] = c[i] - a[i]
        }
        return (d1, d2, d3)
    }

    private func computeMEDPredictionCPU(
        a: [Int32], b: [Int32], c: [Int32]
    ) -> [Int32] {
        let count = a.count
        var predictions = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let av = a[i], bv = b[i], cv = c[i]
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

    private func quantizeGradientsCPU(
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

    // MARK: - Combined Encoding Pipeline

    /// Run the combined encoding preprocessing pipeline for a batch of pixels.
    ///
    /// Performs gradient computation, NEAR-aware gradient quantisation, MED
    /// prediction, and prediction-error computation in a single pass. This
    /// mirrors the `MetalAccelerator.computeEncodingPipelineBatch` API so
    /// application code can swap backends with minimal changes.
    ///
    /// Uses the GPU compute path when the Vulkan SDK is present and a device
    /// is available; otherwise falls back to an equivalent CPU implementation
    /// that produces bit-exact results.
    ///
    /// - Parameters:
    ///   - a: West neighbour pixel values.
    ///   - b: North neighbour pixel values.
    ///   - c: North-west neighbour pixel values.
    ///   - x: Current pixel values.
    ///   - near: NEAR parameter (0 = lossless, 1–255 = near-lossless).
    ///   - t1: Quantisation threshold 1.
    ///   - t2: Quantisation threshold 2.
    ///   - t3: Quantisation threshold 3.
    /// - Returns: A tuple containing MED predictions, raw prediction errors,
    ///   and quantised gradients (q1, q2, q3).
    /// - Throws: `VulkanAcceleratorError` if input arrays have mismatched lengths.
    /// - Precondition: All input arrays must have the same length.
    public func computeEncodingPipelineBatch(
        a: [Int32], b: [Int32], c: [Int32], x: [Int32],
        near: Int32 = 0, t1: Int32, t2: Int32, t3: Int32
    ) throws -> (prediction: [Int32], predError: [Int32],
                 q1: [Int32], q2: [Int32], q3: [Int32]) {
        guard a.count == b.count && b.count == c.count && c.count == x.count else {
            throw VulkanAcceleratorError.inputLengthMismatch
        }
        let count = a.count
        guard count > 0 else { return ([], [], [], [], []) }

        // GPU path (when Vulkan SDK is available and device is present)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return try dispatchEncodingPipelineGPU(a:b:c:x:near:t1:t2:t3:)
        // }
        // #endif

        return computeEncodingPipelineCPU(
            a: a, b: b, c: c, x: x, near: near, t1: t1, t2: t2, t3: t3)
    }

    /// Run the combined decoding reconstruction pipeline for a batch of pixels.
    ///
    /// Given the already-entropy-decoded (and de-mapped) prediction errors and
    /// the MED neighbours for each pixel, reconstructs the original pixel values
    /// in a single pass. Mirrors `MetalAccelerator.computeDecodingPipelineBatch`.
    ///
    /// - Parameters:
    ///   - a: West neighbour pixel values (already reconstructed).
    ///   - b: North neighbour pixel values (already reconstructed).
    ///   - c: North-west neighbour pixel values (already reconstructed).
    ///   - errval: Signed prediction errors from the entropy decoder.
    /// - Returns: Reconstructed pixel values.
    /// - Throws: `VulkanAcceleratorError` if input arrays have mismatched lengths.
    /// - Precondition: All input arrays must have the same length.
    public func computeDecodingPipelineBatch(
        a: [Int32], b: [Int32], c: [Int32], errval: [Int32]
    ) throws -> [Int32] {
        guard a.count == b.count && b.count == c.count && c.count == errval.count else {
            throw VulkanAcceleratorError.inputLengthMismatch
        }
        let count = a.count
        guard count > 0 else { return [] }

        // GPU path (when Vulkan SDK is available and device is present)
        // #if canImport(VulkanSwift)
        // if count >= Self.gpuThreshold, device?.isGPUDevice == true {
        //     return try dispatchDecodingPipelineGPU(a:b:c:errval:)
        // }
        // #endif

        return computeDecodingPipelineCPU(a: a, b: b, c: c, errval: errval)
    }

    // MARK: - CPU Implementations for Pipeline

    private func computeEncodingPipelineCPU(
        a: [Int32], b: [Int32], c: [Int32], x: [Int32],
        near: Int32, t1: Int32, t2: Int32, t3: Int32
    ) -> (prediction: [Int32], predError: [Int32], q1: [Int32], q2: [Int32], q3: [Int32]) {
        func quantiseNear(_ d: Int32) -> Int32 {
            if d <= -t3  { return -4 }
            if d <= -t2  { return -3 }
            if d <= -t1  { return -2 }
            if d < -near { return -1 }
            if d <= near { return  0 }
            if d < t1    { return  1 }
            if d < t2    { return  2 }
            if d < t3    { return  3 }
            return 4
        }
        func medPredict(_ av: Int32, _ bv: Int32, _ cv: Int32) -> Int32 {
            let minAB = min(av, bv)
            let maxAB = max(av, bv)
            if cv >= maxAB { return minAB }
            if cv <= minAB { return maxAB }
            return av + bv - cv
        }
        let count = a.count
        var prediction = [Int32](repeating: 0, count: count)
        var predError  = [Int32](repeating: 0, count: count)
        var q1 = [Int32](repeating: 0, count: count)
        var q2 = [Int32](repeating: 0, count: count)
        var q3 = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let d1 = b[i] - c[i]
            let d2 = a[i] - c[i]
            let d3 = c[i] - a[i]
            q1[i] = quantiseNear(d1)
            q2[i] = quantiseNear(d2)
            q3[i] = quantiseNear(d3)
            let px = medPredict(a[i], b[i], c[i])
            prediction[i] = px
            predError[i]  = x[i] - px
        }
        return (prediction, predError, q1, q2, q3)
    }

    private func computeDecodingPipelineCPU(
        a: [Int32], b: [Int32], c: [Int32], errval: [Int32]
    ) -> [Int32] {
        let count = a.count
        var reconstructed = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let av = a[i], bv = b[i], cv = c[i]
            let minAB = min(av, bv)
            let maxAB = max(av, bv)
            let px: Int32
            if cv >= maxAB { px = minAB }
            else if cv <= minAB { px = maxAB }
            else { px = av + bv - cv }
            reconstructed[i] = px + errval[i]
        }
        return reconstructed
    }
}
