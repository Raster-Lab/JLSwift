/// Tile-based processing for large images to reduce memory footprint
///
/// Enables processing large images in smaller tiles, reducing peak memory usage
/// while maintaining JPEG-LS encoding/decoding correctness.
import Foundation

/// Tile boundary information for processing
public struct TileBounds: Equatable, Sendable {
    /// Starting row of the tile (inclusive)
    public let rowStart: Int
    /// Ending row of the tile (exclusive)
    public let rowEnd: Int
    /// Starting column of the tile (inclusive)
    public let columnStart: Int
    /// Ending column of the tile (exclusive)
    public let columnEnd: Int
    
    /// Width of the tile in pixels
    public var width: Int { columnEnd - columnStart }
    
    /// Height of the tile in pixels
    public var height: Int { rowEnd - rowStart }
    
    /// Total number of pixels in the tile
    public var pixelCount: Int { width * height }
    
    /// Creates a new tile bounds
    public init(rowStart: Int, rowEnd: Int, columnStart: Int, columnEnd: Int) {
        self.rowStart = rowStart
        self.rowEnd = rowEnd
        self.columnStart = columnStart
        self.columnEnd = columnEnd
    }
    
    /// Checks if the tile contains a specific position
    public func contains(row: Int, column: Int) -> Bool {
        row >= rowStart && row < rowEnd && column >= columnStart && column < columnEnd
    }
}

/// Configuration for tile-based processing
public struct TileConfiguration: Sendable {
    /// Target tile width in pixels (default: 512)
    public let tileWidth: Int
    
    /// Target tile height in pixels (default: 512)
    public let tileHeight: Int
    
    /// Overlap between adjacent tiles in pixels for boundary handling (default: 4)
    public let overlap: Int
    
    /// Creates a new tile configuration
    /// - Parameters:
    ///   - tileWidth: Target width for each tile
    ///   - tileHeight: Target height for each tile
    ///   - overlap: Overlap between tiles in pixels
    public init(tileWidth: Int = 512, tileHeight: Int = 512, overlap: Int = 4) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.overlap = overlap
    }
    
    /// Default tile configuration
    public static let `default` = TileConfiguration()
}

/// Manages tile-based processing of large images
public struct JPEGLSTileProcessor: Sendable {
    /// Width of the full image in pixels
    public let imageWidth: Int
    
    /// Height of the full image in pixels
    public let imageHeight: Int
    
    /// Tile configuration
    public let configuration: TileConfiguration
    
    /// Creates a new tile processor
    /// - Parameters:
    ///   - imageWidth: Width of the full image
    ///   - imageHeight: Height of the full image
    ///   - configuration: Tile processing configuration
    public init(imageWidth: Int, imageHeight: Int, configuration: TileConfiguration = .default) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.configuration = configuration
    }
    
    /// Calculates all tile bounds for processing the image
    /// - Returns: Array of tile bounds covering the entire image
    public func calculateTiles() -> [TileBounds] {
        var tiles: [TileBounds] = []
        
        let tileWidth = configuration.tileWidth
        let tileHeight = configuration.tileHeight
        
        var rowStart = 0
        while rowStart < imageHeight {
            let rowEnd = min(rowStart + tileHeight, imageHeight)
            
            var columnStart = 0
            while columnStart < imageWidth {
                let columnEnd = min(columnStart + tileWidth, imageWidth)
                
                tiles.append(TileBounds(
                    rowStart: rowStart,
                    rowEnd: rowEnd,
                    columnStart: columnStart,
                    columnEnd: columnEnd
                ))
                
                columnStart = columnEnd
            }
            
            rowStart = rowEnd
        }
        
        return tiles
    }
    
    /// Calculates tile bounds with overlap for boundary handling
    /// - Returns: Array of tile bounds with overlap regions
    public func calculateTilesWithOverlap() -> [TileBounds] {
        var tiles: [TileBounds] = []
        
        let tileWidth = configuration.tileWidth
        let tileHeight = configuration.tileHeight
        let overlap = configuration.overlap
        
        var rowStart = 0
        while rowStart < imageHeight {
            let rowEnd = min(rowStart + tileHeight, imageHeight)
            let rowStartWithOverlap = max(0, rowStart - overlap)
            let rowEndWithOverlap = min(imageHeight, rowEnd + overlap)
            
            var columnStart = 0
            while columnStart < imageWidth {
                let columnEnd = min(columnStart + tileWidth, imageWidth)
                let columnStartWithOverlap = max(0, columnStart - overlap)
                let columnEndWithOverlap = min(imageWidth, columnEnd + overlap)
                
                tiles.append(TileBounds(
                    rowStart: rowStartWithOverlap,
                    rowEnd: rowEndWithOverlap,
                    columnStart: columnStartWithOverlap,
                    columnEnd: columnEndWithOverlap
                ))
                
                columnStart = columnEnd
            }
            
            rowStart = rowEnd
        }
        
        return tiles
    }
    
    /// Gets the number of tiles needed to process the image
    public func tileCount() -> Int {
        let tilesPerRow = (imageWidth + configuration.tileWidth - 1) / configuration.tileWidth
        let tilesPerColumn = (imageHeight + configuration.tileHeight - 1) / configuration.tileHeight
        return tilesPerRow * tilesPerColumn
    }
    
    /// Estimates memory savings from tile-based processing
    /// - Parameter bytesPerPixel: Number of bytes per pixel
    /// - Returns: Estimated memory reduction ratio (0.0 to 1.0)
    public func estimateMemorySavings(bytesPerPixel: Int) -> Double {
        let fullImageMemory = imageWidth * imageHeight * bytesPerPixel
        let tileMemory = configuration.tileWidth * configuration.tileHeight * bytesPerPixel
        
        guard fullImageMemory > 0 else { return 0.0 }
        
        let savings = 1.0 - (Double(tileMemory) / Double(fullImageMemory))
        return max(0.0, min(1.0, savings))
    }
}
