/// Tests for cache-friendly buffer
import Testing
@testable import JPEGLS

@Suite("JPEG-LS Cache-Friendly Buffer Tests")
struct JPEGLSCacheFriendlyBufferTests {
    
    @Test("Create buffer from 2D data")
    func testCreateFrom2DData() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 3)
        
        #expect(buffer.width == 3)
        #expect(buffer.height == 3)
        #expect(buffer.componentCount == 1)
    }
    
    @Test("Get pixel from buffer")
    func testGetPixel() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [10, 20, 30],
                [40, 50, 60]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 2)
        
        #expect(buffer.getPixel(componentId: 0, row: 0, column: 0) == 10)
        #expect(buffer.getPixel(componentId: 0, row: 0, column: 2) == 30)
        #expect(buffer.getPixel(componentId: 0, row: 1, column: 1) == 50)
    }
    
    @Test("Get pixel out of bounds")
    func testGetPixelOutOfBounds() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [[1, 2], [3, 4]]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 2, height: 2)
        
        #expect(buffer.getPixel(componentId: 0, row: -1, column: 0) == nil)
        #expect(buffer.getPixel(componentId: 0, row: 0, column: 5) == nil)
        #expect(buffer.getPixel(componentId: 0, row: 10, column: 0) == nil)
    }
    
    @Test("Set pixel creates new buffer")
    func testSetPixel() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [[1, 2], [3, 4]]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 2, height: 2)
        let newBuffer = buffer.settingPixel(componentId: 0, row: 1, column: 1, value: 99)
        
        #expect(buffer.getPixel(componentId: 0, row: 1, column: 1) == 4)
        #expect(newBuffer.getPixel(componentId: 0, row: 1, column: 1) == 99)
    }
    
    @Test("Get row from buffer")
    func testGetRow() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [10, 20, 30],
                [40, 50, 60],
                [70, 80, 90]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 3)
        let row1 = buffer.getRow(componentId: 0, row: 1)
        
        #expect(row1 == [40, 50, 60])
    }
    
    @Test("Get multiple rows")
    func testGetRows() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2],
                [3, 4],
                [5, 6]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 2, height: 3)
        let rows = buffer.getRows(componentId: 0, rowStart: 0, rowEnd: 2)
        
        #expect(rows == [1, 2, 3, 4])
    }
    
    @Test("Get neighbors")
    func testGetNeighbors() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2, 3],
                [4, 5, 6],
                [7, 8, 9]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 3)
        
        // Center pixel
        let neighbors = buffer.getNeighbors(componentId: 0, row: 1, column: 1)
        #expect(neighbors.left == 4)
        #expect(neighbors.top == 2)
        #expect(neighbors.topLeft == 1)
        #expect(neighbors.topRight == 3)
    }
    
    @Test("Get neighbors at edges")
    func testGetNeighborsAtEdges() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2, 3],
                [4, 5, 6]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 2)
        
        // Top-left corner
        let topLeft = buffer.getNeighbors(componentId: 0, row: 0, column: 0)
        #expect(topLeft.left == nil)
        #expect(topLeft.top == nil)
        #expect(topLeft.topLeft == nil)
        #expect(topLeft.topRight == nil)
        
        // Top edge
        let topEdge = buffer.getNeighbors(componentId: 0, row: 0, column: 1)
        #expect(topEdge.left == 1)
        #expect(topEdge.top == nil)
        #expect(topEdge.topLeft == nil)
        #expect(topEdge.topRight == nil)
        
        // Bottom-right corner
        let bottomRight = buffer.getNeighbors(componentId: 0, row: 1, column: 2)
        #expect(bottomRight.left == 5)
        #expect(bottomRight.top == 3)
        #expect(bottomRight.topLeft == 2)
        #expect(bottomRight.topRight == nil)
    }
    
    @Test("Convert to 2D array")
    func testTo2DArray() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2, 3],
                [4, 5, 6]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 3, height: 2)
        let result = buffer.to2DArray(componentId: 0)
        
        #expect(result == [[1, 2, 3], [4, 5, 6]])
    }
    
    @Test("Get contiguous data")
    func testGetContiguousData() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [1, 2],
                [3, 4]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 2, height: 2)
        let data = buffer.getContiguousData(componentId: 0)
        
        #expect(data == [1, 2, 3, 4])
    }
    
    @Test("Multiple components")
    func testMultipleComponents() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [[1, 2], [3, 4]],
            1: [[5, 6], [7, 8]],
            2: [[9, 10], [11, 12]]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 2, height: 2)
        
        #expect(buffer.componentCount == 3)
        #expect(buffer.componentIds.sorted() == [0, 1, 2])
        
        #expect(buffer.getPixel(componentId: 0, row: 0, column: 0) == 1)
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 0) == 5)
        #expect(buffer.getPixel(componentId: 2, row: 0, column: 0) == 9)
    }
    
    @Test("Large buffer performance")
    func testLargeBuffer() {
        // Create a large buffer to test performance
        var rows: [[Int]] = []
        for row in 0..<1024 {
            var rowData: [Int] = []
            for col in 0..<1024 {
                rowData.append(row * 1024 + col)
            }
            rows.append(rowData)
        }
        
        let pixelData: [UInt8: [[Int]]] = [0: rows]
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 1024, height: 1024)
        
        // Test random access
        let pixel = buffer.getPixel(componentId: 0, row: 500, column: 750)
        #expect(pixel == 500 * 1024 + 750)
        
        // Test row access
        let row = buffer.getRow(componentId: 0, row: 100)
        #expect(row.count == 1024)
        #expect(row[0] == 100 * 1024)
    }
    
    @Test("Cache-friendly neighbor access pattern")
    func testCacheFriendlyNeighborAccess() {
        let pixelData: [UInt8: [[Int]]] = [
            0: [
                [10, 20, 30, 40],
                [50, 60, 70, 80],
                [90, 100, 110, 120]
            ]
        ]
        
        let buffer = JPEGLSCacheFriendlyBuffer(pixelData: pixelData, width: 4, height: 3)
        
        // Simulate processing a scanline (cache-friendly)
        for col in 0..<4 {
            let neighbors = buffer.getNeighbors(componentId: 0, row: 1, column: col)
            
            // Verify correct neighbors
            if col == 0 {
                #expect(neighbors.left == nil)
                #expect(neighbors.top == 10)
            } else {
                #expect(neighbors.left != nil)
                #expect(neighbors.top != nil)
            }
        }
    }
    
    @Test("Memory statistics initialization")
    func testMemoryStatistics() {
        let stats = JPEGLSMemoryStatistics(totalBytes: 1000, peakBytes: 500, allocationCount: 10)
        
        #expect(stats.totalBytes == 1000)
        #expect(stats.peakBytes == 500)
        #expect(stats.allocationCount == 10)
        #expect(stats.averageAllocationSize == 100.0)
    }
    
    @Test("Memory statistics with zero allocations")
    func testMemoryStatisticsZeroAllocations() {
        let stats = JPEGLSMemoryStatistics(totalBytes: 0, peakBytes: 0, allocationCount: 0)
        
        #expect(stats.averageAllocationSize == 0.0)
    }
}
