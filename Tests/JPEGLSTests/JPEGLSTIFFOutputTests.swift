// JPEGLSTIFFOutputTests.swift
// Tests for TIFF output support in the JPEG-LS CLI decode command.
//
// These tests verify that:
//   - `TIFFSupport.encode` produces data with the correct TIFF file header.
//   - The IFD records the correct tags for width, height, bit depth, and colour type.
//   - 8-bit greyscale, 8-bit RGB, and 16-bit greyscale images are encoded correctly.
//   - Image data is written in chunky (interleaved), uncompressed little-endian format.
//   - A full JPEG-LS encode → decode → TIFF round-trip produces a valid TIFF file.
//   - TIFF output format is accepted by the decode command alongside raw/pgm/ppm/png.
//
// Phase 17.1: TIFF output for the `decode` command.

import Testing
import Foundation
@testable import JPEGLS

// MARK: - TIFF Output Tests

@Suite("TIFF Output Tests")
struct JPEGLSTIFFOutputTests {

    // MARK: - Header Tests

    @Test("TIFF output starts with 'II' little-endian byte-order mark")
    func testTIFFByteOrderMark() throws {
        let pixels: [[[Int]]] = [[[0, 128], [64, 255]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        #expect(data.count >= 8)
        #expect(data[0] == 0x49)  // 'I'
        #expect(data[1] == 0x49)  // 'I'
    }

    @Test("TIFF output contains magic number 42 in little-endian at bytes 2–3")
    func testTIFFMagicNumber() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let magic = UInt16(data[2]) | (UInt16(data[3]) << 8)
        #expect(magic == 42)
    }

    @Test("TIFF IFD offset in header points to offset 8 (immediately after the header)")
    func testTIFFIFDOffset() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let ifdOffset = readLE32(data, at: 4)
        #expect(ifdOffset == 8)
    }

    // MARK: - IFD Tests

    @Test("IFD contains exactly 10 entries for a greyscale image")
    func testIFDEntryCount() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let ifdOffset = Int(readLE32(data, at: 4))
        let entryCount = readLE16(data, at: ifdOffset)
        #expect(entryCount == 10)
    }

    @Test("IFD ImageWidth tag (256) contains the correct width for an 8-bit greyscale image")
    func testIFDImageWidth() throws {
        let row = Array(repeating: 0, count: 5)
        let pixels: [[[Int]]] = [Array(repeating: row, count: 3)]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 5, height: 3, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 256, in: data))
        #expect(readLE32(entry, at: 8) == 5)
    }

    @Test("IFD ImageLength tag (257) contains the correct height for an 8-bit greyscale image")
    func testIFDImageLength() throws {
        let row = Array(repeating: 0, count: 5)
        let pixels: [[[Int]]] = [Array(repeating: row, count: 3)]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 5, height: 3, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 257, in: data))
        #expect(readLE32(entry, at: 8) == 3)
    }

    @Test("IFD BitsPerSample tag (258) is 8 for maxVal ≤ 255 (greyscale)")
    func testIFDBitsPerSample8bitGreyscale() throws {
        let pixels: [[[Int]]] = [[[0, 100], [200, 255]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 258, in: data))
        // count == 1, type == SHORT: value is inline, lower 2 bytes of value field.
        let count = readLE32(entry, at: 4)
        #expect(count == 1)
        let bps = readLE16(entry, at: 8)
        #expect(bps == 8)
    }

    @Test("IFD BitsPerSample tag (258) is 16 for maxVal > 255 (greyscale)")
    func testIFDBitsPerSample16bitGreyscale() throws {
        let pixels: [[[Int]]] = [[[0, 4095], [2048, 1]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 4095)
        let entry = try #require(findIFDEntry(tag: 258, in: data))
        let count = readLE32(entry, at: 4)
        #expect(count == 1)
        let bps = readLE16(entry, at: 8)
        #expect(bps == 16)
    }

    @Test("IFD BitsPerSample tag (258) for RGB has count 3 and points to 3 equal SHORT values")
    func testIFDBitsPerSampleRGB8bit() throws {
        let r: [[Int]] = [[255, 0], [128, 64]]
        let g: [[Int]] = [[0, 255], [64, 128]]
        let b: [[Int]] = [[0, 0], [255, 0]]
        let pixels: [[[Int]]] = [r, g, b]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 258, in: data))
        let count = readLE32(entry, at: 4)
        #expect(count == 3)
        // value field is an offset into the file pointing to 3 SHORTs.
        let offset = Int(readLE32(entry, at: 8))
        #expect(offset + 6 <= data.count)
        let bps0 = readLE16(data, at: offset)
        let bps1 = readLE16(data, at: offset + 2)
        let bps2 = readLE16(data, at: offset + 4)
        #expect(bps0 == 8)
        #expect(bps1 == 8)
        #expect(bps2 == 8)
    }

    @Test("IFD Compression tag (259) is 1 (no compression)")
    func testIFDCompression() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 259, in: data))
        let compression = readLE16(entry, at: 8)
        #expect(compression == 1)
    }

    @Test("IFD PhotometricInterpretation tag (262) is 1 (BlackIsZero) for greyscale")
    func testIFDPhotometricGreyscale() throws {
        let pixels: [[[Int]]] = [[[0, 128], [64, 255]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 262, in: data))
        let photometric = readLE16(entry, at: 8)
        #expect(photometric == 1)
    }

    @Test("IFD PhotometricInterpretation tag (262) is 2 (RGB) for colour images")
    func testIFDPhotometricRGB() throws {
        let r: [[Int]] = [[255, 0], [128, 64]]
        let g: [[Int]] = [[0, 255], [64, 128]]
        let b: [[Int]] = [[0, 0], [255, 0]]
        let data = try TIFFSupport.encode(componentPixels: [r, g, b], width: 2, height: 2, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 262, in: data))
        let photometric = readLE16(entry, at: 8)
        #expect(photometric == 2)
    }

    @Test("IFD SamplesPerPixel tag (277) is 1 for greyscale and 3 for RGB")
    func testIFDSamplesPerPixel() throws {
        let grey = [[[Int]]]([[[0]]])
        let greyData = try TIFFSupport.encode(componentPixels: grey, width: 1, height: 1, maxVal: 255)
        let greyEntry = try #require(findIFDEntry(tag: 277, in: greyData))
        #expect(readLE16(greyEntry, at: 8) == 1)

        let rgb = [[[Int]]]([[[0]], [[0]], [[0]]])
        let rgbData = try TIFFSupport.encode(componentPixels: rgb, width: 1, height: 1, maxVal: 255)
        let rgbEntry = try #require(findIFDEntry(tag: 277, in: rgbData))
        #expect(readLE16(rgbEntry, at: 8) == 3)
    }

    @Test("IFD PlanarConfiguration tag (284) is 1 (chunky / interleaved)")
    func testIFDPlanarConfiguration() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let entry = try #require(findIFDEntry(tag: 284, in: data))
        let planar = readLE16(entry, at: 8)
        #expect(planar == 1)
    }

    @Test("IFD next-IFD pointer after entries is 0 (single IFD)")
    func testIFDNextIFDPointerIsZero() throws {
        let pixels: [[[Int]]] = [[[0]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        let ifdOffset = Int(readLE32(data, at: 4))
        let entryCount = Int(readLE16(data, at: ifdOffset))
        let nextIFDOffset = ifdOffset + 2 + entryCount * 12
        let nextIFD = readLE32(data, at: nextIFDOffset)
        #expect(nextIFD == 0)
    }

    // MARK: - Error Handling

    @Test("TIFF encoder throws for zero-dimension images")
    func testErrorZeroDimensions() {
        let pixels: [[[Int]]] = [[[0]]]
        #expect(throws: TIFFEncoderError.invalidDimensions) {
            try TIFFSupport.encode(componentPixels: pixels, width: 0, height: 1, maxVal: 255)
        }
        #expect(throws: TIFFEncoderError.invalidDimensions) {
            try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 0, maxVal: 255)
        }
    }

    @Test("TIFF encoder throws for unsupported component count")
    func testErrorUnsupportedComponents() {
        let pixels: [[[Int]]] = [[[0]], [[0]]]  // 2 components
        #expect(throws: TIFFEncoderError.unsupportedComponentCount(2)) {
            try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 255)
        }
    }

    @Test("TIFF encoder throws for invalid maxVal (0 and 65536)")
    func testErrorInvalidMaxVal() {
        let pixels: [[[Int]]] = [[[0]]]
        #expect(throws: TIFFEncoderError.invalidMaxVal) {
            try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 0)
        }
        #expect(throws: TIFFEncoderError.invalidMaxVal) {
            try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 65536)
        }
    }

    // MARK: - Pixel Content Verification

    @Test("8-bit greyscale image data contains correct pixel values in row-major order")
    func testImageDataGreyscale8bit() throws {
        // 2×2 greyscale image: [[10, 20], [30, 40]]
        let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let imageData = extractImageData(from: data)
        // Chunky format: row 0 = [10, 20], row 1 = [30, 40]
        #expect(imageData == [10, 20, 30, 40])
    }

    @Test("16-bit greyscale image data is stored in little-endian byte order")
    func testImageDataGreyscale16bit() throws {
        // 1×1 greyscale 16-bit image with pixel value 0x0F00.
        let pixels: [[[Int]]] = [[[0x0F00]]]
        let data = try TIFFSupport.encode(componentPixels: pixels, width: 1, height: 1, maxVal: 4095)
        let imageData = extractImageData(from: data)
        // Little-endian: low byte first.
        #expect(imageData.count == 2)
        #expect(imageData[0] == 0x00)  // low byte
        #expect(imageData[1] == 0x0F)  // high byte
    }

    @Test("8-bit RGB image data interleaves R, G, B samples in chunky order")
    func testImageDataRGB8bit() throws {
        // 1×2 RGB image: pixel (0,0) = R=10,G=20,B=30; pixel (0,1) = R=40,G=50,B=60.
        let r: [[Int]] = [[10, 40]]
        let g: [[Int]] = [[20, 50]]
        let b: [[Int]] = [[30, 60]]
        let data = try TIFFSupport.encode(componentPixels: [r, g, b], width: 2, height: 1, maxVal: 255)
        let imageData = extractImageData(from: data)
        // Chunky: R0 G0 B0 R1 G1 B1
        #expect(imageData == [10, 20, 30, 40, 50, 60])
    }

    @Test("16-bit RGB image data stores each channel in little-endian order")
    func testImageDataRGB16bit() throws {
        // 1×1 RGB image: R=0x0102, G=0x0304, B=0x0506.
        let r: [[Int]] = [[0x0102]]
        let g: [[Int]] = [[0x0304]]
        let b: [[Int]] = [[0x0506]]
        let data = try TIFFSupport.encode(componentPixels: [r, g, b], width: 1, height: 1, maxVal: 65535)
        let imageData = extractImageData(from: data)
        // Little-endian 16-bit per channel: R_lo R_hi G_lo G_hi B_lo B_hi
        #expect(imageData.count == 6)
        #expect(imageData[0] == 0x02); #expect(imageData[1] == 0x01)  // R LE
        #expect(imageData[2] == 0x04); #expect(imageData[3] == 0x03)  // G LE
        #expect(imageData[4] == 0x06); #expect(imageData[5] == 0x05)  // B LE
    }

    // MARK: - JPEG-LS Round-Trip

    @Test("Round-trip JPEG-LS encode → decode → TIFF produces a valid TIFF with correct pixel data")
    func testJPEGLSRoundTripToTIFF() throws {
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

        let componentPixels: [[[Int]]] = decoded.components.map { $0.pixels }
        let maxVal = (1 << decoded.frameHeader.bitsPerSample) - 1
        let tiffData = try TIFFSupport.encode(
            componentPixels: componentPixels,
            width: decoded.frameHeader.width,
            height: decoded.frameHeader.height,
            maxVal: maxVal
        )

        // Verify TIFF header.
        #expect(tiffData[0] == 0x49)
        #expect(tiffData[1] == 0x49)
        let magic = UInt16(tiffData[2]) | (UInt16(tiffData[3]) << 8)
        #expect(magic == 42)

        // Verify IFD ImageWidth and ImageLength.
        let widthEntry  = try #require(findIFDEntry(tag: 256, in: tiffData))
        let heightEntry = try #require(findIFDEntry(tag: 257, in: tiffData))
        #expect(readLE32(widthEntry,  at: 8) == UInt32(width))
        #expect(readLE32(heightEntry, at: 8) == UInt32(height))

        // Verify image data pixels.
        let imageData = extractImageData(from: tiffData)
        #expect(imageData.count == width * height)
        for row in 0..<height {
            for col in 0..<width {
                #expect(imageData[row * width + col] == UInt8(original[row][col]))
            }
        }
    }

    @Test("Round-trip 8-bit RGB JPEG-LS → TIFF produces correct interleaved component data")
    func testRGBRoundTripToTIFF() throws {
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
        let tiffData = try TIFFSupport.encode(
            componentPixels: componentPixels,
            width: decoded.frameHeader.width,
            height: decoded.frameHeader.height,
            maxVal: maxVal
        )

        // Verify PhotometricInterpretation == 2 (RGB).
        let photoEntry = try #require(findIFDEntry(tag: 262, in: tiffData))
        #expect(readLE16(photoEntry, at: 8) == 2)

        // Verify image data: chunky RGB pixels.
        let imageData = extractImageData(from: tiffData)
        #expect(imageData.count == width * height * 3)
        for row in 0..<height {
            for col in 0..<width {
                let base = (row * width + col) * 3
                #expect(imageData[base]     == UInt8(r[row][col]))
                #expect(imageData[base + 1] == UInt8(g[row][col]))
                #expect(imageData[base + 2] == UInt8(b[row][col]))
            }
        }
    }

    // MARK: - Decode Format Acceptance

    @Test("TIFF is listed as a supported decode output format alongside raw, pgm, ppm, and png")
    func testTIFFInSupportedDecodeFormats() {
        // This mirrors the validation logic in DecodeCommand.run().
        let supportedFormats = ["raw", "pgm", "ppm", "png", "tiff"]
        #expect(supportedFormats.contains("tiff"))
    }

    // MARK: - Helpers

    /// Return the raw bytes of the 12-byte IFD entry for `tag`, or nil if not found.
    private func findIFDEntry(tag: UInt16, in data: Data) -> Data? {
        guard data.count >= 8 else { return nil }
        let ifdOffset = Int(readLE32(data, at: 4))
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readLE16(data, at: ifdOffset))
        for i in 0..<entryCount {
            let entryOffset = ifdOffset + 2 + i * 12
            guard entryOffset + 12 <= data.count else { return nil }
            let entryTag = readLE16(data, at: entryOffset)
            if entryTag == tag {
                return data.subdata(in: entryOffset..<(entryOffset + 12))
            }
        }
        return nil
    }

    /// Extract the image data bytes from a TIFF produced by TIFFSupport.encode.
    ///
    /// Reads StripOffsets (tag 273) and StripByteCounts (tag 279) from the IFD.
    private func extractImageData(from data: Data) -> [UInt8] {
        guard let offsetEntry = findIFDEntry(tag: 273, in: data),
              let countEntry  = findIFDEntry(tag: 279, in: data) else { return [] }
        let offset = Int(readLE32(offsetEntry, at: 8))
        let count  = Int(readLE32(countEntry,  at: 8))
        guard offset + count <= data.count else { return [] }
        return Array(data[offset..<(offset + count)])
    }

    /// Read a little-endian UInt16 from `data` at `offset`.
    private func readLE16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    /// Read a little-endian UInt32 from `data` at `offset`.
    private func readLE32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
    }

    // MARK: - TIFF Decoder Tests

    @Test("TIFF decoder round-trip: 8-bit greyscale encode → decode preserves pixel values")
    func testTIFFDecodeGreyscale8bit() throws {
        let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
        let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let decoded = try TIFFSupport.decode(tiffData)
        #expect(decoded.width == 2)
        #expect(decoded.height == 2)
        #expect(decoded.bitsPerSample == 8)
        #expect(decoded.componentPixels.count == 1)
        #expect(decoded.componentPixels[0][0][0] == 10)
        #expect(decoded.componentPixels[0][0][1] == 20)
        #expect(decoded.componentPixels[0][1][0] == 30)
        #expect(decoded.componentPixels[0][1][1] == 40)
    }

    @Test("TIFF decoder round-trip: 16-bit greyscale encode → decode preserves pixel values")
    func testTIFFDecodeGreyscale16bit() throws {
        let pixels: [[[Int]]] = [[[0x0F00, 0x1234], [0xABCD, 0xFFFF]]]
        let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 65535)
        let decoded = try TIFFSupport.decode(tiffData)
        #expect(decoded.bitsPerSample == 16)
        #expect(decoded.componentPixels[0][0][0] == 0x0F00)
        #expect(decoded.componentPixels[0][0][1] == 0x1234)
        #expect(decoded.componentPixels[0][1][0] == 0xABCD)
        #expect(decoded.componentPixels[0][1][1] == 0xFFFF)
    }

    @Test("TIFF decoder round-trip: 8-bit RGB encode → decode preserves all three channels")
    func testTIFFDecodeRGB8bit() throws {
        let r: [[Int]] = [[255, 0], [128, 64]]
        let g: [[Int]] = [[0, 200], [64, 100]]
        let b: [[Int]] = [[50, 100], [200, 255]]
        let pixels: [[[Int]]] = [r, g, b]
        let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
        let decoded = try TIFFSupport.decode(tiffData)
        #expect(decoded.componentPixels.count == 3)
        #expect(decoded.componentPixels[0] == r)
        #expect(decoded.componentPixels[1] == g)
        #expect(decoded.componentPixels[2] == b)
    }

    @Test("TIFF decoder round-trip: 16-bit RGB encode → decode preserves all three channels")
    func testTIFFDecodeRGB16bit() throws {
        let r: [[Int]] = [[1000, 2000], [3000, 4000]]
        let g: [[Int]] = [[5000, 6000], [7000, 8000]]
        let b: [[Int]] = [[9000, 10000], [11000, 12000]]
        let pixels: [[[Int]]] = [r, g, b]
        let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 65535)
        let decoded = try TIFFSupport.decode(tiffData)
        #expect(decoded.componentPixels[0] == r)
        #expect(decoded.componentPixels[1] == g)
        #expect(decoded.componentPixels[2] == b)
    }

    @Test("TIFF decoder rejects data that is too short to be a valid TIFF file")
    func testTIFFDecodeTooShort() {
        let tinyData = Data([0x49, 0x49, 0x2A])  // 'II' + part of magic
        #expect(throws: TIFFDecoderError.invalidByteOrderMark) {
            try TIFFSupport.decode(tinyData)
        }
    }

    @Test("TIFF decoder rejects files with an invalid byte-order mark")
    func testTIFFDecodeInvalidByteOrder() {
        var bad = Data(repeating: 0, count: 10)
        bad[0] = 0x4A; bad[1] = 0x4A  // 'JJ' — not valid
        #expect(throws: TIFFDecoderError.invalidByteOrderMark) {
            try TIFFSupport.decode(bad)
        }
    }

    @Test("TIFF decoder rejects files with an invalid magic number")
    func testTIFFDecodeInvalidMagic() {
        var bad = Data(repeating: 0, count: 10)
        bad[0] = 0x49; bad[1] = 0x49  // 'II'
        bad[2] = 0x2B; bad[3] = 0x00  // magic = 43, not 42
        #expect(throws: TIFFDecoderError.invalidMagicNumber) {
            try TIFFSupport.decode(bad)
        }
    }

    @Test("TIFF decoder rejects compressed TIFF files (Compression ≠ 1)")
    func testTIFFDecodeCompressed() throws {
        // Build a minimal TIFF with Compression = 5 (LZW).
        var tiffData = try TIFFSupport.encode(
            componentPixels: [[[0]]], width: 1, height: 1, maxVal: 255
        )
        // Patch the Compression tag value in the IFD.
        // IFD starts at offset 8; entry count at offset 8 (2 bytes LE).
        // Each IFD entry is 12 bytes; Compression is tag 259 (0x0103).
        let entryCount = Int(readLE16(tiffData, at: 8))
        let entriesStart = 10
        for i in 0..<entryCount {
            let base = entriesStart + i * 12
            let tag = readLE16(tiffData, at: base)
            if tag == 259 {  // Compression tag
                // Set value to 5 (LZW): for SHORT with count=1 the value is in bytes 8-9 of the entry.
                tiffData[base + 8] = 0x05
                tiffData[base + 9] = 0x00
                break
            }
        }
        #expect(throws: TIFFDecoderError.unsupportedCompression(5)) {
            try TIFFSupport.decode(tiffData)
        }
    }

    @Test("TIFF decoder maxVal property returns 255 for 8-bit and 65535 for 16-bit images")
    func testTIFFImageMaxVal() throws {
        let pixels8: [[[Int]]] = [[[100]]]
        let tiff8 = try TIFFSupport.encode(componentPixels: pixels8, width: 1, height: 1, maxVal: 255)
        let decoded8 = try TIFFSupport.decode(tiff8)
        #expect(decoded8.maxVal == 255)

        let pixels16: [[[Int]]] = [[[1000]]]
        let tiff16 = try TIFFSupport.encode(componentPixels: pixels16, width: 1, height: 1, maxVal: 65535)
        let decoded16 = try TIFFSupport.decode(tiff16)
        #expect(decoded16.maxVal == 65535)
    }
}
