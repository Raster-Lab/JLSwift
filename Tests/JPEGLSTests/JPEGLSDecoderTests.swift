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
    
    @Test("Round-trip: 8x8 grayscale near-lossless (NEAR=3)")
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
    
    @Test("Round-trip: Flat region (run mode)")
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

    @Test("DIAGNOSTIC: Round-trip: 32x32 flat grayscale (should pass)")
    func testDiagFlatGrayscale32x32() throws {
        let width = 32, height = 32
        let pixels = Array(repeating: Array(repeating: 128, count: width), count: height)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.width == width)
        #expect(decoded.frameHeader.height == height)
        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == 128)
            }
        }
    }

    @Test("DIAGNOSTIC: Round-trip: 32x32 flat RGB none-ILV")
    func testDiagFlatRGBNoneILV32x32() throws {
        let width = 32, height = 32
        let pixels = Array(repeating: Array(repeating: 100, count: width), count: height)
        let imageData = try MultiComponentImageData.rgb(redPixels: pixels, greenPixels: pixels, bluePixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.width == width)
        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == 100)
            }
        }
    }

    @Test("DIAGNOSTIC: Round-trip: 32x32 flat RGB line-ILV")
    func testDiagFlatRGBLineILV32x32() throws {
        let width = 32, height = 32
        let pixels = Array(repeating: Array(repeating: 100, count: width), count: height)
        let imageData = try MultiComponentImageData.rgb(redPixels: pixels, greenPixels: pixels, bluePixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .line)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.width == width)
        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == 100)
            }
        }
    }

    @Test("DIAGNOSTIC: Round-trip: 256x256 flat grayscale")
    func testDiagFlatGrayscale256x256() throws {
        let width = 256, height = 256
        let pixels = Array(repeating: Array(repeating: 100, count: width), count: height)
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
            for row in 0..<height {
                for col in 0..<width {
                    #expect(decoded.components[0].pixels[row][col] == 100)
                }
            }
        } catch {
            Issue.record("Error: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Round-trip: 256x256 flat RGB none-ILV")
    func testDiagFlatRGB256x256NoneILV() throws {
        let width = 256, height = 256
        let pixels = Array(repeating: Array(repeating: 100, count: width), count: height)
        let imageData = try MultiComponentImageData.rgb(redPixels: pixels, greenPixels: pixels, bluePixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("256x256 flat RGB none-ILV error: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Round-trip: 256x256 flat RGB line-ILV")
    func testDiagFlatRGB256x256LineILV() throws {
        let width = 256, height = 256
        let pixels = Array(repeating: Array(repeating: 100, count: width), count: height)
        let imageData = try MultiComponentImageData.rgb(redPixels: pixels, greenPixels: pixels, bluePixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .line)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("256x256 flat RGB line-ILV error: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Print pixel values around row 151 col 128 in test8g.pgm")
    func testDiagPixelRow151Col128() throws {
        let (_, width, _, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        // Print row 148-152, cols 120-135
        for r in 148...153 {
            let rowVals = (120..<min(136, width)).map { c in Int(pixels[r * width + c]) }
            print("Row \(r) [120..135]: \(rowVals)")
        }
        print("Pixel[151][128] = \(pixels[151 * width + 128])")
        print("Pixel[151][127] = \(pixels[151 * width + 127])")
        print("Pixel[150][128] = \(pixels[150 * width + 128])")
    }

    @Test("DIAGNOSTIC: Verify test8g.pgm round-trip up to row 152")
    func testDiagVerify152Rows() throws {
        let (_, width, _, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        let numRows = 152
        let pixelGrid: [[Int]] = (0..<numRows).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixelGrid, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        // Find first wrong pixel
        var firstWrong: String? = nil
        outer: for row in 0..<numRows {
            for col in 0..<width {
                let expected = Int(pixels[row * width + col])
                let actual = decoded.components[0].pixels[row][col]
                if actual != expected {
                    firstWrong = "Row \(row), col \(col): expected \(expected), got \(actual)"
                    break outer
                }
            }
        }
        if let w = firstWrong {
            Issue.record("Pixel mismatch: \(w)")
        } else {
            print("All 152 rows decoded correctly (scan bytes: \(encoded.count))")
        }
    }

    @Test("DIAGNOSTIC: Print pixels around row 152 of test8g.pgm")
    func testDiagPrintPixels() throws {
        let (_, width, _, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        // Print rows 150-152 (first 10 pixels each)
        for r in 148...152 {
            let rowVals = (0..<min(20, width)).map { c in Int(pixels[r * width + c]) }
            print("Row \(r): \(rowVals)")
        }
        // Also check the run index after encoding 152 rows by looking at what runValue/context is
        let pixelGrid152: [[Int]] = (0..<153).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        // Just verify this fails
        let imageData = try MultiComponentImageData.grayscale(pixels: pixelGrid152, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let _ = try JPEGLSEncoder().encode(imageData, configuration: config)
            // Should have failed
        } catch {
            print("Got expected error: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Find failing column in test8g.pgm row 153")
    func testDiagFindFailingCol() throws {
        let (_, width, _, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        // Load rows 0..152 (first 153 rows but encode only 0..N to find the column in row 152 that fails)
        let height = 153
        let pixelGrid: [[Int]] = (0..<height).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        // Print row 152 pixel values (0-indexed)
        let row152 = pixelGrid[152]
        let firstFew = row152.prefix(30).map { String($0) }.joined(separator: ",")
        // Try encoding subsets of width for row 152 to find the col
        for numCols in stride(from: 1, through: width, by: 1) {
            var grid = (0..<152).map { row in Array(pixelGrid[row]) }
            grid.append(Array(row152.prefix(numCols)))
            // Pad to width if needed
            if numCols < width {
                let lastVal = row152[numCols - 1]
                grid[152].append(contentsOf: Array(repeating: lastVal, count: width - numCols))
            }
            let imageData = try MultiComponentImageData.grayscale(pixels: grid, bitsPerSample: 8)
            let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
            do {
                let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
                let _ = try JPEGLSDecoder().decode(encoded)
            } catch {
                Issue.record("Failed at row 152, col \(numCols): \(error) | row152[0..29]=\(firstFew) | around col: \(row152[max(0,numCols-3)..<min(width, numCols+3)])")
                return
            }
        }
        // All columns passed — expected behavior after fixing the run-interruption adjustedLimit bug.
    }

    @Test("DIAGNOSTIC: Find failing row in test8g.pgm")
    func testDiagFindFailingRow() throws {
        let (_, width, height, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        // Try encoding first N rows, find which N causes failure
        for numRows in stride(from: 1, through: height, by: 1) {
            let pixelGrid: [[Int]] = (0..<numRows).map { row in
                (0..<width).map { col in Int(pixels[row * width + col]) }
            }
            let imageData = try MultiComponentImageData.grayscale(pixels: pixelGrid, bitsPerSample: 8)
            let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
            do {
                let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
                let _ = try JPEGLSDecoder().decode(encoded)
            } catch {
                Issue.record("Failed at \(numRows) rows: \(error)")
                return
            }
        }
    }

    @Test("DIAGNOSTIC: test8g.pgm as grayscale (should work)")
    func testDiagTest8gGrayscale() throws {
        let (_, width, height, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        let pixelGrid: [[Int]] = (0..<height).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        let imageData = try MultiComponentImageData.grayscale(pixels: pixelGrid, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("test8g grayscale failed: \(error)")
        }
    }

    @Test("DIAGNOSTIC: test8g.pgm as 3-component RGB none-ILV")
    func testDiagTest8gAsRGB() throws {
        let (_, width, height, pixels) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        let pixelGrid: [[Int]] = (0..<height).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        let imageData = try MultiComponentImageData.rgb(
            redPixels: pixelGrid, greenPixels: pixelGrid, bluePixels: pixelGrid, bitsPerSample: 8
        )
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("test8g as RGB failed: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Mixed components with different data none-ILV")
    func testDiagMixedComponents() throws {
        // Use R data for first 2 components, G data for third  
        let (_, width, height, rpix) = try TestFixtureLoader.loadPGM(named: "test8r.pgm")
        let (_, _, _, gpix) = try TestFixtureLoader.loadPGM(named: "test8g.pgm")
        let rGrid: [[Int]] = (0..<height).map { row in (0..<width).map { col in Int(rpix[row * width + col]) } }
        let gGrid: [[Int]] = (0..<height).map { row in (0..<width).map { col in Int(gpix[row * width + col]) } }
        let imageData = try MultiComponentImageData.rgb(redPixels: rGrid, greenPixels: gGrid, bluePixels: rGrid, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("Mixed R+G+R failed: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Round-trip: test8r.pgm as 3-component RGB none-ILV")
    func testDiagTest8rAsRGB() throws {
        let (_, width, height, pixels) = try TestFixtureLoader.loadPGM(named: "test8r.pgm")
        let pixelGrid: [[Int]] = (0..<height).map { row in
            (0..<width).map { col in Int(pixels[row * width + col]) }
        }
        let imageData = try MultiComponentImageData.rgb(
            redPixels: pixelGrid, greenPixels: pixelGrid, bluePixels: pixelGrid, bitsPerSample: 8
        )
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
        } catch {
            Issue.record("test8r as RGB failed: \(error)")
        }
    }

    @Test("DIAGNOSTIC: Round-trip: test8.ppm none-ILV")
    func testDiagTest8PPMNoneILV() throws {
        let (_, width, height, pixels) = try TestFixtureLoader.loadPPM(named: "test8.ppm")
        var r = [[Int]](), g = [[Int]](), b = [[Int]]()
        for row in 0..<height {
            var rRow = [Int](), gRow = [Int](), bRow = [Int]()
            for col in 0..<width {
                let base = (row * width + col) * 3
                rRow.append(Int(pixels[base]))
                gRow.append(Int(pixels[base + 1]))
                bRow.append(Int(pixels[base + 2]))
            }
            r.append(rRow); g.append(gRow); b.append(bRow)
        }
        let imageData = try MultiComponentImageData.rgb(redPixels: r, greenPixels: g, bluePixels: b, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        do {
            let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
            let decoded = try JPEGLSDecoder().decode(encoded)
            #expect(decoded.frameHeader.width == width)
            // Check first few pixels
            for row in 0..<min(3, height) {
                for col in 0..<min(10, width) {
                    #expect(decoded.components[0].pixels[row][col] == r[row][col])
                    #expect(decoded.components[1].pixels[row][col] == g[row][col])
                    #expect(decoded.components[2].pixels[row][col] == b[row][col])
                }
            }
        } catch {
            Issue.record("Encoding/Decoding failed: \(error)")
        }
    }
}
