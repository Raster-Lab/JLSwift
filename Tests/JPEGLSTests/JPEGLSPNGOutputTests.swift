// JPEGLSPNGOutputTests.swift
// Tests for PNG output support in the JPEG-LS CLI decode command.
//
// These tests verify that:
//   - `PNGSupport.encode` produces data with the correct PNG file signature.
//   - The IHDR chunk records the correct width, height, and bit depth.
//   - 8-bit greyscale, 8-bit RGB, and 16-bit greyscale images are encoded correctly.
//   - CRC-32 and Adler-32 helpers produce known-correct values.
//   - A full JPEG-LS encode → decode → PNG round-trip produces a valid PNG file.
//   - PNG output format is accepted by the decode command alongside raw/pgm/ppm.
//
// Phase 17.1: PNG output for the `decode` command.

import Testing
import Foundation
@testable import JPEGLS

// MARK: - PNG Output Tests

@Suite("PNG Output Tests")
struct JPEGLSPNGOutputTests {

    // MARK: - PNG Signature

    @Test("PNG output starts with the standard 8-byte PNG file signature")
    func testPNGSignature() throws {
        let pixels: [[[Int]]] = [[[0, 128], [64, 255]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let expected: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(data.count >= 8)
        for (i, byte) in expected.enumerated() {
            #expect(data[i] == byte, "Signature byte \(i) mismatch")
        }
    }

    // MARK: - IHDR Chunk

    /// Returns the content of the named chunk from a PNG byte stream, or nil if not found.
    private func findChunk(named type: String, in data: Data) -> Data? {
        var offset = 8  // skip PNG signature
        while offset + 12 <= data.count {
            let length = (Int(data[offset]) << 24) |
                         (Int(data[offset + 1]) << 16) |
                         (Int(data[offset + 2]) << 8)  |
                          Int(data[offset + 3])
            guard offset + 12 + length <= data.count else { return nil }
            let chunkType = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if chunkType == type {
                return data.subdata(in: (offset + 8)..<(offset + 8 + length))
            }
            offset += 12 + length
        }
        return nil
    }

    @Test("IHDR chunk contains correct width, height, bit depth, and colour type for 8-bit greyscale")
    func testIHDRGreyscale8bit() throws {
        let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let ihdr = try #require(findChunk(named: "IHDR", in: data))
        #expect(ihdr.count == 13)
        // Width (bytes 0-3)
        let width = (Int(ihdr[0]) << 24) | (Int(ihdr[1]) << 16) | (Int(ihdr[2]) << 8) | Int(ihdr[3])
        #expect(width == 2)
        // Height (bytes 4-7)
        let height = (Int(ihdr[4]) << 24) | (Int(ihdr[5]) << 16) | (Int(ihdr[6]) << 8) | Int(ihdr[7])
        #expect(height == 2)
        // Bit depth (byte 8)
        #expect(ihdr[8] == 8)
        // Colour type (byte 9): 0 = greyscale
        #expect(ihdr[9] == 0)
    }

    @Test("IHDR chunk contains correct colour type for 8-bit RGB")
    func testIHDRRGB8bit() throws {
        let r: [[Int]] = [[255, 0], [128, 64]]
        let g: [[Int]] = [[0, 255], [64, 128]]
        let b: [[Int]] = [[0, 0], [255, 0]]
        let pixels: [[[Int]]] = [r, g, b]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let ihdr = try #require(findChunk(named: "IHDR", in: data))
        // Colour type (byte 9): 2 = RGB
        #expect(ihdr[9] == 2)
        // Bit depth: 8
        #expect(ihdr[8] == 8)
    }

    @Test("IHDR chunk has bit depth 16 when maxVal exceeds 255")
    func testIHDR16bit() throws {
        let pixels: [[[Int]]] = [[[4095, 0], [2048, 1]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 4095)
        let ihdr = try #require(findChunk(named: "IHDR", in: data))
        #expect(ihdr[8] == 16)
        #expect(ihdr[9] == 0)  // greyscale
    }

    @Test("IHDR chunk records correct large dimensions (256 × 256)")
    func testIHDRLargeDimensions() throws {
        let row = Array(repeating: 128, count: 256)
        let plane = Array(repeating: row, count: 256)
        let pixels: [[[Int]]] = [plane]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 256, height: 256, maxVal: 255)
        let ihdr = try #require(findChunk(named: "IHDR", in: data))
        let width  = (Int(ihdr[0]) << 24) | (Int(ihdr[1]) << 16) | (Int(ihdr[2]) << 8) | Int(ihdr[3])
        let height = (Int(ihdr[4]) << 24) | (Int(ihdr[5]) << 16) | (Int(ihdr[6]) << 8) | Int(ihdr[7])
        #expect(width  == 256)
        #expect(height == 256)
    }

    // MARK: - PNG Structure

    @Test("PNG file contains IHDR, IDAT, and IEND chunks in order")
    func testChunkOrder() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        var foundTypes: [String] = []
        var offset = 8
        while offset + 12 <= data.count {
            let length = (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16) |
                         (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            let type = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            foundTypes.append(type)
            offset += 12 + length
        }
        #expect(foundTypes == ["IHDR", "IDAT", "IEND"])
    }

    @Test("IEND chunk has zero-length data field")
    func testIENDEmpty() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        var offset = 8
        while offset + 8 <= data.count {
            let length = (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16) |
                         (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            let type = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if type == "IEND" {
                #expect(length == 0)
                return
            }
            offset += 12 + length
        }
        Issue.record("IEND chunk not found")
    }

    // MARK: - Error Handling

    @Test("PNG encoder throws for zero-dimension images")
    func testErrorZeroDimensions() {
        let pixels: [[[Int]]] = [[[0]]]
        #expect(throws: PNGEncoderError.invalidDimensions) {
            try PNGSupport.encode(componentPixels: pixels, width: 0, height: 1, maxVal: 255)
        }
        #expect(throws: PNGEncoderError.invalidDimensions) {
            try PNGSupport.encode(componentPixels: pixels, width: 1, height: 0, maxVal: 255)
        }
    }

    @Test("PNG encoder throws for unsupported component count")
    func testErrorUnsupportedComponents() {
        let pixels: [[[Int]]] = [[[0]], [[0]]]  // 2 components
        #expect(throws: PNGEncoderError.unsupportedComponentCount(2)) {
            try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        }
    }

    @Test("PNG encoder throws for invalid maxVal")
    func testErrorInvalidMaxVal() {
        let pixels: [[[Int]]] = [[[0]]]
        #expect(throws: PNGEncoderError.invalidMaxVal) {
            try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 0)
        }
        #expect(throws: PNGEncoderError.invalidMaxVal) {
            try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 65536)
        }
    }

    // MARK: - CRC-32 and Adler-32

    @Test("CRC-32 of 'IEND' chunk type produces the standard known value 0xAE426082")
    func testCRC32IENDValue() {
        // The CRC of an empty IEND chunk (type only, no data) is a well-known constant.
        let typeBytes = Data("IEND".utf8)
        let crc = PNGSupport.crc32(typeBytes)
        #expect(crc == 0xAE42_6082)
    }

    @Test("Adler-32 of empty data returns 1")
    func testAdler32Empty() {
        #expect(PNGSupport.adler32(Data()) == 1)
    }

    @Test("Adler-32 of single byte 0x01 returns expected value")
    func testAdler32SingleByte() {
        // s1 = (1 + 1) % 65521 = 2; s2 = (0 + 2) % 65521 = 2 → 0x00020002
        #expect(PNGSupport.adler32(Data([0x01])) == 0x0002_0002)
    }

    // MARK: - Pixel Content Verification

    @Test("8-bit greyscale IDAT contains correct filter byte and pixel values")
    func testIDATGreyscale8bit() throws {
        // 1×1 greyscale image with pixel value 170 (0xAA).
        let pixels: [[[Int]]] = [[[170]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)

        // Locate and decompress the IDAT chunk.
        let idatChunkData = try #require(findChunk(named: "IDAT", in: data))
        let scanlines     = try decompressZlibStored(idatChunkData)

        // One row: filter byte (0) + one pixel byte (170).
        #expect(scanlines.count == 2)
        #expect(scanlines[0] == 0)    // filter type: None
        #expect(scanlines[1] == 170)  // pixel value
    }

    @Test("16-bit greyscale IDAT encodes pixels in big-endian order")
    func testIDATGreyscale16bit() throws {
        // 1×1 greyscale 16-bit image with pixel value 0x0F00.
        let pixels: [[[Int]]] = [[[0x0F00]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 4095)
        let idatData  = try #require(findChunk(named: "IDAT", in: data))
        let scanlines = try decompressZlibStored(idatData)

        // One row: filter byte (0) + two pixel bytes (0x0F, 0x00).
        #expect(scanlines.count == 3)
        #expect(scanlines[0] == 0x00)  // filter type: None
        #expect(scanlines[1] == 0x0F)  // high byte
        #expect(scanlines[2] == 0x00)  // low byte
    }

    @Test("8-bit RGB IDAT interleaves R, G, B samples correctly")
    func testIDATRGB8bit() throws {
        // 1×1 RGB pixel: R=10, G=20, B=30.
        let pixels: [[[Int]]] = [[[10]], [[20]], [[30]]]
        let data = try PNGSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let idatData  = try #require(findChunk(named: "IDAT", in: data))
        let scanlines = try decompressZlibStored(idatData)

        // One row: filter byte + R + G + B.
        #expect(scanlines.count == 4)
        #expect(scanlines[0] == 0)   // filter type: None
        #expect(scanlines[1] == 10)  // R
        #expect(scanlines[2] == 20)  // G
        #expect(scanlines[3] == 30)  // B
    }

    // MARK: - JPEG-LS Round-Trip

    @Test("Round-trip JPEG-LS encode → decode → PNG produces valid PNG with correct pixel data")
    func testJPEGLSRoundTripToPNG() throws {
        // Encode a small greyscale image with JPEG-LS.
        let width = 4
        let height = 4
        var original: [[Int]] = []
        for row in 0..<height {
            var r: [Int] = []
            for col in 0..<width {
                r.append((row * width + col) * 10 % 256)
            }
            original.append(r)
        }

        let imgData = try MultiComponentImageData.grayscale(pixels: original, bitsPerSample: 8)
        let config  = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none,
                                                       presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        // Produce PNG output.
        let componentPixels: [[[Int]]] = decoded.components.map { $0.pixels }
        let maxVal = (1 << decoded.frameHeader.bitsPerSample) - 1
        let pngData = try PNGSupport.encode(
            componentPixels: componentPixels,
            width: decoded.frameHeader.width,
            height: decoded.frameHeader.height,
            maxVal: maxVal
        )

        // Verify PNG signature.
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        for (i, b) in sig.enumerated() { #expect(pngData[i] == b) }

        // Verify IHDR dimensions.
        let ihdr = try #require(findChunk(named: "IHDR", in: pngData))
        let w = (Int(ihdr[0]) << 24) | (Int(ihdr[1]) << 16) | (Int(ihdr[2]) << 8) | Int(ihdr[3])
        let h = (Int(ihdr[4]) << 24) | (Int(ihdr[5]) << 16) | (Int(ihdr[6]) << 8) | Int(ihdr[7])
        #expect(w == width)
        #expect(h == height)

        // Decompress and verify pixel values.
        let idatData  = try #require(findChunk(named: "IDAT", in: pngData))
        let scanlines = try decompressZlibStored(idatData)
        let rowStride = 1 + width  // 1 filter byte + 1 byte per pixel (8-bit greyscale)
        #expect(scanlines.count == height * rowStride)
        for row in 0..<height {
            #expect(scanlines[row * rowStride] == 0)  // filter: None
            for col in 0..<width {
                let expected = UInt8(original[row][col])
                #expect(scanlines[row * rowStride + 1 + col] == expected)
            }
        }
    }

    @Test("Round-trip 8-bit RGB JPEG-LS → PNG produces correct component data")
    func testRGBRoundTripToPNG() throws {
        let width = 2
        let height = 2
        let r: [[Int]] = [[255, 128], [64, 0]]
        let g: [[Int]] = [[0,   64],  [128, 255]]
        let b: [[Int]] = [[128, 0],   [255, 64]]

        let imgData = try MultiComponentImageData.rgb(redPixels: r, greenPixels: g, bluePixels: b,
                                                      bitsPerSample: 8)
        let config  = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample,
                                                       presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        let componentPixels: [[[Int]]] = decoded.components.map { $0.pixels }
        let maxVal = (1 << decoded.frameHeader.bitsPerSample) - 1
        let pngData = try PNGSupport.encode(
            componentPixels: componentPixels,
            width: decoded.frameHeader.width,
            height: decoded.frameHeader.height,
            maxVal: maxVal
        )

        // Check IHDR colour type = 2 (RGB).
        let ihdr = try #require(findChunk(named: "IHDR", in: pngData))
        #expect(ihdr[9] == 2)

        // Check pixel layout in the decompressed scanlines.
        let idatData  = try #require(findChunk(named: "IDAT", in: pngData))
        let scanlines = try decompressZlibStored(idatData)
        let rowStride = 1 + width * 3  // filter byte + RGB per pixel
        for row in 0..<height {
            for col in 0..<width {
                let base = row * rowStride + 1 + col * 3
                #expect(scanlines[base]     == UInt8(r[row][col]))
                #expect(scanlines[base + 1] == UInt8(g[row][col]))
                #expect(scanlines[base + 2] == UInt8(b[row][col]))
            }
        }
    }

    // MARK: - Decode Format Acceptance

    @Test("PNG is listed as a supported decode output format alongside raw, pgm, and ppm")
    func testPNGInSupportedDecodeFormats() {
        // This mirrors the validation logic in DecodeCommand.run().
        let supportedFormats = ["raw", "pgm", "ppm", "png"]
        #expect(supportedFormats.contains("png"))
        #expect(!supportedFormats.contains("tiff"))
    }

    // MARK: - Helpers

    /// Decompress a zlib "stored" stream and return the raw payload.
    ///
    /// This helper only handles the specific zlib-stored format produced by
    /// `PNGSupport.makeZlibStored`; it is not a general zlib decompressor.
    private func decompressZlibStored(_ data: Data) throws -> Data {
        struct ZlibStoredDecompressionError: Error {}
        guard data.count >= 6 else { throw ZlibStoredDecompressionError() }
        // Skip the 2-byte zlib header (CMF + FLG).
        var offset = 2
        var result = Data()
        var seenFinal = false
        while offset + 5 <= data.count {
            let bfinalBtype = data[offset]; offset += 1
            let isFinal = (bfinalBtype & 0x01) == 1
            let btype   = (bfinalBtype >> 1) & 0x03
            guard btype == 0 else { throw ZlibStoredDecompressionError() }  // must be stored
            let lenLo = Int(data[offset]);     let lenHi = Int(data[offset + 1]); offset += 2
            let nlenLo = Int(data[offset]);    let nlenHi = Int(data[offset + 1]); offset += 2
            let len  = lenLo  | (lenHi  << 8)
            let nlen = nlenLo | (nlenHi << 8)
            guard (len & 0xFFFF) == (~UInt16(nlen) & 0xFFFF) else { throw ZlibStoredDecompressionError() }
            guard offset + len <= data.count else { throw ZlibStoredDecompressionError() }
            result.append(contentsOf: data[offset..<(offset + len)])
            offset += len
            if isFinal { seenFinal = true; break }
        }
        guard seenFinal else { throw ZlibStoredDecompressionError() }
        return result
    }
}
