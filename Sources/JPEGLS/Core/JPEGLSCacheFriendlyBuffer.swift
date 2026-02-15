/// Cache-friendly data layout for JPEG-LS processing
///
/// Optimizes data structures for better CPU cache utilization during encoding/decoding.
/// Uses row-major layout with contiguous memory and prefetching hints.
import Foundation

/// Cache-friendly pixel buffer with optimized memory layout
public struct JPEGLSCacheFriendlyBuffer: Sendable {
    /// Component data stored in contiguous memory (row-major order)
    private let componentData: [UInt8: [Int]]
    
    /// Image dimensions
    public let width: Int
    public let height: Int
    
    /// Number of components
    public let componentCount: Int
    
    /// Cache line size for prefetching (typically 64 bytes on modern CPUs)
    private static let cacheLineSize = 64
    
    /// Creates a new cache-friendly buffer from 2D pixel data
    /// - Parameters:
    ///   - pixelData: 2D pixel data per component
    ///   - width: Image width
    ///   - height: Image height
    public init(pixelData: [UInt8: [[Int]]], width: Int, height: Int) {
        self.width = width
        self.height = height
        self.componentCount = pixelData.count
        
        // Flatten 2D arrays into contiguous 1D arrays for better cache locality
        var flattened: [UInt8: [Int]] = [:]
        for (componentId, rows) in pixelData {
            var flat = [Int]()
            flat.reserveCapacity(width * height)
            for row in rows {
                flat.append(contentsOf: row)
            }
            flattened[componentId] = flat
        }
        
        self.componentData = flattened
    }
    
    /// Creates a new cache-friendly buffer with contiguous data
    /// - Parameters:
    ///   - contiguousData: Contiguous pixel data per component (row-major order)
    ///   - width: Image width
    ///   - height: Image height
    public init(contiguousData: [UInt8: [Int]], width: Int, height: Int) {
        self.width = width
        self.height = height
        self.componentCount = contiguousData.count
        self.componentData = contiguousData
    }
    
    /// Gets a pixel value at the specified position
    /// - Parameters:
    ///   - componentId: Component identifier
    ///   - row: Row index
    ///   - column: Column index
    /// - Returns: Pixel value or nil if out of bounds
    @inline(__always)
    public func getPixel(componentId: UInt8, row: Int, column: Int) -> Int? {
        guard row >= 0, row < height, column >= 0, column < width else { return nil }
        guard let data = componentData[componentId] else { return nil }
        
        let index = row * width + column
        return data[index]
    }
    
    /// Sets a pixel value at the specified position (creates a new buffer)
    /// - Parameters:
    ///   - componentId: Component identifier
    ///   - row: Row index
    ///   - column: Column index
    ///   - value: New pixel value
    /// - Returns: New buffer with the updated pixel
    public func settingPixel(componentId: UInt8, row: Int, column: Int, value: Int) -> JPEGLSCacheFriendlyBuffer {
        guard row >= 0, row < height, column >= 0, column < width else { return self }
        
        var newData = componentData
        if var data = newData[componentId] {
            let index = row * width + column
            data[index] = value
            newData[componentId] = data
        }
        
        return JPEGLSCacheFriendlyBuffer(contiguousData: newData, width: width, height: height)
    }
    
    /// Gets a contiguous row of pixels for cache-efficient processing
    /// - Parameters:
    ///   - componentId: Component identifier
    ///   - row: Row index
    /// - Returns: Array of pixels in the row or empty array if invalid
    @inline(__always)
    public func getRow(componentId: UInt8, row: Int) -> [Int] {
        guard row >= 0, row < height else { return [] }
        guard let data = componentData[componentId] else { return [] }
        
        let startIndex = row * width
        let endIndex = startIndex + width
        return Array(data[startIndex..<endIndex])
    }
    
    /// Gets multiple contiguous rows for cache-efficient processing
    /// - Parameters:
    ///   - componentId: Component identifier
    ///   - rowStart: Starting row (inclusive)
    ///   - rowEnd: Ending row (exclusive)
    /// - Returns: Flattened array of pixels from the row range
    @inline(__always)
    public func getRows(componentId: UInt8, rowStart: Int, rowEnd: Int) -> [Int] {
        guard rowStart >= 0, rowEnd <= height, rowStart < rowEnd else { return [] }
        guard let data = componentData[componentId] else { return [] }
        
        let startIndex = rowStart * width
        let endIndex = rowEnd * width
        return Array(data[startIndex..<endIndex])
    }
    
    /// Gets neighbor pixels in cache-friendly manner
    /// - Parameters:
    ///   - componentId: Component identifier
    ///   - row: Row index
    ///   - column: Column index
    /// - Returns: Neighbor pixels (left, top, top-left, top-right)
    @inline(__always)
    public func getNeighbors(componentId: UInt8, row: Int, column: Int) -> (left: Int?, top: Int?, topLeft: Int?, topRight: Int?) {
        guard let data = componentData[componentId] else {
            return (nil, nil, nil, nil)
        }
        
        // Calculate indices for cache-efficient access
        let currentIndex = row * width + column
        
        let left = column > 0 ? data[currentIndex - 1] : nil
        let top = row > 0 ? data[currentIndex - width] : nil
        let topLeft = (row > 0 && column > 0) ? data[currentIndex - width - 1] : nil
        let topRight = (row > 0 && column < width - 1) ? data[currentIndex - width + 1] : nil
        
        return (left, top, topLeft, topRight)
    }
    
    /// Converts back to 2D array format for compatibility
    /// - Parameter componentId: Component identifier
    /// - Returns: 2D pixel array
    public func to2DArray(componentId: UInt8) -> [[Int]] {
        guard let data = componentData[componentId] else { return [] }
        
        var result: [[Int]] = []
        result.reserveCapacity(height)
        
        for row in 0..<height {
            let startIndex = row * width
            let endIndex = startIndex + width
            result.append(Array(data[startIndex..<endIndex]))
        }
        
        return result
    }
    
    /// Gets all contiguous data for a component
    /// - Parameter componentId: Component identifier
    /// - Returns: Contiguous array of pixels in row-major order
    public func getContiguousData(componentId: UInt8) -> [Int] {
        return componentData[componentId] ?? []
    }
    
    /// Gets all component identifiers
    public var componentIds: [UInt8] {
        return Array(componentData.keys).sorted()
    }
}

/// Memory statistics for profiling
public struct JPEGLSMemoryStatistics: Sendable {
    /// Total bytes allocated
    public let totalBytes: Int
    
    /// Peak bytes used
    public let peakBytes: Int
    
    /// Number of allocations
    public let allocationCount: Int
    
    /// Average allocation size
    public var averageAllocationSize: Double {
        guard allocationCount > 0 else { return 0 }
        return Double(totalBytes) / Double(allocationCount)
    }
    
    /// Creates new memory statistics
    public init(totalBytes: Int, peakBytes: Int, allocationCount: Int) {
        self.totalBytes = totalBytes
        self.peakBytes = peakBytes
        self.allocationCount = allocationCount
    }
}
