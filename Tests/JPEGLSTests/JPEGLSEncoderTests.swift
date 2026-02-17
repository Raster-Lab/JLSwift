/// Tests for JPEG-LS high-level encoder API

import Testing
@testable import JPEGLS

@Suite("JPEGLS Encoder Tests")
struct JPEGLSEncoderTests {
    
    @Test("Encode simple 2x2 grayscale image")
    func testEncodeSimpleGrayscale() throws {
        // Create a simple 2x2 grayscale image
        let pixels: [[Int]] = [
            [100, 110],
            [105, 115]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        
        // Verify we got some data
        #expect(jpegLSData.count > 0)
        
        // Verify JPEG-LS markers are present
        // SOI marker: 0xFF 0xD8
        #expect(jpegLSData[0] == 0xFF)
        #expect(jpegLSData[1] == 0xD8)
        
        // EOI marker should be at the end: 0xFF 0xD9
        #expect(jpegLSData[jpegLSData.count - 2] == 0xFF)
        #expect(jpegLSData[jpegLSData.count - 1] == 0xD9)
    }
    
    @Test("Encode 4x4 grayscale image lossless")
    func testEncode4x4Lossless() throws {
        // Create a 4x4 grayscale image with varying intensities
        let pixels: [[Int]] = [
            [0, 10, 20, 30],
            [40, 50, 60, 70],
            [80, 90, 100, 110],
            [120, 130, 140, 150]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        
        // Verify we got data
        #expect(jpegLSData.count > 0)
        
        // Verify file structure: should start with SOI (0xFF 0xD8)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
        
        // Should end with EOI (0xFF 0xD9)
        #expect(jpegLSData.suffix(2).elementsEqual([0xFF, 0xD9]))
    }
    
    @Test("Encode flat region (all same values)")
    func testEncodeFlatRegion() throws {
        // Create a flat 4x4 image (all pixels same value)
        let pixels: [[Int]] = [
            [128, 128, 128, 128],
            [128, 128, 128, 128],
            [128, 128, 128, 128],
            [128, 128, 128, 128]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        
        // Flat regions should compress very well
        #expect(jpegLSData.count > 0)
        
        // Should be much smaller than uncompressed (4x4 = 16 bytes uncompressed)
        // Even with headers, should be relatively small
        #expect(jpegLSData.count < 100)  // Generous upper bound
    }
    
    @Test("Encode with near-lossless mode")
    func testEncodeNearLossless() throws {
        let pixels: [[Int]] = [
            [100, 102, 104, 106],
            [101, 103, 105, 107],
            [100, 102, 104, 106],
            [101, 103, 105, 107]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        // Near-lossless with NEAR=3
        let jpegLSData = try encoder.encode(imageData, near: 3, interleaveMode: .none)
        
        #expect(jpegLSData.count > 0)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
        #expect(jpegLSData.suffix(2).elementsEqual([0xFF, 0xD9]))
    }
    
    @Test("Encode configuration with custom parameters")
    func testEncodeWithConfiguration() throws {
        let pixels: [[Int]] = [
            [50, 55],
            [52, 57]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .none,
            presetParameters: nil
        )
        
        let jpegLSData = try encoder.encode(imageData, configuration: config)
        
        #expect(jpegLSData.count > 0)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
    }
    
    @Test("Encode different bit depths")
    func testEncodeDifferentBitDepths() throws {
        // 12-bit grayscale image
        let pixels12bit: [[Int]] = [
            [0, 1024, 2048, 3072],
            [1000, 2000, 3000, 4000]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels12bit,
            bitsPerSample: 12
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        
        #expect(jpegLSData.count > 0)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
    }
    
    @Test("Encode RGB image with sample interleaving")
    func testEncodeRGBSampleInterleaved() throws {
        // Small 2x2 RGB image
        let redPixels: [[Int]] = [
            [255, 200],
            [180, 220]
        ]
        let greenPixels: [[Int]] = [
            [100, 150],
            [120, 140]
        ]
        let bluePixels: [[Int]] = [
            [50, 80],
            [60, 90]
        ]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: redPixels,
            greenPixels: greenPixels,
            bluePixels: bluePixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .sample)
        
        #expect(jpegLSData.count > 0)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
        #expect(jpegLSData.suffix(2).elementsEqual([0xFF, 0xD9]))
    }
    
    @Test("Encode RGB image with line interleaving")
    func testEncodeRGBLineInterleaved() throws {
        // Small 2x2 RGB image
        let redPixels: [[Int]] = [
            [100, 110],
            [105, 115]
        ]
        let greenPixels: [[Int]] = [
            [150, 160],
            [155, 165]
        ]
        let bluePixels: [[Int]] = [
            [200, 210],
            [205, 215]
        ]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: redPixels,
            greenPixels: greenPixels,
            bluePixels: bluePixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData, near: 0, interleaveMode: .line)
        
        #expect(jpegLSData.count > 0)
        #expect(jpegLSData.starts(with: [0xFF, 0xD8]))
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNEARParameter() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(near: 256)  // NEAR must be 0-255
        }
        
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(near: -1)  // NEAR must be non-negative
        }
    }
}
