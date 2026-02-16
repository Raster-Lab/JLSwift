import Testing
import Foundation
@testable import JPEGLS

/// Comprehensive edge case and robustness testing for JPEG-LS implementation
@Suite("Edge Cases and Robustness")
struct EdgeCasesTests {
    
    // MARK: - Preset Parameters Edge Cases
    
    @Test("Preset parameters with minimum valid values")
    func testPresetParametersMinimumValues() throws {
        // Test with minimum MAXVAL (2) and minimum valid thresholds
        let params = try JPEGLSPresetParameters(
            maxValue: 2,
            threshold1: 1,  // T1 must be >= 1
            threshold2: 1,
            threshold3: 1,
            reset: 64
        )
        #expect(params.maxValue == 2)
    }
    
    @Test("Preset parameters with maximum valid values")
    func testPresetParametersMaximumValues() throws {
        // Test with maximum MAXVAL (65535 for 16-bit)
        let params = try JPEGLSPresetParameters(
            maxValue: 65535,
            threshold1: 100,
            threshold2: 200,
            threshold3: 300,
            reset: 64
        )
        #expect(params.maxValue == 65535)
    }
    
    @Test("Preset parameters with invalid MAXVAL (too small)")
    func testPresetParametersInvalidMAXVALTooSmall() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSPresetParameters(
                maxValue: 1,  // Too small
                threshold1: 1,
                threshold2: 2,
                threshold3: 3,
                reset: 64
            )
        }
    }
    
    @Test("Preset parameters with invalid MAXVAL (too large)")
    func testPresetParametersInvalidMAXVALTooLarge() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSPresetParameters(
                maxValue: 65536,  // Too large
                threshold1: 1,
                threshold2: 2,
                threshold3: 3,
                reset: 64
            )
        }
    }
    
    @Test("Preset parameters with invalid threshold ordering")
    func testPresetParametersInvalidThresholdOrdering() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 3,
                threshold2: 2,  // T2 < T1 is invalid
                threshold3: 7,
                reset: 64
            )
        }
    }
    
    @Test("Preset parameters with invalid RESET value (zero)")
    func testPresetParametersInvalidRESETZero() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 1,
                threshold2: 2,
                threshold3: 3,
                reset: 0  // Invalid
            )
        }
    }
    
    // MARK: - Context Model Edge Cases
    
    @Test("Context model with minimum MAXVAL")
    func testContextModelMinimumMAXVAL() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 2,
            threshold1: 1,  // T1 must be >= 1
            threshold2: 1,
            threshold3: 1,
            reset: 64
        )
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        #expect(context != nil)
    }
    
    @Test("Context model with maximum MAXVAL")
    func testContextModelMaximumMAXVAL() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 65535,
            threshold1: 10,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        let context = try JPEGLSContextModel(parameters: params, near: 0)
        #expect(context != nil)
    }
    
    @Test("Context model with invalid NEAR (negative)")
    func testContextModelInvalidNEARNegative() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 3,
            threshold2: 7,
            threshold3: 21,
            reset: 64
        )
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSContextModel(parameters: params, near: -1)
        }
    }
    
    @Test("Context model with invalid NEAR (too large)")
    func testContextModelInvalidNEARTooLarge() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 3,
            threshold2: 7,
            threshold3: 21,
            reset: 64
        )
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSContextModel(parameters: params, near: 256)
        }
    }
    
    @Test("Context model with NEAR at boundary (255)")
    func testContextModelNEARBoundary() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 3,
            threshold2: 7,
            threshold3: 21,
            reset: 64
        )
        let context = try JPEGLSContextModel(parameters: params, near: 255)
        #expect(context != nil)
    }
    
    // MARK: - Bitstream Reader Edge Cases
    
    @Test("Bitstream reader with empty data")
    func testBitstreamReaderEmptyData() {
        var reader = JPEGLSBitstreamReader(data: Data())
        #expect(throws: JPEGLSError.self) {
            _ = try reader.readByte()
        }
    }
    
    @Test("Bitstream reader with single byte")
    func testBitstreamReaderSingleByte() throws {
        var reader = JPEGLSBitstreamReader(data: Data([0x42]))
        let byte = try reader.readByte()
        #expect(byte == 0x42)
        
        // Reading beyond end should throw
        #expect(throws: JPEGLSError.self) {
            _ = try reader.readByte()
        }
    }
    
    @Test("Bitstream reader reads bytes sequentially")
    func testBitstreamReaderSequential() throws {
        // Simple sequential reading test
        var reader = JPEGLSBitstreamReader(data: Data([0xFF, 0x00, 0x42]))
        let byte1 = try reader.readByte()
        #expect(byte1 == 0xFF)
        
        let byte2 = try reader.readByte()
        #expect(byte2 == 0x00)
        
        let byte3 = try reader.readByte()
        #expect(byte3 == 0x42)
    }
    
    @Test("Bitstream reader reading bits beyond data")
    func testBitstreamReaderBitsBeyondData() {
        var reader = JPEGLSBitstreamReader(data: Data([0xFF]))
        #expect(throws: JPEGLSError.self) {
            _ = try reader.readBits(16)  // Try to read more bits than available
        }
    }
    
    // MARK: - Bitstream Writer Edge Cases
    
    @Test("Bitstream writer marker stuffing for 0xFF")
    func testBitstreamWriterMarkerStuffing() throws {
        let writer = JPEGLSBitstreamWriter()
        writer.writeByte(0xFF)
        writer.writeByte(0x42)
        writer.flush()
        
        let data = try writer.getData()
        // 0xFF should be stuffed as 0xFF 0x00
        #expect(data.count == 3)
        #expect(data[0] == 0xFF)
        #expect(data[1] == 0x00)
        #expect(data[2] == 0x42)
    }
    
    @Test("Bitstream writer with zero bits")
    func testBitstreamWriterZeroBits() throws {
        let writer = JPEGLSBitstreamWriter()
        writer.writeBits(0, count: 0)
        writer.flush()
        
        let data = try writer.getData()
        #expect(data.isEmpty)
    }
    
    // MARK: - Frame Header Edge Cases
    
    @Test("Frame header with minimum dimensions (1x1)")
    func testFrameHeaderMinimumDimensions() throws {
        let header = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: 1,
            width: 1,
            componentCount: 1,
            components: [
                JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1)
            ]
        )
        #expect(header.height == 1)
        #expect(header.width == 1)
    }
    
    @Test("Frame header with maximum dimensions (65535x65535)")
    func testFrameHeaderMaximumDimensions() throws {
        let header = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: 65535,
            width: 65535,
            componentCount: 1,
            components: [
                JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1)
            ]
        )
        #expect(header.height == 65535)
        #expect(header.width == 65535)
    }
    
    @Test("Frame header with zero width throws error")
    func testFrameHeaderZeroWidth() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 0,  // Invalid
                componentCount: 1,
                components: [
                    JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1)
                ]
            )
        }
    }
    
    @Test("Frame header with zero height throws error")
    func testFrameHeaderZeroHeight() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 0,  // Invalid
                width: 100,
                componentCount: 1,
                components: [
                    JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1)
                ]
            )
        }
    }
    
    @Test("Frame header with invalid bits per sample (1) throws error")
    func testFrameHeaderInvalidBitsPerSample() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSFrameHeader(
                bitsPerSample: 1,  // Invalid (min is 2)
                height: 100,
                width: 100,
                componentCount: 1,
                components: [
                    JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1)
                ]
            )
        }
    }
    
    @Test("Frame header with invalid component count (0) throws error")
    func testFrameHeaderInvalidComponentCountZero() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 100,
                componentCount: 0,  // Invalid
                components: []
            )
        }
    }
    
    @Test("Frame header with invalid component count (5) throws error")
    func testFrameHeaderInvalidComponentCountTooMany() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 100,
                componentCount: 5,  // Invalid (max is 4)
                components: Array(repeating: JPEGLSFrameHeader.ComponentSpec(id: 1, horizontalSamplingFactor: 1, verticalSamplingFactor: 1), count: 5)
            )
        }
    }
    
    // MARK: - Scan Header Edge Cases
    
    @Test("Scan header with single component")
    func testScanHeaderSingleComponent() throws {
        let header = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: 0,
            interleaveMode: .none,
            pointTransform: 0
        )
        #expect(header.componentCount == 1)
    }
    
    @Test("Scan header with maximum components (4)")
    func testScanHeaderMaximumComponents() throws {
        let header = try JPEGLSScanHeader(
            componentCount: 4,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3),
                JPEGLSScanHeader.ComponentSelector(id: 4)
            ],
            near: 0,
            interleaveMode: .sample,
            pointTransform: 0
        )
        #expect(header.componentCount == 4)
    }
    
    @Test("Scan header with invalid component count (0)")
    func testScanHeaderInvalidComponentCountZero() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSScanHeader(
                componentCount: 0,  // Invalid
                components: [],
                near: 0,
                interleaveMode: .none,
                pointTransform: 0
            )
        }
    }
    
    @Test("Scan header with mismatched component count")
    func testScanHeaderMismatchedComponentCount() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSScanHeader(
                componentCount: 2,
                components: [JPEGLSScanHeader.ComponentSelector(id: 1)],  // Only 1 component
                near: 0,
                interleaveMode: .none,
                pointTransform: 0
            )
        }
    }
    
    // MARK: - Buffer Pool Edge Cases
    
    @Test("Buffer pool with zero-size buffer")
    func testBufferPoolZeroSize() {
        let pool = JPEGLSBufferPool()
        let buffer = pool.acquire(type: .contextArrays, size: 0)
        #expect(buffer.isEmpty)
    }
    
    @Test("Buffer pool with very large buffer")
    func testBufferPoolVeryLargeBuffer() {
        let pool = JPEGLSBufferPool()
        let size = 10_000_000  // 10 million elements
        let buffer = pool.acquire(type: .pixelData, size: size)
        #expect(buffer.count == size)
        pool.release(buffer, type: .pixelData)
    }
    
    @Test("Buffer pool cleanup")
    func testBufferPoolCleanup() {
        let pool = JPEGLSBufferPool(maxPoolSize: 2, bufferLifetime: 0.1)
        
        // Acquire and release buffers
        let buffer1 = pool.acquire(type: .contextArrays, size: 100)
        pool.release(buffer1, type: .contextArrays)
        
        let buffer2 = pool.acquire(type: .contextArrays, size: 200)
        pool.release(buffer2, type: .contextArrays)
        
        // Cleanup should work without errors
        pool.cleanup()
    }
    
    // MARK: - Tile Processor Edge Cases
    
    @Test("Tile processor with single tile (tile larger than image)")
    func testTileProcessorSingleTile() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 100,
            imageHeight: 100,
            configuration: TileConfiguration(tileWidth: 200, tileHeight: 200, overlap: 0)
        )
        let tiles = processor.calculateTiles()
        #expect(tiles.count == 1)
    }
    
    @Test("Tile processor with minimum image size (1x1)")
    func testTileProcessorMinimumImageSize() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1,
            imageHeight: 1,
            configuration: TileConfiguration(tileWidth: 1, tileHeight: 1, overlap: 0)
        )
        let tiles = processor.calculateTiles()
        #expect(tiles.count == 1)
        #expect(tiles[0].width == 1)
        #expect(tiles[0].height == 1)
    }
    
    @Test("Tile processor with maximum overlap")
    func testTileProcessorMaximumOverlap() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 100,
            imageHeight: 100,
            configuration: TileConfiguration(tileWidth: 50, tileHeight: 50, overlap: 25)
        )
        let tiles = processor.calculateTilesWithOverlap()
        // With large overlap, there should be more tiles
        #expect(tiles.count >= 4)
    }
    
    @Test("Tile processor memory savings calculation")
    func testTileProcessorMemorySavings() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 4096,
            imageHeight: 4096,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        let savings = processor.estimateMemorySavings(bytesPerPixel: 2)
        // Should have positive memory savings
        #expect(savings > 0)
        #expect(savings < 1.0)  // Can't save more than 100%
    }
    
    // MARK: - Cache-Friendly Buffer Edge Cases
    
    @Test("Cache-friendly buffer with single pixel")
    func testCacheFriendlyBufferSinglePixel() {
        let pixelData: [UInt8: [[Int]]] = [
            1: [[42]]
        ]
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 1, height: 1)
        let pixel = buffer.getPixel(componentId: 1, row: 0, column: 0)
        #expect(pixel == 42)
    }
    
    @Test("Cache-friendly buffer boundary access")
    func testCacheFriendlyBufferBoundaryAccess() {
        let pixelData: [UInt8: [[Int]]] = [
            1: (0..<10).map { y in
                (0..<10).map { x in
                    x + y * 10
                }
            }
        ]
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 10, height: 10)
        
        // Test corners
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 0) == 0)
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 9) == 9)
        #expect(buffer.getPixel(componentId: 1, row: 9, column: 0) == 90)
        #expect(buffer.getPixel(componentId: 1, row: 9, column: 9) == 99)
    }
    
    @Test("Cache-friendly buffer with multiple components")
    func testCacheFriendlyBufferMultipleComponents() {
        let pixelData: [UInt8: [[Int]]] = [
            1: [[100]],
            2: [[200]],
            3: [[300]]
        ]
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 1, height: 1)
        
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 0) == 100)
        #expect(buffer.getPixel(componentId: 2, row: 0, column: 0) == 200)
        #expect(buffer.getPixel(componentId: 3, row: 0, column: 0) == 300)
    }
}
