/// Tests for JPEG-LS pixel buffer and multi-component image data

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Pixel Buffer Tests")
struct JPEGLSPixelBufferTests {
    
    // MARK: - Multi-Component Image Data Tests
    
    @Test("Create grayscale image data")
    func createGrayscaleImageData() throws {
        let pixels = [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        #expect(imageData.components.count == 1)
        #expect(imageData.components[0].id == 1)
        #expect(imageData.components[0].pixels == pixels)
        #expect(imageData.frameHeader.width == 3)
        #expect(imageData.frameHeader.height == 3)
        #expect(imageData.frameHeader.componentCount == 1)
    }
    
    @Test("Create RGB image data")
    func createRGBImageData() throws {
        let red = [[255, 200], [150, 100]]
        let green = [[100, 150], [200, 255]]
        let blue = [[50, 75], [100, 125]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        #expect(imageData.components.count == 3)
        #expect(imageData.components[0].id == 1)
        #expect(imageData.components[1].id == 2)
        #expect(imageData.components[2].id == 3)
        #expect(imageData.frameHeader.width == 2)
        #expect(imageData.frameHeader.height == 2)
        #expect(imageData.frameHeader.componentCount == 3)
    }
    
    @Test("Validate component count mismatch")
    func validateComponentCountMismatch() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        
        let components = [
            MultiComponentImageData.ComponentData(id: 1, pixels: [[1, 2], [3, 4]])
        ]
        
        #expect(throws: JPEGLSError.self) {
            try MultiComponentImageData(components: components, frameHeader: frameHeader)
        }
    }
    
    @Test("Validate invalid component ID")
    func validateInvalidComponentID() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        
        let components = [
            MultiComponentImageData.ComponentData(id: 99, pixels: [[1, 2], [3, 4]])
        ]
        
        #expect(throws: JPEGLSError.self) {
            try MultiComponentImageData(components: components, frameHeader: frameHeader)
        }
    }
    
    @Test("Validate dimension mismatch")
    func validateDimensionMismatch() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 3,
            height: 2
        )
        
        let components = [
            MultiComponentImageData.ComponentData(id: 1, pixels: [[1, 2], [3, 4]])
        ]
        
        #expect(throws: JPEGLSError.self) {
            try MultiComponentImageData(components: components, frameHeader: frameHeader)
        }
    }
    
    @Test("Validate pixel value out of range")
    func validatePixelValueOutOfRange() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        
        let components = [
            MultiComponentImageData.ComponentData(id: 1, pixels: [[1, 256], [3, 4]])
        ]
        
        #expect(throws: JPEGLSError.self) {
            try MultiComponentImageData(components: components, frameHeader: frameHeader)
        }
    }
    
    // MARK: - Pixel Buffer Tests
    
    @Test("Get neighbors for first pixel")
    func getNeighborsFirstPixel() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let neighbors = buffer.getNeighbors(componentId: 1, row: 0, column: 0)
        
        #expect(neighbors != nil)
        #expect(neighbors?.actual == 10)
        #expect(neighbors?.left == 0)
        #expect(neighbors?.top == 0)
        #expect(neighbors?.topLeft == 0)
        #expect(neighbors?.topRight == 0)
    }
    
    @Test("Get neighbors for first row, not first column")
    func getNeighborsFirstRow() throws {
        let pixels = [[10, 20, 30], [40, 50, 60]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let neighbors = buffer.getNeighbors(componentId: 1, row: 0, column: 1)
        
        #expect(neighbors != nil)
        #expect(neighbors?.actual == 20)
        #expect(neighbors?.left == 10)
        #expect(neighbors?.top == 10)  // Uses left pixel
        #expect(neighbors?.topLeft == 10)  // Uses left pixel
        #expect(neighbors?.topRight == 10)  // Uses left pixel
    }
    
    @Test("Get neighbors for first column, not first row")
    func getNeighborsFirstColumn() throws {
        let pixels = [[10, 20, 30], [40, 50, 60]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let neighbors = buffer.getNeighbors(componentId: 1, row: 1, column: 0)
        
        #expect(neighbors != nil)
        #expect(neighbors?.actual == 40)
        #expect(neighbors?.left == 10)  // Uses top pixel
        #expect(neighbors?.top == 10)
        #expect(neighbors?.topLeft == 10)  // Uses top pixel
        #expect(neighbors?.topRight == 20)
    }
    
    @Test("Get neighbors for general case")
    func getNeighborsGeneralCase() throws {
        let pixels = [
            [10, 20, 30],
            [40, 50, 60],
            [70, 80, 90]
        ]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Get neighbors for pixel at (1, 1) = 50
        let neighbors = buffer.getNeighbors(componentId: 1, row: 1, column: 1)
        
        #expect(neighbors != nil)
        #expect(neighbors?.actual == 50)
        #expect(neighbors?.left == 40)     // Left of 50
        #expect(neighbors?.top == 20)      // Top of 50
        #expect(neighbors?.topLeft == 10)  // Top-left of 50
        #expect(neighbors?.topRight == 30) // Top-right of 50
    }
    
    @Test("Get neighbors at right edge")
    func getNeighborsRightEdge() throws {
        let pixels = [
            [10, 20, 30],
            [40, 50, 60]
        ]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Get neighbors for pixel at (1, 2) = 60 (right edge)
        let neighbors = buffer.getNeighbors(componentId: 1, row: 1, column: 2)
        
        #expect(neighbors != nil)
        #expect(neighbors?.actual == 60)
        #expect(neighbors?.left == 50)
        #expect(neighbors?.top == 30)
        #expect(neighbors?.topLeft == 20)
        #expect(neighbors?.topRight == 30)  // Uses top pixel at right edge
    }
    
    @Test("Get neighbors for invalid position")
    func getNeighborsInvalidPosition() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let neighbors = buffer.getNeighbors(componentId: 1, row: 5, column: 5)
        #expect(neighbors == nil)
    }
    
    @Test("Get neighbors for invalid component")
    func getNeighborsInvalidComponent() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let neighbors = buffer.getNeighbors(componentId: 99, row: 0, column: 0)
        #expect(neighbors == nil)
    }
    
    @Test("Get pixel value")
    func getPixelValue() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 0) == 10)
        #expect(buffer.getPixel(componentId: 1, row: 0, column: 1) == 20)
        #expect(buffer.getPixel(componentId: 1, row: 1, column: 0) == 30)
        #expect(buffer.getPixel(componentId: 1, row: 1, column: 1) == 40)
    }
    
    @Test("Get component pixels")
    func getComponentPixels() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let componentPixels = buffer.getComponentPixels(componentId: 1)
        #expect(componentPixels != nil)
        #expect(componentPixels == pixels)
    }
    
    @Test("Get neighbors for multi-component image")
    func getNeighborsMultiComponent() throws {
        let red = [[255, 200], [150, 100]]
        let green = [[100, 150], [200, 255]]
        let blue = [[50, 75], [100, 125]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Check red component neighbors
        let redNeighbors = buffer.getNeighbors(componentId: 1, row: 1, column: 1)
        #expect(redNeighbors?.actual == 100)
        #expect(redNeighbors?.left == 150)
        #expect(redNeighbors?.top == 200)
        #expect(redNeighbors?.topLeft == 255)
        
        // Check green component neighbors
        let greenNeighbors = buffer.getNeighbors(componentId: 2, row: 1, column: 1)
        #expect(greenNeighbors?.actual == 255)
        #expect(greenNeighbors?.left == 200)
        #expect(greenNeighbors?.top == 150)
        #expect(greenNeighbors?.topLeft == 100)
        
        // Check blue component neighbors
        let blueNeighbors = buffer.getNeighbors(componentId: 3, row: 1, column: 1)
        #expect(blueNeighbors?.actual == 125)
        #expect(blueNeighbors?.left == 100)
        #expect(blueNeighbors?.top == 75)
        #expect(blueNeighbors?.topLeft == 50)
    }
    
    @Test("Buffer dimensions")
    func bufferDimensions() throws {
        let pixels = [[1, 2, 3, 4], [5, 6, 7, 8]]
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        #expect(buffer.width == 4)
        #expect(buffer.height == 2)
    }
}
