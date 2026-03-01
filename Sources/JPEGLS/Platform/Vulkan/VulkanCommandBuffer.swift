/// Vulkan command buffer recording and submission architecture.
///
/// This file provides CPU-side types that represent Vulkan command recording
/// and submission. When the Vulkan SDK (`VulkanSwift`) is integrated, these
/// types will delegate to the actual Vulkan API calls:
/// `vkBeginCommandBuffer`, `vkCmdBindPipeline`, `vkCmdDispatch`,
/// `vkEndCommandBuffer`, and `vkQueueSubmit`.
///
/// In the current CPU-fallback implementation the recorded commands are
/// stored in a Swift array. This lets the full dispatch path be tested and
/// the command-recording API be stabilised before the GPU execution path
/// is connected to real Vulkan calls.

import Foundation

// MARK: - Compute Command

/// A single recorded Vulkan compute command.
///
/// Each `VulkanComputeCommand` wraps one of the operations a compute
/// command buffer can record: pipeline binding, buffer binding,
/// push-constants upload, or workgroup dispatch.
public struct VulkanComputeCommand: Sendable {

    /// The kind of operation this command represents.
    public enum Operation: Sendable {
        /// Bind a named compute pipeline (shader entry point).
        case bindPipeline(name: String)
        /// Bind a `VulkanBuffer` to a specific descriptor-set binding slot.
        case bindBuffer(buffer: VulkanBuffer, binding: UInt32)
        /// Upload raw bytes to the shader's push-constant range.
        case pushConstants(data: [UInt8])
        /// Dispatch a compute workgroup grid of `(x, y, z)` groups.
        case dispatch(x: UInt32, y: UInt32, z: UInt32)
    }

    /// The operation to execute when this command is submitted.
    public let operation: Operation
}

// MARK: - Command Buffer

/// Records a sequence of Vulkan compute commands for later submission.
///
/// In a real Vulkan integration this type wraps a `VkCommandBuffer` handle.
/// Here it stores recorded commands in an array so that:
/// - The full encode/decode command-recording path can be exercised in tests.
/// - The API is defined before a GPU device is available in the project.
/// - CPU-fallback execution can iterate `recordedCommands` to perform the
///   equivalent work on the CPU.
///
/// - Important: `VulkanCommandBuffer` is marked `@unchecked Sendable` to
///   match the Vulkan command-buffer ownership model: a command buffer is
///   owned by one thread at a time (recording, then submitting). Concurrent
///   access from multiple tasks or threads is not supported and requires
///   external synchronisation.
///
/// ## Recording Pattern
///
/// ```swift
/// let pool = VulkanCommandPool()
/// let cmdBuf = pool.allocate()
/// cmdBuf.begin()
/// cmdBuf.bindPipeline(name: "compute_gradients")
/// cmdBuf.bindBuffer(inputBuf,  binding: 0)
/// cmdBuf.bindBuffer(outputBuf, binding: 1)
/// cmdBuf.dispatch(x: UInt32((pixelCount + 63) / 64))
/// cmdBuf.end()
/// // … submit cmdBuf to a VulkanAccelerator or execute CPU fallback …
/// ```
public final class VulkanCommandBuffer: @unchecked Sendable {

    private var commands: [VulkanComputeCommand] = []

    /// Whether the command buffer is currently open for recording.
    ///
    /// `begin()` sets this to `true`; `end()` sets it to `false`.
    /// Recording methods (`bindPipeline`, `bindBuffer`, `dispatch`, etc.)
    /// are silently ignored when `isRecording` is `false`.
    public private(set) var isRecording = false

    /// All commands recorded between the last `begin()` and the most
    /// recent `end()` call (or recorded so far if `end()` has not been
    /// called yet).
    public var recordedCommands: [VulkanComputeCommand] { commands }

    /// The number of commands recorded in this buffer.
    public var commandCount: Int { commands.count }

    // MARK: Recording API

    /// Open the command buffer for recording, discarding any prior commands.
    ///
    /// Must be called before `bindPipeline`, `bindBuffer`, `pushConstants`,
    /// or `dispatch`.
    public func begin() {
        commands.removeAll()
        isRecording = true
    }

    /// Record a pipeline bind command.
    ///
    /// - Parameter name: Logical name of the compute pipeline (corresponds
    ///   to the shader function name, e.g. `"compute_gradients"`).
    public func bindPipeline(name: String) {
        guard isRecording else { return }
        commands.append(VulkanComputeCommand(operation: .bindPipeline(name: name)))
    }

    /// Record a buffer bind command.
    ///
    /// - Parameters:
    ///   - buffer: The `VulkanBuffer` to bind.
    ///   - binding: Descriptor-set binding index as declared in the GLSL/HLSL shader.
    public func bindBuffer(_ buffer: VulkanBuffer, binding: UInt32) {
        guard isRecording else { return }
        commands.append(VulkanComputeCommand(
            operation: .bindBuffer(buffer: buffer, binding: binding)))
    }

    /// Record a push-constants upload.
    ///
    /// Push constants allow small amounts of data (e.g. scalar parameters
    /// like `NEAR` or threshold values) to be uploaded to the shader without
    /// creating a separate uniform buffer.
    ///
    /// - Parameter data: Raw bytes to push to the shader's push-constant range.
    public func pushConstants(data: [UInt8]) {
        guard isRecording else { return }
        commands.append(VulkanComputeCommand(operation: .pushConstants(data: data)))
    }

    /// Record a compute dispatch.
    ///
    /// Launches `x * y * z` workgroups. Each workgroup processes a fixed
    /// number of elements as declared by the `local_size_*` qualifier in
    /// the GLSL shader.
    ///
    /// - Parameters:
    ///   - x: Number of workgroups in the X dimension.
    ///   - y: Number of workgroups in the Y dimension (default 1).
    ///   - z: Number of workgroups in the Z dimension (default 1).
    public func dispatch(x: UInt32, y: UInt32 = 1, z: UInt32 = 1) {
        guard isRecording else { return }
        commands.append(VulkanComputeCommand(operation: .dispatch(x: x, y: y, z: z)))
    }

    /// Close the command buffer, making it ready for submission.
    ///
    /// After `end()`, `isRecording` is `false` and `recordedCommands`
    /// contains the full command sequence for this recording session.
    public func end() {
        isRecording = false
    }
}

// MARK: - Command Pool

/// Allocates and manages `VulkanCommandBuffer` instances.
///
/// In a real Vulkan integration this type wraps a `VkCommandPool` handle.
/// The pool provides efficient allocation of command buffers from a
/// pre-allocated block of GPU memory, and supports bulk reset to reuse
/// that block for a new frame or dispatch cycle.
///
/// - Important: `VulkanCommandPool` is marked `@unchecked Sendable` to
///   match the Vulkan pool ownership model. Concurrent calls to `allocate()`
///   or `reset()` are not thread-safe; use the pool from a single task or
///   thread, or provide external synchronisation.
///
/// ## Example
///
/// ```swift
/// let pool = VulkanCommandPool()
/// let cmdBuf = pool.allocate()
/// cmdBuf.begin()
/// // … record commands …
/// cmdBuf.end()
/// pool.reset()   // reuse the pool for the next frame
/// ```
public final class VulkanCommandPool: @unchecked Sendable {

    private var buffers: [VulkanCommandBuffer] = []

    /// Allocate a new, empty command buffer from this pool.
    ///
    /// - Returns: A fresh `VulkanCommandBuffer` that is not yet recording.
    ///   Call `begin()` before recording any commands into it.
    public func allocate() -> VulkanCommandBuffer {
        let buffer = VulkanCommandBuffer()
        buffers.append(buffer)
        return buffer
    }

    /// Reset all command buffers allocated from this pool.
    ///
    /// Discards all previously allocated command buffers. After `reset()`,
    /// use `allocate()` to obtain fresh command buffers. In a real Vulkan
    /// implementation this corresponds to `vkResetCommandPool`.
    public func reset() {
        buffers.removeAll()
    }

    /// The number of command buffers currently allocated from this pool.
    public var allocatedCount: Int { buffers.count }
}
