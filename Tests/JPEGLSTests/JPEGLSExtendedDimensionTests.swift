// Extended Dimension Tests
//
// Unit tests for JPEG-LS extended dimensions (LSE type 4) support per ITU-T.87 §5.1.1.4.
// Tests cover frame header validation, LSE type 4 encoding, parsing, and encoder/decoder
// round-trips for images whose width or height exceeds the standard 16-bit SOF limit (65535).

import Foundation
import Testing
@testable import JPEGLS

// MARK: - Frame Header Extended Dimension Tests

@Suite("Extended Dimension Frame Header Tests")
struct ExtendedDimensionFrameHeaderTests {

    @Test("Frame header allows width > 65535")
    func testWidthAbove65535() throws {
        let header = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 65536, height: 100)
        #expect(header.width == 65536)
        #expect(header.height == 100)
    }

    @Test("Frame header allows height > 65535")
    func testHeightAbove65535() throws {
        let header = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 100, height: 65536)
        #expect(header.width == 100)
        #expect(header.height == 65536)
    }

    @Test("Frame header allows both dimensions > 65535")
    func testBothDimensionsAbove65535() throws {
        let header = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 100_000, height: 80_000)
        #expect(header.width == 100_000)
        #expect(header.height == 80_000)
    }

    @Test("Frame header allows dimensions up to UInt32 maximum")
    func testDimensionsAtUInt32Max() throws {
        let header = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: Int(UInt32.max),
            height: Int(UInt32.max)
        )
        #expect(header.width == Int(UInt32.max))
        #expect(header.height == Int(UInt32.max))
    }

    @Test("Frame header rejects dimensions exceeding UInt32 maximum")
    func testDimensionsExceedUInt32MaxThrows() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(
                bitsPerSample: 8,
                width: Int(UInt32.max) + 1,
                height: 100
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(
                bitsPerSample: 8,
                width: 100,
                height: Int(UInt32.max) + 1
            )
        }
    }
}

// MARK: - LSE Type 4 Encoder Tests

@Suite("Extended Dimension Encoder Tests")
struct ExtendedDimensionEncoderTests {

    @Test("Encoder emits LSE type 4 before SOF when width > 65535")
    func testEncoderEmitsLSEType4ForWideImage() throws {
        let header = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: 2,
            width: 65536,
            componentCount: 1,
            components: [.init(id: 1)]
        )
        // Single row of 65536 pixels (all zero) — create minimal pixel data
        let row = [Int](repeating: 0, count: 65536)
        let imageData = try MultiComponentImageData(
            components: [MultiComponentImageData.ComponentData(id: 1, pixels: [row, row])],
            frameHeader: header
        )
        let encoder = JPEGLSEncoder()
        let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        let bytes = Array(encoded)

        // Find the LSE type 4 segment (FF F8 ... 04 ...)
        var lseType4Found = false
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xF8 {
                // Read Ll (2 bytes) and Id (1 byte)
                if i + 4 < bytes.count {
                    let id = bytes[i + 4]  // byte after Ll
                    if id == 0x04 {
                        lseType4Found = true
                        // Verify structure: Ll = 12, Wxy = 4, XSIZE = 65536, YSIZE = 2
                        let ll = (Int(bytes[i + 2]) << 8) | Int(bytes[i + 3])
                        #expect(ll == 12)
                        #expect(bytes[i + 5] == 4)   // Wxy = 4 bytes
                        let xSize = (Int(bytes[i + 6]) << 24) | (Int(bytes[i + 7]) << 16) |
                                    (Int(bytes[i + 8]) << 8) | Int(bytes[i + 9])
                        let ySize = (Int(bytes[i + 10]) << 24) | (Int(bytes[i + 11]) << 16) |
                                    (Int(bytes[i + 12]) << 8) | Int(bytes[i + 13])
                        #expect(xSize == 65536)
                        #expect(ySize == 2)
                        break
                    }
                }
            }
            i += 1
        }
        #expect(lseType4Found)
    }

    @Test("Encoder writes 0 in SOF width field when width > 65535")
    func testEncoderWritesZeroInSOFWidth() throws {
        let header = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: 1,
            width: 65536,
            componentCount: 1,
            components: [.init(id: 1)]
        )
        let row = [Int](repeating: 0, count: 65536)
        let imageData = try MultiComponentImageData(
            components: [MultiComponentImageData.ComponentData(id: 1, pixels: [row])],
            frameHeader: header
        )
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        let bytes = Array(encoded)

        // Find SOF marker (FF F7) and check width/height fields
        var sofPos: Int?
        var j = 0
        while j < bytes.count - 1 {
            if bytes[j] == 0xFF && bytes[j + 1] == 0xF7 {
                sofPos = j
                break
            }
            j += 1
        }
        guard let pos = sofPos else {
            Issue.record("SOF marker not found")
            return
        }
        // SOF layout: FF F7 | Ll(2) | P(1) | Y(2) | X(2) | ...
        let sofWidth = (Int(bytes[pos + 7]) << 8) | Int(bytes[pos + 8])
        #expect(sofWidth == 0)   // Width > 65535 → SOF field is 0
    }

    @Test("Encoder does not emit LSE type 4 for standard dimensions")
    func testEncoderDoesNotEmitLSEType4ForStandardImage() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        let bytes = Array(encoded)

        var lseType4Found = false
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xF8 && i + 4 < bytes.count {
                if bytes[i + 4] == 0x04 {
                    lseType4Found = true
                    break
                }
            }
            i += 1
        }
        #expect(!lseType4Found)
    }
}

// MARK: - LSE Type 4 Parser Tests

@Suite("Extended Dimension Parser Tests")
struct ExtendedDimensionParserTests {

    /// Build a minimal JPEG-LS bitstream that includes an LSE type 4 segment.
    ///
    /// - Parameters:
    ///   - width: Image width to encode in LSE type 4 (XSIZE).
    ///   - height: Image height to encode in LSE type 4 (YSIZE).
    ///   - sofWidth: Width written in SOF (0 when extended).
    ///   - sofHeight: Height written in SOF (0 when extended).
    private func buildBitstreamWithLSEType4(
        width: UInt32,
        height: UInt32,
        sofWidth: UInt16 = 0,
        sofHeight: UInt16 = 0
    ) -> Data {
        var data = Data()

        // SOI
        data.append(contentsOf: [0xFF, 0xD8])

        // LSE type 4 — FF F8 | Ll(2) | Id(1) | Wxy(1) | XSIZE(4) | YSIZE(4)
        data.append(contentsOf: [0xFF, 0xF8])
        data.append(contentsOf: [0x00, 0x0C])   // Ll = 12
        data.append(0x04)                         // Id = 4 (extended dimensions)
        data.append(0x04)                         // Wxy = 4
        data.append(UInt8((width >> 24) & 0xFF))
        data.append(UInt8((width >> 16) & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))
        data.append(UInt8((height >> 24) & 0xFF))
        data.append(UInt8((height >> 16) & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))

        // SOF — FF F7 | Ll(2) | P(1) | Y(2) | X(2) | Nf(1) | comp(3)
        data.append(contentsOf: [0xFF, 0xF7])
        data.append(contentsOf: [0x00, 0x0B])   // Ll = 11 (1 component)
        data.append(8)                            // Precision
        data.append(UInt8((sofHeight >> 8) & 0xFF))
        data.append(UInt8(sofHeight & 0xFF))
        data.append(UInt8((sofWidth >> 8) & 0xFF))
        data.append(UInt8(sofWidth & 0xFF))
        data.append(1)                            // Nf = 1 component
        data.append(1)                            // Component ID
        data.append(0x11)                         // Sampling factors
        data.append(0)                            // QT selector

        // SOS — FF DA | Ll(2) | Ns(1) | Cs(1) Td(1) | Ss Ss Ah|Al
        data.append(contentsOf: [0xFF, 0xDA])
        data.append(contentsOf: [0x00, 0x08])   // Ll = 8
        data.append(1)                            // Ns = 1
        data.append(1)                            // Component ID
        data.append(0)                            // Tdi = 0
        data.append(0)                            // NEAR = 0
        data.append(0)                            // ILV = 0
        data.append(0)                            // Al/Ah = 0

        // Minimal scan data
        data.append(contentsOf: [0x00])

        // EOI
        data.append(contentsOf: [0xFF, 0xD9])

        return data
    }

    @Test("Parser reads extended width from LSE type 4")
    func testParserReadsExtendedWidth() throws {
        let data = buildBitstreamWithLSEType4(width: 65536, height: 100, sofWidth: 0, sofHeight: 100)
        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == 65536)
        #expect(result.frameHeader.height == 100)
    }

    @Test("Parser reads extended height from LSE type 4")
    func testParserReadsExtendedHeight() throws {
        let data = buildBitstreamWithLSEType4(width: 100, height: 65536, sofWidth: 100, sofHeight: 0)
        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == 100)
        #expect(result.frameHeader.height == 65536)
    }

    @Test("Parser reads both extended dimensions from LSE type 4")
    func testParserReadsBothExtendedDimensions() throws {
        let data = buildBitstreamWithLSEType4(width: 100_000, height: 80_000, sofWidth: 0, sofHeight: 0)
        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == 100_000)
        #expect(result.frameHeader.height == 80_000)
    }

    @Test("Parser uses SOF dimensions when non-zero even if LSE type 4 present")
    func testParserPrefersSofDimensionWhenNonZero() throws {
        // SOF has non-zero width: parser should use SOF value for width, LSE value for height
        let data = buildBitstreamWithLSEType4(
            width: 100_000, height: 80_000,
            sofWidth: 200,  // Non-zero → use SOF width
            sofHeight: 0    // Zero → use LSE height
        )
        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == 200)
        #expect(result.frameHeader.height == 80_000)
    }

    @Test("Parser gracefully skips LSE type 4 with unsupported Wxy value")
    func testParserSkipsUnsupportedWxy() throws {
        var data = Data()
        // SOI
        data.append(contentsOf: [0xFF, 0xD8])
        // LSE type 4 with unsupported Wxy=8 and Ll=6 to test graceful skip behaviour.
        // Payload after the marker: Id(1) + Wxy(1) + 2 padding bytes = 4 bytes; Ll = 2+4 = 6.
        data.append(contentsOf: [0xFF, 0xF8])
        data.append(contentsOf: [0x00, 0x06])   // Ll = 6
        data.append(0x04)                         // Id = 4 (extended dimensions)
        data.append(0x08)                         // Wxy = 8 (unsupported — triggers graceful skip)
        data.append(0x00)                         // Padding bytes to complete segment payload.
        data.append(0x00)

        // SOF with standard dimensions
        data.append(contentsOf: [0xFF, 0xF7])
        data.append(contentsOf: [0x00, 0x0B])
        data.append(8)
        data.append(contentsOf: [0x00, 0x02])   // Height = 2
        data.append(contentsOf: [0x00, 0x04])   // Width = 4
        data.append(1)
        data.append(1); data.append(0x11); data.append(0)

        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        data.append(contentsOf: [0x00, 0x08])
        data.append(1); data.append(1); data.append(0)
        data.append(0); data.append(0); data.append(0)
        data.append(0x00)

        // EOI
        data.append(contentsOf: [0xFF, 0xD9])

        // Should not throw; falls back to SOF dimensions
        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == 4)
        #expect(result.frameHeader.height == 2)
    }
}

// MARK: - Encoder/Parser Round-Trip Tests

@Suite("Extended Dimension Round-Trip Tests")
struct ExtendedDimensionRoundTripTests {

    @Test("Encode and re-parse image with width > 65535 preserves dimensions in frame header")
    func testRoundTripPreservesDimensions() throws {
        let targetWidth = 65538
        let targetHeight = 3
        let header = try JPEGLSFrameHeader(
            bitsPerSample: 8,
            height: targetHeight,
            width: targetWidth,
            componentCount: 1,
            components: [.init(id: 1)]
        )
        let row = [Int](repeating: 128, count: targetWidth)
        let rows = [[Int]](repeating: row, count: targetHeight)
        let imageData = try MultiComponentImageData(
            components: [MultiComponentImageData.ComponentData(id: 1, pixels: rows)],
            frameHeader: header
        )
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        let parsed = try JPEGLSParser(data: encoded).parse()

        #expect(parsed.frameHeader.width == targetWidth)
        #expect(parsed.frameHeader.height == targetHeight)
    }
}
