/// Vulkan memory management types for JPEG-LS GPU compute.
///
/// This file provides CPU-side buffer and memory-pool abstractions that
/// mirror the Vulkan memory model. When the Vulkan SDK (`VulkanSwift`) is
/// integrated, these types will wrap `VkBuffer` + `VkDeviceMemory` objects.
/// For now they provide a CPU-backed implementation that ensures the API
/// and data-layout used by `VulkanAccelerator` are correct for future GPU
/// integration and that all data paths can be exercised in tests today.

import Foundation

// MARK: - Buffer Usage Flags

/// Flags indicating the intended usage of a Vulkan buffer.
///
/// Mirror the `VkBufferUsageFlags` bitmask from the Vulkan specification.
/// Multiple flags may be combined to describe a buffer used in more than
/// one way (for example, a buffer that acts as both a transfer source and
/// a compute storage buffer).
public struct VulkanBufferUsage: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Buffer used as a storage buffer in compute shaders (`VK_BUFFER_USAGE_STORAGE_BUFFER_BIT`).
    public static let storageBuffer = VulkanBufferUsage(rawValue: 1 << 0)

    /// Buffer used as a uniform buffer (constant data) in shaders (`VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT`).
    public static let uniformBuffer = VulkanBufferUsage(rawValue: 1 << 1)

    /// Buffer acts as the source of a transfer operation (`VK_BUFFER_USAGE_TRANSFER_SRC_BIT`).
    public static let transferSrc   = VulkanBufferUsage(rawValue: 1 << 2)

    /// Buffer acts as the destination of a transfer operation (`VK_BUFFER_USAGE_TRANSFER_DST_BIT`).
    public static let transferDst   = VulkanBufferUsage(rawValue: 1 << 3)
}

// MARK: - VulkanBuffer

/// A CPU-backed representation of a Vulkan buffer allocation.
///
/// On platforms with the Vulkan SDK this type would wrap a `VkBuffer` handle
/// together with its backing `VkDeviceMemory`. In the current CPU-fallback
/// implementation it manages a contiguous `[UInt8]` storage block, ensuring
/// the host-visible data layout matches what a GPU buffer would hold.
///
/// Use `VulkanMemoryPool.allocate(size:usage:)` to create buffers in batch;
/// use `VulkanBuffer.init(size:usage:)` to create standalone buffers.
///
/// - Important: `VulkanBuffer` is marked `@unchecked Sendable` to align with
///   the ownership model used by GPU command-buffer APIs: a buffer is owned
///   by one producer at a time (typically the CPU during host–device transfer,
///   or the GPU during shader execution). Callers must not access a buffer
///   concurrently from multiple Swift tasks without external synchronisation.
public final class VulkanBuffer: @unchecked Sendable {

    /// The size of this buffer in bytes.
    public let size: Int

    /// The intended usage flags for this buffer.
    public let usage: VulkanBufferUsage

    /// CPU-side storage backing this buffer.
    private var storage: [UInt8]

    /// Initialise a new buffer of the given size.
    ///
    /// - Parameters:
    ///   - size: Buffer size in bytes. Must be greater than zero.
    ///   - usage: Intended Vulkan buffer usage flags.
    /// - Throws: `VulkanAcceleratorError.bufferAllocationFailed` if `size` is zero.
    public init(size: Int, usage: VulkanBufferUsage) throws {
        guard size > 0 else { throw VulkanAcceleratorError.bufferAllocationFailed }
        self.size = size
        self.usage = usage
        self.storage = [UInt8](repeating: 0, count: size)
    }

    // MARK: Host-Accessible Data Transfer

    /// Write a typed array into the buffer starting at offset 0.
    ///
    /// This mirrors a host-visible mapped Vulkan buffer write (or a staging
    /// buffer `memcpy`) and is used to transfer data from the CPU to the
    /// (currently simulated) GPU.
    ///
    /// - Parameter array: Elements to write. Their packed byte representation
    ///   must fit within `size` bytes.
    /// - Precondition: `array.count * MemoryLayout<T>.stride <= size`.
    public func write<T>(_ array: [T]) {
        let byteCount = array.count * MemoryLayout<T>.stride
        precondition(byteCount <= size, "Array does not fit in buffer")
        array.withUnsafeBytes { src in
            storage.withUnsafeMutableBytes { dst in
                dst.copyMemory(from: src)
            }
        }
    }

    /// Read typed elements from the buffer starting at offset 0.
    ///
    /// This mirrors a host-visible mapped Vulkan buffer read (or a readback
    /// staging transfer) and is used to transfer results from the (currently
    /// simulated) GPU back to the CPU.
    ///
    /// - Parameters:
    ///   - count: Number of elements to read.
    ///   - type: Element type.
    /// - Returns: Array of `count` elements read from the start of the buffer.
    /// - Precondition: `count * MemoryLayout<T>.stride <= size`.
    public func read<T>(count: Int, type: T.Type) -> [T] {
        let byteCount = count * MemoryLayout<T>.stride
        precondition(byteCount <= size, "Read range exceeds buffer size")
        return storage.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: T.self).prefix(count))
        }
    }
}

// MARK: - VulkanMemoryPool

/// A pool-based allocator for `VulkanBuffer` instances.
///
/// `VulkanMemoryPool` manages a set of `VulkanBuffer` allocations backed by
/// a pre-declared capacity, mirroring the pattern used in Vulkan applications
/// where a large `VkDeviceMemory` block is sub-allocated into individual
/// buffers. This avoids the overhead of a separate `vkAllocateMemory` call
/// for every buffer.
///
/// Call `allocate(size:usage:)` to obtain buffers from the pool, and
/// `reset()` to release all allocations and reclaim the capacity.
///
/// - Important: `VulkanMemoryPool` is marked `@unchecked Sendable` to match
///   the single-owner GPU memory model. The pool must only be accessed from
///   one thread or Swift task at a time; concurrent calls to `allocate()` or
///   `reset()` are not thread-safe and require external synchronisation if
///   used across concurrency boundaries.
///
/// ## Example
/// ```swift
/// let pool = VulkanMemoryPool(maxPoolSize: 64 * 1024 * 1024)  // 64 MB
/// let inputBuf  = try pool.allocate(size: pixels * 4, usage: .transferSrc)
/// let outputBuf = try pool.allocate(size: pixels * 4, usage: .storageBuffer)
/// // … fill inputBuf, dispatch shader, read outputBuf …
/// pool.reset()  // free all allocations for reuse
/// ```
public final class VulkanMemoryPool: @unchecked Sendable {

    /// Maximum total bytes available for allocation from this pool.
    public let maxPoolSize: Int

    /// Total bytes currently allocated from this pool.
    public private(set) var totalAllocated: Int = 0

    private var buffers: [VulkanBuffer] = []

    /// Initialise a memory pool with the given capacity.
    ///
    /// - Parameter maxPoolSize: Maximum total bytes available for allocation.
    public init(maxPoolSize: Int) {
        self.maxPoolSize = maxPoolSize
    }

    /// Allocate a new buffer from the pool.
    ///
    /// - Parameters:
    ///   - size: Required buffer size in bytes.
    ///   - usage: Intended Vulkan buffer usage flags.
    /// - Returns: A new `VulkanBuffer` of the requested size.
    /// - Throws: `VulkanAcceleratorError.bufferAllocationFailed` when the
    ///   remaining pool capacity is insufficient.
    public func allocate(size: Int, usage: VulkanBufferUsage) throws -> VulkanBuffer {
        guard totalAllocated + size <= maxPoolSize else {
            throw VulkanAcceleratorError.bufferAllocationFailed
        }
        let buffer = try VulkanBuffer(size: size, usage: usage)
        buffers.append(buffer)
        totalAllocated += size
        return buffer
    }

    /// Release all allocations and reset the pool to empty.
    ///
    /// After calling `reset()`, `totalAllocated` returns to zero and all
    /// previously returned `VulkanBuffer` objects must be discarded. In a
    /// real Vulkan implementation this corresponds to `vkResetDescriptorPool`
    /// or re-using the backing `VkDeviceMemory` block.
    public func reset() {
        buffers.removeAll()
        totalAllocated = 0
    }

    /// The number of buffers currently alive in this pool.
    public var bufferCount: Int { buffers.count }
}
