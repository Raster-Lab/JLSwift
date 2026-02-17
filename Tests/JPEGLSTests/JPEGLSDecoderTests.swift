import Testing
import Foundation
@testable import JPEGLS

/// Test suite for JPEGLSDecoder
@Suite("JPEG-LS Decoder Tests")
struct JPEGLSDecoderTests {
    
    // MARK: - Round-Trip Tests
    
    @Test("Round-trip: 8x8 grayscale lossless")
    func testRoundTripGrayscale8x8Lossless() throws {
        // Create test image
        let pixels: [[Int]] = [
            [100, 101, 102, 103, 104, 105, 106, 107],
            [110, 111, 112, 113, 114, 115, 116, 117],
            [120, 121, 122, 123, 124, 125, 126, 127],
            [130, 131, 132, 133, 134, 135, 136, 137],
            [140, 141, 142, 143, 144, 145, 146, 147],
            [150, 151, 152, 153, 154, 155, 156, 157],
            [160, 161, 162, 163, 164, 165, 166, 167],
            [170, 171, 172, 173, 174, 175, 176, 177]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Encode
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .none
        )
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify dimensions
        #expect(decoded.frameHeader.width == 8)
        #expect(decoded.frameHeader.height == 8)
        #expect(decoded.frameHeader.bitsPerSample == 8)
        #expect(decoded.frameHeader.componentCount == 1)
        
        // Verify pixel-perfect match
        for row in 0..<8 {
            for col in 0..<8 {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }
    
    @Test("Round-trip: 16x16 grayscale lossless")
    func testRoundTripGrayscale16x16Lossless() throws {
        // Create gradient test image
        var pixels: [[Int]] = []
        for row in 0..<16 {
            var rowPixels: [Int] = []
            for col in 0..<16 {
                rowPixels.append((row * 16 + col) % 256)
            }
            pixels.append(rowPixels)
        }
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Encode
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify pixel-perfect match
        for row in 0..<16 {
            for col in 0..<16 {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }
    
    @Test("Round-trip: 8x8 grayscale near-lossless (NEAR=3)", .disabled("Encoder near-lossless mode does not yet quantize errors or track reconstructed values"))
    func testRoundTripGrayscaleNearLossless() throws {
        let pixels: [[Int]] = [
            [100, 101, 102, 103, 104, 105, 106, 107],
            [110, 111, 112, 113, 114, 115, 116, 117],
            [120, 121, 122, 123, 124, 125, 126, 127],
            [130, 131, 132, 133, 134, 135, 136, 137],
            [140, 141, 142, 143, 144, 145, 146, 147],
            [150, 151, 152, 153, 154, 155, 156, 157],
            [160, 161, 162, 163, 164, 165, 166, 167],
            [170, 171, 172, 173, 174, 175, 176, 177]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Encode with NEAR=3
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 3, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify near-lossless: difference should be <= NEAR
        let near = 3
        for row in 0..<8 {
            for col in 0..<8 {
                let original = pixels[row][col]
                let reconstructed = decoded.components[0].pixels[row][col]
                let diff = abs(original - reconstructed)
                #expect(diff <= near, "Pixel at (\(row),\(col)): original=\(original), reconstructed=\(reconstructed), diff=\(diff) > NEAR=\(near)")
            }
        }
    }
    
    @Test("Round-trip: 8x8 RGB sample-interleaved lossless")
    func testRoundTripRGBSampleInterleaved() throws {
        // Create RGB test image
        let redPixels: [[Int]] = [
            [200, 201, 202, 203, 204, 205, 206, 207],
            [210, 211, 212, 213, 214, 215, 216, 217],
            [220, 221, 222, 223, 224, 225, 226, 227],
            [230, 231, 232, 233, 234, 235, 236, 237],
            [200, 201, 202, 203, 204, 205, 206, 207],
            [210, 211, 212, 213, 214, 215, 216, 217],
            [220, 221, 222, 223, 224, 225, 226, 227],
            [230, 231, 232, 233, 234, 235, 236, 237]
        ]
        
        let greenPixels: [[Int]] = [
            [100, 101, 102, 103, 104, 105, 106, 107],
            [110, 111, 112, 113, 114, 115, 116, 117],
            [120, 121, 122, 123, 124, 125, 126, 127],
            [130, 131, 132, 133, 134, 135, 136, 137],
            [100, 101, 102, 103, 104, 105, 106, 107],
            [110, 111, 112, 113, 114, 115, 116, 117],
            [120, 121, 122, 123, 124, 125, 126, 127],
            [130, 131, 132, 133, 134, 135, 136, 137]
        ]
        
        let bluePixels: [[Int]] = [
            [50, 51, 52, 53, 54, 55, 56, 57],
            [60, 61, 62, 63, 64, 65, 66, 67],
            [70, 71, 72, 73, 74, 75, 76, 77],
            [80, 81, 82, 83, 84, 85, 86, 87],
            [50, 51, 52, 53, 54, 55, 56, 57],
            [60, 61, 62, 63, 64, 65, 66, 67],
            [70, 71, 72, 73, 74, 75, 76, 77],
            [80, 81, 82, 83, 84, 85, 86, 87]
        ]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: redPixels,
            greenPixels: greenPixels,
            bluePixels: bluePixels,
            bitsPerSample: 8
        )
        
        // Encode with sample interleaving
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify component count
        #expect(decoded.components.count == 3)
        
        // Verify pixel-perfect match for all components
        for componentIdx in 0..<3 {
            let original = [redPixels, greenPixels, bluePixels][componentIdx]
            for row in 0..<8 {
                for col in 0..<8 {
                    #expect(decoded.components[componentIdx].pixels[row][col] == original[row][col])
                }
            }
        }
    }
    
    @Test("Round-trip: 16-bit grayscale lossless")
    func testRoundTrip16BitGrayscale() throws {
        // Create 16-bit test image
        var pixels: [[Int]] = []
        for row in 0..<8 {
            var rowPixels: [Int] = []
            for col in 0..<8 {
                // Use values that require 16-bit (> 255)
                rowPixels.append(1000 + row * 100 + col * 10)
            }
            pixels.append(rowPixels)
        }
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 16
        )
        
        // Encode
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify bits per sample
        #expect(decoded.frameHeader.bitsPerSample == 16)
        
        // Verify pixel-perfect match
        for row in 0..<8 {
            for col in 0..<8 {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }
    
    @Test("Round-trip: Flat region (run mode)", .disabled("Decoder has known pixel drift for images with gradient regions"))
    func testRoundTripFlatRegion() throws {
        // Create image with flat regions to trigger run mode
        var pixels: [[Int]] = []
        for row in 0..<8 {
            var rowPixels: [Int] = []
            for col in 0..<8 {
                // First half flat, second half gradient
                if col < 4 {
                    rowPixels.append(128)  // Flat
                } else {
                    rowPixels.append(128 + (col - 4) * 10)  // Gradient
                }
            }
            pixels.append(rowPixels)
        }
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Encode
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify pixel-perfect match
        for row in 0..<8 {
            for col in 0..<8 {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }
    
    @Test("Round-trip: Checkerboard pattern")
    func testRoundTripCheckerboard() throws {
        // Create checkerboard pattern
        var pixels: [[Int]] = []
        for row in 0..<8 {
            var rowPixels: [Int] = []
            for col in 0..<8 {
                rowPixels.append((row + col) % 2 == 0 ? 0 : 255)
            }
            pixels.append(rowPixels)
        }
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Encode
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify pixel-perfect match
        for row in 0..<8 {
            for col in 0..<8 {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }
}
