/// Tests for Vulkan memory management and command buffer types (Phase 15.2).
///
/// These tests validate the CPU-side Vulkan abstraction types introduced in
/// Milestone 15.2:
/// - `VulkanBuffer`: typed read/write host-accessible buffer
/// - `VulkanMemoryPool`: pool-based buffer allocator
/// - `VulkanCommandBuffer`: command recording and introspection
/// - `VulkanCommandPool`: command buffer lifecycle management

import Testing
@testable import JPEGLS

// MARK: - VulkanBuffer Tests

@Suite("VulkanBuffer Tests")
struct VulkanBufferTests {

    // MARK: Initialization

    @Test("VulkanBuffer initialises with correct size and usage")
    func testInitSizeAndUsage() throws {
        let buf = try VulkanBuffer(size: 1024, usage: .storageBuffer)
        #expect(buf.size == 1024)
        #expect(buf.usage == .storageBuffer)
    }

    @Test("VulkanBuffer throws on zero size")
    func testInitZeroSizeThrows() {
        #expect(throws: (any Error).self) {
            _ = try VulkanBuffer(size: 0, usage: .storageBuffer)
        }
    }

    @Test("VulkanBuffer combined usage flags are preserved")
    func testInitCombinedUsage() throws {
        let usage: VulkanBufferUsage = [.storageBuffer, .transferDst]
        let buf = try VulkanBuffer(size: 256, usage: usage)
        #expect(buf.usage.contains(.storageBuffer))
        #expect(buf.usage.contains(.transferDst))
        #expect(!buf.usage.contains(.uniformBuffer))
    }

    // MARK: Write / Read round-trips

    @Test("VulkanBuffer write+read round-trips Int32 array")
    func testWriteReadInt32() throws {
        let data: [Int32] = [10, 20, 30, 40, 50]
        let buf = try VulkanBuffer(
            size: data.count * MemoryLayout<Int32>.stride, usage: .storageBuffer)
        buf.write(data)
        let result = buf.read(count: data.count, type: Int32.self)
        #expect(result == data)
    }

    @Test("VulkanBuffer write+read round-trips UInt8 array")
    func testWriteReadUInt8() throws {
        let data: [UInt8] = [0, 1, 127, 128, 255]
        let buf = try VulkanBuffer(size: data.count, usage: .transferSrc)
        buf.write(data)
        let result = buf.read(count: data.count, type: UInt8.self)
        #expect(result == data)
    }

    @Test("VulkanBuffer write+read round-trips large Int32 array")
    func testWriteReadLargeArray() throws {
        let count = 65536
        let data = (0..<count).map { Int32($0 % 256) }
        let buf = try VulkanBuffer(
            size: count * MemoryLayout<Int32>.stride, usage: .storageBuffer)
        buf.write(data)
        let result = buf.read(count: count, type: Int32.self)
        #expect(result == data)
    }

    @Test("VulkanBuffer second write overwrites first")
    func testWriteOverwrite() throws {
        let buf = try VulkanBuffer(
            size: 4 * MemoryLayout<Int32>.stride, usage: .storageBuffer)
        buf.write([Int32](repeating: 0, count: 4))
        buf.write([Int32](repeating: 99, count: 4))
        let result = buf.read(count: 4, type: Int32.self)
        #expect(result == [99, 99, 99, 99])
    }
}

// MARK: - VulkanBufferUsage Tests

@Suite("VulkanBufferUsage Tests")
struct VulkanBufferUsageTests {

    @Test("Individual flags have distinct raw values")
    func testDistinctRawValues() {
        let flags: [VulkanBufferUsage] = [
            .storageBuffer, .uniformBuffer, .transferSrc, .transferDst
        ]
        let rawValues = Set(flags.map { $0.rawValue })
        #expect(rawValues.count == flags.count)
    }

    @Test("OptionSet union and intersection work correctly")
    func testOptionSetOperations() {
        let combined: VulkanBufferUsage = [.storageBuffer, .transferSrc]
        #expect(combined.contains(.storageBuffer))
        #expect(combined.contains(.transferSrc))
        #expect(!combined.contains(.uniformBuffer))
        #expect(!combined.contains(.transferDst))
    }
}

// MARK: - VulkanMemoryPool Tests

@Suite("VulkanMemoryPool Tests")
struct VulkanMemoryPoolTests {

    // MARK: Initialization

    @Test("VulkanMemoryPool initialises with correct capacity")
    func testInit() {
        let pool = VulkanMemoryPool(maxPoolSize: 1024 * 1024)
        #expect(pool.maxPoolSize == 1024 * 1024)
        #expect(pool.totalAllocated == 0)
        #expect(pool.bufferCount == 0)
    }

    // MARK: Allocation

    @Test("VulkanMemoryPool allocates buffer and tracks usage")
    func testAllocateSingleBuffer() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 1024)
        let buf = try pool.allocate(size: 256, usage: .storageBuffer)
        #expect(buf.size == 256)
        #expect(pool.totalAllocated == 256)
        #expect(pool.bufferCount == 1)
    }

    @Test("VulkanMemoryPool allocates multiple buffers")
    func testAllocateMultipleBuffers() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 4096)
        _ = try pool.allocate(size: 1024, usage: .storageBuffer)
        _ = try pool.allocate(size: 512,  usage: .uniformBuffer)
        _ = try pool.allocate(size: 256,  usage: .transferSrc)
        #expect(pool.totalAllocated == 1792)
        #expect(pool.bufferCount == 3)
    }

    @Test("VulkanMemoryPool throws when capacity is exceeded")
    func testAllocateExceedsCapacity() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 512)
        _ = try pool.allocate(size: 256, usage: .storageBuffer)
        #expect(throws: (any Error).self) {
            _ = try pool.allocate(size: 512, usage: .storageBuffer)
        }
    }

    @Test("VulkanMemoryPool allows allocations up to exact capacity")
    func testAllocateExactCapacity() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 1024)
        _ = try pool.allocate(size: 512, usage: .storageBuffer)
        _ = try pool.allocate(size: 512, usage: .transferDst)
        #expect(pool.totalAllocated == 1024)
    }

    // MARK: Reset

    @Test("VulkanMemoryPool.reset() returns pool to empty state")
    func testReset() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 2048)
        _ = try pool.allocate(size: 512, usage: .storageBuffer)
        _ = try pool.allocate(size: 512, usage: .transferSrc)
        pool.reset()
        #expect(pool.totalAllocated == 0)
        #expect(pool.bufferCount == 0)
    }

    @Test("VulkanMemoryPool can be reused after reset")
    func testReuseAfterReset() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 512)
        _ = try pool.allocate(size: 512, usage: .storageBuffer)
        pool.reset()
        let buf = try pool.allocate(size: 512, usage: .uniformBuffer)
        #expect(buf.size == 512)
        #expect(pool.totalAllocated == 512)
    }

    // MARK: Data integrity

    @Test("VulkanMemoryPool: allocated buffers hold correct data")
    func testAllocatedBufferDataIntegrity() throws {
        let pool = VulkanMemoryPool(maxPoolSize: 4096)
        let count = 256
        let data: [Int32] = (0..<count).map { Int32($0) }
        let buf = try pool.allocate(
            size: count * MemoryLayout<Int32>.stride, usage: .storageBuffer)
        buf.write(data)
        let result = buf.read(count: count, type: Int32.self)
        #expect(result == data)
    }
}

// MARK: - VulkanCommandBuffer Tests

@Suite("VulkanCommandBuffer Tests")
struct VulkanCommandBufferTests {

    // MARK: Initial state

    @Test("VulkanCommandBuffer starts not recording with no commands")
    func testInitialState() {
        let buf = VulkanCommandBuffer()
        #expect(!buf.isRecording)
        #expect(buf.commandCount == 0)
        #expect(buf.recordedCommands.isEmpty)
    }

    // MARK: Recording lifecycle

    @Test("VulkanCommandBuffer begin() opens recording")
    func testBeginOpensRecording() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        #expect(buf.isRecording)
    }

    @Test("VulkanCommandBuffer end() closes recording")
    func testEndClosesRecording() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        buf.end()
        #expect(!buf.isRecording)
    }

    @Test("VulkanCommandBuffer begin() clears prior commands")
    func testBeginClearsPriorCommands() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        buf.dispatch(x: 16)
        buf.end()
        #expect(buf.commandCount == 1)
        buf.begin()  // second recording session
        #expect(buf.commandCount == 0)
    }

    // MARK: Recording commands

    @Test("VulkanCommandBuffer records bindPipeline")
    func testRecordBindPipeline() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        buf.bindPipeline(name: "compute_gradients")
        buf.end()
        #expect(buf.commandCount == 1)
        if case .bindPipeline(let name) = buf.recordedCommands[0].operation {
            #expect(name == "compute_gradients")
        } else {
            Issue.record("Expected bindPipeline command")
        }
    }

    @Test("VulkanCommandBuffer records bindBuffer with binding index")
    func testRecordBindBuffer() throws {
        let buf = VulkanCommandBuffer()
        let buffer = try VulkanBuffer(size: 256, usage: .storageBuffer)
        buf.begin()
        buf.bindBuffer(buffer, binding: 2)
        buf.end()
        #expect(buf.commandCount == 1)
        if case .bindBuffer(_, let binding) = buf.recordedCommands[0].operation {
            #expect(binding == 2)
        } else {
            Issue.record("Expected bindBuffer command")
        }
    }

    @Test("VulkanCommandBuffer records pushConstants")
    func testRecordPushConstants() {
        let buf = VulkanCommandBuffer()
        let data: [UInt8] = [1, 0, 0, 0]  // Int32(1) in little-endian
        buf.begin()
        buf.pushConstants(data: data)
        buf.end()
        #expect(buf.commandCount == 1)
        if case .pushConstants(let d) = buf.recordedCommands[0].operation {
            #expect(d == data)
        } else {
            Issue.record("Expected pushConstants command")
        }
    }

    @Test("VulkanCommandBuffer records dispatch with default y=1, z=1")
    func testRecordDispatchDefaults() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        buf.dispatch(x: 64)
        buf.end()
        if case .dispatch(let x, let y, let z) = buf.recordedCommands[0].operation {
            #expect(x == 64)
            #expect(y == 1)
            #expect(z == 1)
        } else {
            Issue.record("Expected dispatch command")
        }
    }

    @Test("VulkanCommandBuffer records dispatch with explicit y and z")
    func testRecordDispatchExplicit() {
        let buf = VulkanCommandBuffer()
        buf.begin()
        buf.dispatch(x: 8, y: 4, z: 2)
        buf.end()
        if case .dispatch(let x, let y, let z) = buf.recordedCommands[0].operation {
            #expect(x == 8)
            #expect(y == 4)
            #expect(z == 2)
        } else {
            Issue.record("Expected dispatch command")
        }
    }

    @Test("VulkanCommandBuffer records a complete compute sequence")
    func testRecordFullComputeSequence() throws {
        let buf = VulkanCommandBuffer()
        let inputBuf  = try VulkanBuffer(size: 256, usage: .storageBuffer)
        let outputBuf = try VulkanBuffer(size: 256, usage: .storageBuffer)

        buf.begin()
        buf.bindPipeline(name: "compute_quantize_gradients")
        buf.bindBuffer(inputBuf,  binding: 0)
        buf.bindBuffer(outputBuf, binding: 1)
        buf.pushConstants(data: [9, 0, 0, 0])  // count = 9, as Int32 little-endian
        buf.dispatch(x: 1)
        buf.end()

        #expect(buf.commandCount == 5)
        #expect(!buf.isRecording)
    }

    // MARK: Commands ignored when not recording

    @Test("VulkanCommandBuffer ignores commands when not recording")
    func testCommandsIgnoredWhenNotRecording() throws {
        let buf = VulkanCommandBuffer()
        let buffer = try VulkanBuffer(size: 64, usage: .storageBuffer)
        // These should all be silently ignored
        buf.bindPipeline(name: "ignored")
        buf.bindBuffer(buffer, binding: 0)
        buf.pushConstants(data: [0])
        buf.dispatch(x: 1)
        #expect(buf.commandCount == 0)
    }
}

// MARK: - VulkanCommandPool Tests

@Suite("VulkanCommandPool Tests")
struct VulkanCommandPoolTests {

    @Test("VulkanCommandPool starts empty")
    func testInitEmpty() {
        let pool = VulkanCommandPool()
        #expect(pool.allocatedCount == 0)
    }

    @Test("VulkanCommandPool allocates command buffers")
    func testAllocate() {
        let pool = VulkanCommandPool()
        let buf1 = pool.allocate()
        let buf2 = pool.allocate()
        #expect(pool.allocatedCount == 2)
        // Each allocation returns a distinct object
        #expect(buf1 !== buf2)
    }

    @Test("VulkanCommandPool reset() releases all buffers")
    func testReset() {
        let pool = VulkanCommandPool()
        _ = pool.allocate()
        _ = pool.allocate()
        _ = pool.allocate()
        pool.reset()
        #expect(pool.allocatedCount == 0)
    }

    @Test("VulkanCommandPool can be reused after reset")
    func testReuseAfterReset() {
        let pool = VulkanCommandPool()
        _ = pool.allocate()
        pool.reset()
        let buf = pool.allocate()
        #expect(pool.allocatedCount == 1)
        // The returned buffer should be usable
        buf.begin()
        buf.dispatch(x: 4)
        buf.end()
        #expect(buf.commandCount == 1)
    }

    @Test("VulkanCommandPool allocated buffers are independently usable")
    func testAllocatedBuffersAreIndependent() {
        let pool = VulkanCommandPool()
        let buf1 = pool.allocate()
        let buf2 = pool.allocate()

        buf1.begin()
        buf1.dispatch(x: 8)
        buf1.end()

        buf2.begin()
        buf2.bindPipeline(name: "test")
        buf2.dispatch(x: 16)
        buf2.end()

        #expect(buf1.commandCount == 1)
        #expect(buf2.commandCount == 2)
    }
}
