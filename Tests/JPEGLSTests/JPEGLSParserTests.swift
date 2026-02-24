/// Tests for JPEG-LS bitstream parser

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Parser Tests")
struct JPEGLSParserTests {
    
    // MARK: - Helper Methods
    
    /// Create a minimal valid JPEG-LS bitstream for grayscale image
    func createMinimalGrayscaleBitstream(
        width: Int = 100,
        height: Int = 100,
        bitsPerSample: Int = 8
    ) -> Data {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker (Start of Frame)
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11  // 2 + 1 + 2 + 2 + 1 + 3
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(UInt8(bitsPerSample))  // Precision
        data.append(contentsOf: withUnsafeBytes(of: UInt16(height).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(width).bigEndian) { Array($0) })
        data.append(1)  // Component count
        data.append(1)  // Component ID
        data.append(0x11)  // Sampling factors (1:1)
        data.append(0)  // Quantization table selector
        
        // SOS marker (Start of Scan)
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8  // 2 + 1 + 2 + 3
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)  // Component count in scan
        data.append(1)  // Component ID
        data.append(0)  // Table selector
        data.append(0)  // NEAR
        data.append(0)  // Interleave mode (none)
        data.append(0)  // Point transform
        
        // Minimal scan data (just a few bytes)
        data.append(contentsOf: [0x00, 0x01, 0x02])
        
        // EOI marker
        data.append(contentsOf: [0xFF, 0xD9])
        
        return data
    }
    
    /// Create a minimal valid JPEG-LS bitstream for RGB image
    func createMinimalRGBBitstream(
        width: Int = 100,
        height: Int = 100,
        bitsPerSample: Int = 8
    ) -> Data {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker (Start of Frame)
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 17  // 2 + 1 + 2 + 2 + 1 + (3 * 3)
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(UInt8(bitsPerSample))  // Precision
        data.append(contentsOf: withUnsafeBytes(of: UInt16(height).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(width).bigEndian) { Array($0) })
        data.append(3)  // Component count
        // Component 1 (R)
        data.append(1)
        data.append(0x11)
        data.append(0)
        // Component 2 (G)
        data.append(2)
        data.append(0x11)
        data.append(0)
        // Component 3 (B)
        data.append(3)
        data.append(0x11)
        data.append(0)
        
        // SOS marker (Start of Scan)
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 12  // 2 + 1 + (3 * 2) + 3
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(3)  // Component count in scan
        data.append(1)  // Component ID
        data.append(0)  // Table selector
        data.append(2)  // Component ID
        data.append(0)  // Table selector
        data.append(3)  // Component ID
        data.append(0)  // Table selector
        data.append(0)  // NEAR
        data.append(2)  // Interleave mode (sample)
        data.append(0)  // Point transform
        
        // Minimal scan data
        data.append(contentsOf: [0x00, 0x01, 0x02])
        
        // EOI marker
        data.append(contentsOf: [0xFF, 0xD9])
        
        return data
    }
    
    // MARK: - Valid Bitstream Tests
    
    @Test("Parse minimal valid grayscale bitstream")
    func testParseMinimalGrayscaleBitstream() throws {
        let data = createMinimalGrayscaleBitstream()
        let parser = JPEGLSParser(data: data)
        
        let result = try parser.parse()
        
        // Verify frame header
        #expect(result.frameHeader.width == 100)
        #expect(result.frameHeader.height == 100)
        #expect(result.frameHeader.bitsPerSample == 8)
        #expect(result.frameHeader.componentCount == 1)
        #expect(result.frameHeader.components.count == 1)
        #expect(result.frameHeader.components[0].id == 1)
        
        // Verify scan header
        #expect(result.scanHeaders.count == 1)
        #expect(result.scanHeaders[0].componentCount == 1)
        #expect(result.scanHeaders[0].near == 0)
        #expect(result.scanHeaders[0].interleaveMode == .none)
        #expect(result.scanHeaders[0].isLossless)
        
        // Verify no custom preset parameters
        #expect(result.presetParameters == nil)
        
        // Verify no application markers or comments
        #expect(result.applicationMarkers.isEmpty)
        #expect(result.comments.isEmpty)
    }
    
    @Test("Parse minimal valid RGB bitstream")
    func testParseMinimalRGBBitstream() throws {
        let data = createMinimalRGBBitstream()
        let parser = JPEGLSParser(data: data)
        
        let result = try parser.parse()
        
        // Verify frame header
        #expect(result.frameHeader.width == 100)
        #expect(result.frameHeader.height == 100)
        #expect(result.frameHeader.bitsPerSample == 8)
        #expect(result.frameHeader.componentCount == 3)
        #expect(result.frameHeader.components.count == 3)
        
        // Verify scan header
        #expect(result.scanHeaders.count == 1)
        #expect(result.scanHeaders[0].componentCount == 3)
        #expect(result.scanHeaders[0].near == 0)
        #expect(result.scanHeaders[0].interleaveMode == .sample)
    }
    
    @Test("Parse bitstream with custom preset parameters")
    func testParseWithPresetParameters() throws {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // LSE marker with preset parameters
        data.append(contentsOf: [0xFF, 0xF8])
        let lseLength: UInt16 = 13  // Length includes itself (2 bytes) + type (1 byte) + parameters (10 bytes)
        data.append(contentsOf: withUnsafeBytes(of: lseLength.bigEndian) { Array($0) })
        data.append(0x01)  // Extension type: preset parameters
        data.append(contentsOf: withUnsafeBytes(of: UInt16(255).bigEndian) { Array($0) })  // MAXVAL
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).bigEndian) { Array($0) })   // T1
        data.append(contentsOf: withUnsafeBytes(of: UInt16(7).bigEndian) { Array($0) })   // T2
        data.append(contentsOf: withUnsafeBytes(of: UInt16(21).bigEndian) { Array($0) })  // T3
        data.append(contentsOf: withUnsafeBytes(of: UInt16(64).bigEndian) { Array($0) })  // RESET
        
        // Add rest of minimal bitstream
        data.append(createMinimalGrayscaleBitstream().dropFirst(2))  // Skip SOI
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        // Verify custom preset parameters
        #expect(result.presetParameters != nil)
        #expect(result.presetParameters?.maxValue == 255)
        #expect(result.presetParameters?.threshold1 == 3)
        #expect(result.presetParameters?.threshold2 == 7)
        #expect(result.presetParameters?.threshold3 == 21)
        #expect(result.presetParameters?.reset == 64)
    }
    
    @Test("Parse bitstream with application markers")
    func testParseWithApplicationMarkers() throws {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // APP0 marker
        data.append(contentsOf: [0xFF, 0xE0])
        let app0Length: UInt16 = 6
        data.append(contentsOf: withUnsafeBytes(of: app0Length.bigEndian) { Array($0) })
        data.append(contentsOf: [0x01, 0x02, 0x03, 0x04])  // 4 bytes of data
        
        // Add rest of minimal bitstream
        data.append(createMinimalGrayscaleBitstream().dropFirst(2))  // Skip SOI
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        // Verify application marker
        #expect(result.applicationMarkers.count == 1)
        #expect(result.applicationMarkers[0].marker == .applicationMarker0)
        #expect(result.applicationMarkers[0].data == Data([0x01, 0x02, 0x03, 0x04]))
    }
    
    @Test("Parse bitstream with comment")
    func testParseWithComment() throws {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // COM marker
        data.append(contentsOf: [0xFF, 0xFE])
        let commentText = "Test comment".data(using: .utf8)!
        let commentLength = UInt16(2 + commentText.count)
        data.append(contentsOf: withUnsafeBytes(of: commentLength.bigEndian) { Array($0) })
        data.append(commentText)
        
        // Add rest of minimal bitstream
        data.append(createMinimalGrayscaleBitstream().dropFirst(2))  // Skip SOI
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        // Verify comment
        #expect(result.comments.count == 1)
        #expect(result.comments[0] == commentText)
    }
    
    @Test("Parse bitstream with various bit depths")
    func testParseVariousBitDepths() throws {
        for bits in [8, 12, 16] {
            let data = createMinimalGrayscaleBitstream(bitsPerSample: bits)
            let parser = JPEGLSParser(data: data)
            
            let result = try parser.parse()
            #expect(result.frameHeader.bitsPerSample == bits)
        }
    }
    
    @Test("Parse bitstream with near-lossless mode")
    func testParseNearLosslessBitstream() throws {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker (Start of Frame)
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)  // Precision
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)  // Component count
        data.append(1)  // Component ID
        data.append(0x11)  // Sampling factors
        data.append(0)  // Quantization table selector
        
        // SOS marker with NEAR = 5
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)  // Component count in scan
        data.append(1)  // Component ID
        data.append(0)  // Table selector
        data.append(5)  // NEAR = 5 (near-lossless)
        data.append(0)  // Interleave mode
        data.append(0)  // Point transform
        
        // Minimal scan data
        data.append(contentsOf: [0x00, 0x01, 0x02])
        
        // EOI marker
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        // Verify near-lossless mode
        #expect(result.scanHeaders[0].near == 5)
        #expect(result.scanHeaders[0].isNearLossless)
        #expect(!result.scanHeaders[0].isLossless)
    }
    
    // MARK: - Invalid Bitstream Tests
    
    @Test("Parse bitstream missing SOI throws error")
    func testParseMissingSOI() {
        // Create bitstream without SOI marker
        let data = Data([0xFF, 0xF7, 0x00, 0x0B])  // Start with SOF instead
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream missing EOI throws error")
    func testParseMissingEOI() {
        var data = createMinimalGrayscaleBitstream()
        // Remove last 2 bytes (EOI marker)
        data = data.dropLast(2)
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream missing SOF throws error")
    func testParseMissingSOF() {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOS marker without SOF
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)
        
        // EOI marker
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream with multiple SOF throws error")
    func testParseMultipleSOF() {
        var data = createMinimalGrayscaleBitstream()
        
        // Remove EOI
        data = data.dropLast(2)
        
        // Add another SOF marker
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)
        
        // Add EOI
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream with invalid SOF length throws error")
    func testParseInvalidSOFLength() {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker with wrong length
        data.append(contentsOf: [0xFF, 0xF7])
        let wrongLength: UInt16 = 10  // Should be 11
        data.append(contentsOf: withUnsafeBytes(of: wrongLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream with invalid SOS length throws error")
    func testParseInvalidSOSLength() {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)
        
        // SOS marker with wrong length
        data.append(contentsOf: [0xFF, 0xDA])
        let wrongLength: UInt16 = 7  // Should be 8
        data.append(contentsOf: withUnsafeBytes(of: wrongLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream with invalid interleave mode throws error")
    func testParseInvalidInterleaveMode() {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)
        
        // SOS marker with invalid interleave mode
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0)
        data.append(0)
        data.append(99)  // Invalid interleave mode
        data.append(0)
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse empty data throws error")
    func testParseEmptyData() {
        let data = Data()
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse truncated data throws error")
    func testParseTruncatedData() {
        let data = Data([0xFF, 0xD8, 0xFF])  // Incomplete marker
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parse bitstream with scan component not in frame throws error")
    func testParseScanComponentNotInFrame() {
        var data = Data()
        
        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF marker with component ID 1
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)  // Component ID 1
        data.append(0x11)
        data.append(0)
        
        // SOS marker with component ID 2 (not in frame)
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(2)  // Component ID 2 (invalid)
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)
        
        let parser = JPEGLSParser(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    // MARK: - DRI/DNL Marker Tests
    
    @Test("Parser reads DRI marker and stores restart interval")
    func testParserDRIMarker() throws {
        var data = Data()
        
        // SOI
        data.append(contentsOf: [0xFF, 0xD8])
        
        // DRI marker: FF DD, length=4, restart interval=32
        data.append(contentsOf: [0xFF, 0xDD])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(32).bigEndian) { Array($0) })
        
        // SOF
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8); data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0x11); data.append(0)
        
        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0); data.append(0); data.append(0); data.append(0)
        
        // Minimal scan data
        data.append(contentsOf: [0x01])
        
        // EOI
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        #expect(result.restartInterval == 32)
    }
    
    @Test("Parser returns nil restartInterval when no DRI marker present")
    func testParserNoDRIMarker() throws {
        let data = createMinimalGrayscaleBitstream()
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        #expect(result.restartInterval == nil)
    }
    
    @Test("Parser handles DRI restart interval zero")
    func testParserDRIZero() throws {
        var data = Data()
        
        // SOI
        data.append(contentsOf: [0xFF, 0xD8])
        
        // DRI marker with interval=0 (disables restart markers)
        data.append(contentsOf: [0xFF, 0xDD])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Array($0) })
        
        // SOF
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8); data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0x11); data.append(0)
        
        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0); data.append(0); data.append(0); data.append(0)
        
        data.append(contentsOf: [0x01])
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        #expect(result.restartInterval == 0)
    }
    
    @Test("Parser rejects DRI marker with invalid length")
    func testParserDRIInvalidLength() throws {
        var data = Data()
        
        // SOI
        data.append(contentsOf: [0xFF, 0xD8])
        
        // DRI marker with wrong length (should be 4)
        data.append(contentsOf: [0xFF, 0xDD])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(6).bigEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x10, 0x00, 0x00])
        
        // SOF (won't be reached)
        data.append(contentsOf: [0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x0A, 0x00, 0x0A, 0x01, 0x01, 0x11, 0x00])
        data.append(contentsOf: [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x01, 0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        #expect(throws: JPEGLSError.self) {
            try parser.parse()
        }
    }
    
    @Test("Parser handles DNL marker gracefully")
    func testParserDNLMarker() throws {
        var data = Data()
        
        // SOI
        data.append(contentsOf: [0xFF, 0xD8])
        
        // SOF
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8); data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0x11); data.append(0)
        
        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1); data.append(1); data.append(0); data.append(0); data.append(0); data.append(0)
        data.append(contentsOf: [0x01])
        
        // DNL marker (FF DC, length=4, lines=10)
        data.append(contentsOf: [0xFF, 0xDC])
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(10).bigEndian) { Array($0) })
        
        // EOI
        data.append(contentsOf: [0xFF, 0xD9])
        
        let parser = JPEGLSParser(data: data)
        // DNL should be silently consumed; parse should succeed
        let result = try parser.parse()
        #expect(result.frameHeader.width == 10)
    }
}
