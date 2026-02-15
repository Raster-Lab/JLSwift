/// Tests for JPEG-LS tile processor
import Testing
@testable import JPEGLS

@Suite("JPEG-LS Tile Processor Tests")
struct JPEGLSTileProcessorTests {
    
    @Test("Tile bounds initialization")
    func testTileBounds() {
        let bounds = TileBounds(rowStart: 0, rowEnd: 100, columnStart: 0, columnEnd: 100)
        
        #expect(bounds.width == 100)
        #expect(bounds.height == 100)
        #expect(bounds.pixelCount == 10_000)
    }
    
    @Test("Tile bounds contains check")
    func testTileBoundsContains() {
        let bounds = TileBounds(rowStart: 10, rowEnd: 20, columnStart: 30, columnEnd: 40)
        
        #expect(bounds.contains(row: 15, column: 35))
        #expect(!bounds.contains(row: 5, column: 35))
        #expect(!bounds.contains(row: 15, column: 50))
        #expect(!bounds.contains(row: 20, column: 35)) // Exclusive end
    }
    
    @Test("Default tile configuration")
    func testDefaultConfiguration() {
        let config = TileConfiguration.default
        
        #expect(config.tileWidth == 512)
        #expect(config.tileHeight == 512)
        #expect(config.overlap == 4)
    }
    
    @Test("Custom tile configuration")
    func testCustomConfiguration() {
        let config = TileConfiguration(tileWidth: 256, tileHeight: 256, overlap: 8)
        
        #expect(config.tileWidth == 256)
        #expect(config.tileHeight == 256)
        #expect(config.overlap == 8)
    }
    
    @Test("Calculate tiles for small image")
    func testCalculateTilesSmallImage() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 100,
            imageHeight: 100,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        
        #expect(tiles.count == 1)
        #expect(tiles[0].width == 100)
        #expect(tiles[0].height == 100)
    }
    
    @Test("Calculate tiles for exact fit")
    func testCalculateTilesExactFit() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1024,
            imageHeight: 1024,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        
        #expect(tiles.count == 4) // 2x2 grid
        #expect(tiles.allSatisfy { $0.width == 512 && $0.height == 512 })
    }
    
    @Test("Calculate tiles for non-exact fit")
    func testCalculateTilesNonExactFit() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1000,
            imageHeight: 1000,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        
        #expect(tiles.count == 4) // 2x2 grid
        
        // First tiles should be 512x512
        #expect(tiles[0].width == 512)
        #expect(tiles[0].height == 512)
        
        // Last tiles should be smaller (488x488)
        #expect(tiles[3].width == 488)
        #expect(tiles[3].height == 488)
    }
    
    @Test("Calculate tiles with overlap")
    func testCalculateTilesWithOverlap() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1024,
            imageHeight: 1024,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 4)
        )
        
        let tiles = processor.calculateTilesWithOverlap()
        
        #expect(tiles.count == 4)
        
        // First tile should extend beyond its nominal bounds
        let firstTile = tiles[0]
        #expect(firstTile.rowStart == 0) // Can't go below 0
        #expect(firstTile.columnStart == 0)
        #expect(firstTile.rowEnd == 516) // 512 + 4
        #expect(firstTile.columnEnd == 516)
    }
    
    @Test("Calculate tiles covers entire image")
    func testTilesCoverEntireImage() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1500,
            imageHeight: 1000,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        
        // Check that all pixels are covered
        for row in 0..<1000 {
            for col in 0..<1500 {
                let covered = tiles.contains { $0.contains(row: row, column: col) }
                #expect(covered, "Pixel at (\(row), \(col)) not covered")
            }
        }
    }
    
    @Test("Tile count calculation")
    func testTileCount() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 1024,
            imageHeight: 512,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let count = processor.tileCount()
        #expect(count == 2) // 2x1 grid
    }
    
    @Test("Estimate memory savings for small tile")
    func testEstimateMemorySavings() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 4096,
            imageHeight: 4096,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let savings = processor.estimateMemorySavings(bytesPerPixel: 2)
        
        // Tile is 512x512, image is 4096x4096
        // Savings should be 1 - (512*512 / 4096*4096) = 1 - (262144 / 16777216) ≈ 0.984
        #expect(savings > 0.9)
        #expect(savings < 1.0)
    }
    
    @Test("Estimate memory savings for single tile")
    func testEstimateMemorySavingsSingleTile() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 256,
            imageHeight: 256,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let savings = processor.estimateMemorySavings(bytesPerPixel: 2)
        
        // Image fits in single tile, no savings
        #expect(savings == 0.0)
    }
    
    @Test("Large image tiling")
    func testLargeImageTiling() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 8192,
            imageHeight: 8192,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        let expectedTiles = 16 * 16 // 16x16 grid
        
        #expect(tiles.count == expectedTiles)
        
        // Verify each tile is correctly sized
        for tile in tiles {
            #expect(tile.width <= 512)
            #expect(tile.height <= 512)
        }
    }
    
    @Test("Non-square tiles")
    func testNonSquareTiles() {
        let processor = JPEGLSTileProcessor(
            imageWidth: 2048,
            imageHeight: 1024,
            configuration: TileConfiguration(tileWidth: 512, tileHeight: 256, overlap: 0)
        )
        
        let tiles = processor.calculateTiles()
        
        // Should be 4x4 grid
        #expect(tiles.count == 16)
    }
    
    @Test("Tile bounds equality")
    func testTileBoundsEquality() {
        let bounds1 = TileBounds(rowStart: 0, rowEnd: 100, columnStart: 0, columnEnd: 100)
        let bounds2 = TileBounds(rowStart: 0, rowEnd: 100, columnStart: 0, columnEnd: 100)
        let bounds3 = TileBounds(rowStart: 0, rowEnd: 100, columnStart: 0, columnEnd: 50)
        
        #expect(bounds1 == bounds2)
        #expect(bounds1 != bounds3)
    }
}
