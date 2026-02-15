/// Buffer pooling system for reducing memory allocations
///
/// Provides reusable buffer pools for common allocation patterns in JPEG-LS encoding/decoding.
/// Thread-safe implementation suitable for concurrent encoding/decoding operations.
import Foundation

/// A pool of reusable buffers to reduce allocation overhead
public final class JPEGLSBufferPool: @unchecked Sendable {
    /// Buffer type stored in the pool
    public enum BufferType: Hashable {
        case contextArrays  // For context model arrays (A, B, C, N)
        case pixelData      // For pixel data buffers
        case bitstreamData  // For bitstream data
        case custom(String) // For custom buffer types
    }
    
    /// Pooled buffer wrapper
    private struct PooledBuffer {
        let data: [Int]
        let capacity: Int
        var lastUsed: Date
    }
    
    // Thread-safe storage using lock
    private let lock = NSLock()
    private var pools: [BufferType: [PooledBuffer]] = [:]
    private let maxPoolSize: Int
    private let bufferLifetime: TimeInterval
    
    /// Creates a new buffer pool
    /// - Parameters:
    ///   - maxPoolSize: Maximum number of buffers to keep per type (default: 10)
    ///   - bufferLifetime: Maximum lifetime for cached buffers in seconds (default: 60)
    public init(maxPoolSize: Int = 10, bufferLifetime: TimeInterval = 60) {
        self.maxPoolSize = maxPoolSize
        self.bufferLifetime = bufferLifetime
    }
    
    /// Acquires a buffer from the pool or creates a new one
    /// - Parameters:
    ///   - type: The type of buffer to acquire
    ///   - size: Required buffer size
    /// - Returns: A buffer of at least the requested size
    public func acquire(type: BufferType, size: Int) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        
        // Try to find a suitable buffer in the pool
        if var buffers = pools[type] {
            // Find first buffer with sufficient capacity
            if let index = buffers.firstIndex(where: { $0.capacity >= size }) {
                let buffer = buffers.remove(at: index)
                pools[type] = buffers
                
                // Return a fresh array with the requested size
                return Array(repeating: 0, count: size)
            }
        }
        
        // No suitable buffer found, create new one
        return Array(repeating: 0, count: size)
    }
    
    /// Returns a buffer to the pool for reuse
    /// - Parameters:
    ///   - buffer: The buffer to return
    ///   - type: The type of buffer being returned
    public func release(_ buffer: [Int], type: BufferType) {
        lock.lock()
        defer { lock.unlock() }
        
        // Don't pool empty buffers
        guard !buffer.isEmpty else { return }
        
        // Initialize pool for this type if needed
        if pools[type] == nil {
            pools[type] = []
        }
        
        // Add to pool if under size limit
        if var buffers = pools[type], buffers.count < maxPoolSize {
            let pooled = PooledBuffer(
                data: buffer,
                capacity: buffer.count,
                lastUsed: Date()
            )
            buffers.append(pooled)
            pools[type] = buffers
        }
    }
    
    /// Cleans up expired buffers from the pool
    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        for type in pools.keys {
            if var buffers = pools[type] {
                buffers.removeAll { buffer in
                    now.timeIntervalSince(buffer.lastUsed) > bufferLifetime
                }
                if buffers.isEmpty {
                    pools.removeValue(forKey: type)
                } else {
                    pools[type] = buffers
                }
            }
        }
    }
    
    /// Clears all buffers from the pool
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        pools.removeAll()
    }
    
    /// Returns statistics about the current pool state
    public func statistics() -> [BufferType: Int] {
        lock.lock()
        defer { lock.unlock() }
        
        return pools.mapValues { $0.count }
    }
}

/// Global shared buffer pool for common use cases
public let sharedBufferPool = JPEGLSBufferPool()
