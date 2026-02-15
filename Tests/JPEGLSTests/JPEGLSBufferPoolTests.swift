/// Tests for JPEG-LS buffer pool
import Testing
@testable import JPEGLS

@Suite("JPEG-LS Buffer Pool Tests")
struct JPEGLSBufferPoolTests {
    
    @Test("Buffer pool acquires new buffer")
    func testAcquireNewBuffer() {
        let pool = JPEGLSBufferPool()
        let buffer = pool.acquire(type: .contextArrays, size: 100)
        
        #expect(buffer.count == 100)
        #expect(buffer.allSatisfy { $0 == 0 })
    }
    
    @Test("Buffer pool reuses released buffers")
    func testReuseBuffer() {
        let pool = JPEGLSBufferPool()
        
        // Acquire and release a buffer
        let buffer1 = pool.acquire(type: .contextArrays, size: 100)
        pool.release(buffer1, type: .contextArrays)
        
        // Acquire again - should get from pool
        let buffer2 = pool.acquire(type: .contextArrays, size: 100)
        #expect(buffer2.count == 100)
        
        // Check statistics
        let stats = pool.statistics()
        #expect(stats[.contextArrays] == 0) // Should be checked out
    }
    
    @Test("Buffer pool handles multiple types")
    func testMultipleTypes() {
        let pool = JPEGLSBufferPool()
        
        let contextBuffer = pool.acquire(type: .contextArrays, size: 365)
        let pixelBuffer = pool.acquire(type: .pixelData, size: 1000)
        
        #expect(contextBuffer.count == 365)
        #expect(pixelBuffer.count == 1000)
        
        pool.release(contextBuffer, type: .contextArrays)
        pool.release(pixelBuffer, type: .pixelData)
        
        let stats = pool.statistics()
        #expect(stats[.contextArrays] == 1)
        #expect(stats[.pixelData] == 1)
    }
    
    @Test("Buffer pool respects max pool size")
    func testMaxPoolSize() {
        let pool = JPEGLSBufferPool(maxPoolSize: 2)
        
        // Create and release 3 buffers directly
        let buffer1 = Array(repeating: 0, count: 100)
        let buffer2 = Array(repeating: 0, count: 100)
        let buffer3 = Array(repeating: 0, count: 100)
        
        pool.release(buffer1, type: .contextArrays)
        pool.release(buffer2, type: .contextArrays)
        pool.release(buffer3, type: .contextArrays)
        
        let stats = pool.statistics()
        #expect(stats[.contextArrays] == 2) // Should only keep 2
    }
    
    @Test("Buffer pool clears all buffers")
    func testClear() {
        let pool = JPEGLSBufferPool()
        
        let buffer = pool.acquire(type: .contextArrays, size: 100)
        pool.release(buffer, type: .contextArrays)
        
        pool.clear()
        
        let stats = pool.statistics()
        #expect(stats.isEmpty)
    }
    
    @Test("Buffer pool does not store empty buffers")
    func testEmptyBufferNotStored() {
        let pool = JPEGLSBufferPool()
        
        let emptyBuffer: [Int] = []
        pool.release(emptyBuffer, type: .contextArrays)
        
        let stats = pool.statistics()
        #expect(stats[.contextArrays] == nil)
    }
    
    @Test("Buffer pool handles custom types")
    func testCustomType() {
        let pool = JPEGLSBufferPool()
        let customType = JPEGLSBufferPool.BufferType.custom("testBuffer")
        
        let buffer = pool.acquire(type: customType, size: 50)
        #expect(buffer.count == 50)
        
        pool.release(buffer, type: customType)
        let stats = pool.statistics()
        #expect(stats[customType] == 1)
    }
    
    @Test("Buffer pool cleanup removes expired buffers")
    func testCleanup() async {
        let pool = JPEGLSBufferPool(bufferLifetime: 0.1) // 100ms lifetime
        
        let buffer = pool.acquire(type: .contextArrays, size: 100)
        pool.release(buffer, type: .contextArrays)
        
        // Wait for buffer to expire
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        pool.cleanup()
        
        let stats = pool.statistics()
        #expect(stats[.contextArrays] == nil)
    }
    
    @Test("Shared buffer pool is accessible")
    func testSharedPool() {
        let buffer = sharedBufferPool.acquire(type: .pixelData, size: 100)
        #expect(buffer.count == 100)
        
        sharedBufferPool.release(buffer, type: .pixelData)
        sharedBufferPool.clear() // Clean up for other tests
    }
    
    @Test("Buffer pool handles large allocations")
    func testLargeAllocation() {
        let pool = JPEGLSBufferPool()
        let largeBuffer = pool.acquire(type: .pixelData, size: 1_000_000)
        
        #expect(largeBuffer.count == 1_000_000)
    }
    
    @Test("Buffer pool thread safety")
    func testThreadSafety() async {
        let pool = JPEGLSBufferPool()
        
        // Create multiple concurrent tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let buffer = pool.acquire(type: .pixelData, size: 100)
                    pool.release(buffer, type: .pixelData)
                }
            }
        }
        
        // Should not crash
        #expect(true)
    }
}
