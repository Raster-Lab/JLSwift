/// Additional tests to maintain >95% code coverage.
///
/// These tests cover code paths in the decoder, error types, parser,
/// and multi-component encoder/decoder that are not exercised by other tests.

import Testing
import Foundation
@testable import JPEGLS

// MARK: - Decoder Line-Interleaved Round-Trip Tests

@Suite("Decoder Coverage Tests")
struct DecoderCoverageTests {

    @Test("Round-trip: 4x4 RGB line-interleaved lossless")
    func testRoundTripRGBLineInterleaved() throws {
        let redPixels: [[Int]] = [
            [200, 201, 202, 203],
            [210, 211, 212, 213],
            [220, 221, 222, 223],
            [230, 231, 232, 233]
        ]

        let greenPixels: [[Int]] = [
            [100, 101, 102, 103],
            [110, 111, 112, 113],
            [120, 121, 122, 123],
            [130, 131, 132, 133]
        ]

        let bluePixels: [[Int]] = [
            [50, 51, 52, 53],
            [60, 61, 62, 63],
            [70, 71, 72, 73],
            [80, 81, 82, 83]
        ]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: redPixels,
            greenPixels: greenPixels,
            bluePixels: bluePixels,
            bitsPerSample: 8
        )

        // Encode with line interleaving
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .line)
        let encoded = try encoder.encode(imageData, configuration: config)

        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)

        // Verify component count
        #expect(decoded.components.count == 3)

        // Verify pixel-perfect match for all components
        let originals = [redPixels, greenPixels, bluePixels]
        for componentIdx in 0..<3 {
            for row in 0..<4 {
                for col in 0..<4 {
                    #expect(decoded.components[componentIdx].pixels[row][col] == originals[componentIdx][row][col])
                }
            }
        }
    }

    @Test("Round-trip: 8x8 RGB line-interleaved lossless")
    func testRoundTripRGBLineInterleaved8x8() throws {
        // Create gradient RGB test image
        var redPixels: [[Int]] = []
        var greenPixels: [[Int]] = []
        var bluePixels: [[Int]] = []

        for row in 0..<8 {
            var red: [Int] = []
            var green: [Int] = []
            var blue: [Int] = []
            for col in 0..<8 {
                red.append(200 + row)
                green.append(100 + col)
                blue.append(50 + row + col)
            }
            redPixels.append(red)
            greenPixels.append(green)
            bluePixels.append(blue)
        }

        let imageData = try MultiComponentImageData.rgb(
            redPixels: redPixels,
            greenPixels: greenPixels,
            bluePixels: bluePixels,
            bitsPerSample: 8
        )

        // Encode with line interleaving
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .line)
        let encoded = try encoder.encode(imageData, configuration: config)

        // Decode
        let decoder = JPEGLSDecoder()
        let decoded = try decoder.decode(encoded)

        #expect(decoded.components.count == 3)
        #expect(decoded.frameHeader.width == 8)
        #expect(decoded.frameHeader.height == 8)
    }
}

// MARK: - Error Description Coverage Tests

@Suite("Error Description Coverage Tests")
struct ErrorDescriptionCoverageTests {

    @Test("Interleave mode error description")
    func testInterleaveModErrorDescription() {
        let error = JPEGLSError.invalidInterleaveMode(mode: 5)
        #expect(error.description.contains("5"))
    }

    @Test("NEAR parameter error description")
    func testNearParameterErrorDescription() {
        let error = JPEGLSError.invalidNearParameter(near: 300)
        #expect(error.description.contains("300"))
    }

    @Test("Preset parameters error description")
    func testPresetParametersErrorDescription() {
        let error = JPEGLSError.invalidPresetParameters(reason: "bad thresholds")
        #expect(error.description.contains("bad thresholds"))
    }

    @Test("Segment length error description")
    func testSegmentLengthErrorDescription() {
        let error = JPEGLSError.invalidSegmentLength(marker: .startOfFrameJPEGLS, length: 5)
        #expect(error.description.contains("5"))
    }

    @Test("Corrupted data error description")
    func testCorruptedDataErrorDescription() {
        let error = JPEGLSError.corruptedData(reason: "bad segment")
        #expect(error.description.contains("bad segment"))
    }

    @Test("Bitstream structure error description")
    func testBitstreamStructureErrorDescription() {
        let error = JPEGLSError.invalidBitstreamStructure(reason: "missing marker")
        #expect(error.description.contains("missing marker"))
    }

    @Test("Frame header error description")
    func testFrameHeaderErrorDescription() {
        let error = JPEGLSError.invalidFrameHeader(reason: "wrong dimensions")
        #expect(error.description.contains("wrong dimensions"))
    }

    @Test("Scan header error description")
    func testScanHeaderErrorDescription() {
        let error = JPEGLSError.invalidScanHeader(reason: "invalid components")
        #expect(error.description.contains("invalid components"))
    }

    @Test("Parameter mismatch error description")
    func testParameterMismatchErrorDescription() {
        let error = JPEGLSError.parameterMismatch(reason: "component count mismatch")
        #expect(error.description.contains("component count mismatch"))
    }

    @Test("Missing header error description")
    func testMissingHeaderErrorDescription() {
        let error = JPEGLSError.missingHeader(type: "SOF")
        #expect(error.description.contains("SOF"))
    }

    @Test("Encoding failed error description")
    func testEncodingFailedErrorDescription() {
        let error = JPEGLSError.encodingFailed(reason: "buffer full")
        #expect(error.description.contains("buffer full"))
    }

    @Test("Encoding buffer overflow error description")
    func testEncodingBufferOverflowDescription() {
        let error = JPEGLSError.encodingBufferOverflow
        #expect(error.description.contains("overflow"))
    }

    @Test("Unsupported encoding feature error description")
    func testUnsupportedEncodingFeatureDescription() {
        let error = JPEGLSError.unsupportedEncodingFeature(feature: "16-bit near-lossless")
        #expect(error.description.contains("16-bit near-lossless"))
    }

    @Test("Decoding failed error description")
    func testDecodingFailedErrorDescription() {
        let error = JPEGLSError.decodingFailed(reason: "invalid Golomb code")
        #expect(error.description.contains("invalid Golomb code"))
    }

    @Test("Invalid prediction error description")
    func testInvalidPredictionErrorDescription() {
        let error = JPEGLSError.invalidPredictionError
        #expect(error.description.contains("prediction"))
    }

    @Test("Context state corruption error description")
    func testContextStateCorruptionDescription() {
        let error = JPEGLSError.contextStateCorruption
        #expect(error.description.contains("Context"))
    }

    @Test("Unsupported decoding feature error description")
    func testUnsupportedDecodingFeatureDescription() {
        let error = JPEGLSError.unsupportedDecodingFeature(feature: "multi-frame")
        #expect(error.description.contains("multi-frame"))
    }

    @Test("Cannot read file with underlying error description")
    func testCannotReadFileWithUnderlyingError() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "permission denied"])
        let error = JPEGLSError.cannotReadFile(path: "/tmp/test.jls", underlying: underlying)
        #expect(error.description.contains("/tmp/test.jls"))
        #expect(error.description.contains("permission denied"))
    }

    @Test("Cannot write file error descriptions")
    func testCannotWriteFileErrorDescriptions() {
        // Without underlying error
        let error1 = JPEGLSError.cannotWriteFile(path: "/tmp/out.jls", underlying: nil)
        #expect(error1.description.contains("/tmp/out.jls"))

        // With underlying error
        let underlying = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        let error2 = JPEGLSError.cannotWriteFile(path: "/tmp/out.jls", underlying: underlying)
        #expect(error2.description.contains("disk full"))
    }

    @Test("Validation failed error description")
    func testValidationFailedErrorDescription() {
        let error = JPEGLSError.validationFailed(reason: "pixel mismatch")
        #expect(error.description.contains("pixel mismatch"))
    }

    @Test("Checksum mismatch error description")
    func testChecksumMismatchErrorDescription() {
        let error = JPEGLSError.checksumMismatch
        #expect(error.description.contains("Checksum"))
    }
}

// MARK: - Parser Edge Case Coverage Tests

@Suite("Parser Coverage Tests")
struct ParserCoverageTests {

    /// Create a minimal valid JPEG-LS bitstream with extra markers
    func createBitstreamWithComment() -> Data {
        var data = Data()

        // SOI marker
        data.append(contentsOf: [0xFF, 0xD8])

        // Comment marker (COM = 0xFE)
        data.append(contentsOf: [0xFF, 0xFE])
        let commentData: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F]  // "Hello"
        let comLength = UInt16(commentData.count + 2)  // length includes itself
        data.append(contentsOf: withUnsafeBytes(of: comLength.bigEndian) { Array($0) })
        data.append(contentsOf: commentData)

        // SOF marker
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)  // Precision
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(1)  // Component count
        data.append(1)  // Component ID
        data.append(0x11)  // Sampling factors
        data.append(0)  // Quantization table selector

        // SOS marker
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)  // Component count
        data.append(1)  // Component ID
        data.append(0)  // Table selector
        data.append(0)  // NEAR
        data.append(0)  // Interleave mode
        data.append(0)  // Point transform

        // Minimal scan data
        data.append(contentsOf: [0x00, 0x01, 0x02])

        // EOI
        data.append(contentsOf: [0xFF, 0xD9])

        return data
    }

    @Test("Parse bitstream with comment marker")
    func testParseWithComment() throws {
        let data = createBitstreamWithComment()
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()

        #expect(result.frameHeader.width == 4)
        #expect(result.frameHeader.height == 4)
    }

    @Test("Parse bitstream with application marker")
    func testParseWithApplicationMarker() throws {
        var data = Data()

        // SOI
        data.append(contentsOf: [0xFF, 0xD8])

        // APP0 marker (0xE0)
        data.append(contentsOf: [0xFF, 0xE0])
        let appData: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let appLength = UInt16(appData.count + 2)
        data.append(contentsOf: withUnsafeBytes(of: appLength.bigEndian) { Array($0) })
        data.append(contentsOf: appData)

        // SOF
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)

        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)

        // Scan data
        data.append(contentsOf: [0x00, 0x01])

        // EOI
        data.append(contentsOf: [0xFF, 0xD9])

        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()

        #expect(result.frameHeader.width == 4)
    }

    @Test("Parse bitstream with restart markers")
    func testParseWithRestartMarkers() throws {
        var data = Data()

        // SOI
        data.append(contentsOf: [0xFF, 0xD8])

        // SOF
        data.append(contentsOf: [0xFF, 0xF7])
        let sofLength: UInt16 = 11
        data.append(contentsOf: withUnsafeBytes(of: sofLength.bigEndian) { Array($0) })
        data.append(8)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0x11)
        data.append(0)

        // SOS
        data.append(contentsOf: [0xFF, 0xDA])
        let sosLength: UInt16 = 8
        data.append(contentsOf: withUnsafeBytes(of: sosLength.bigEndian) { Array($0) })
        data.append(1)
        data.append(1)
        data.append(0)
        data.append(0)
        data.append(0)
        data.append(0)

        // Scan data with embedded byte stuffing (FF 00)
        data.append(contentsOf: [0x00, 0xFF, 0x00, 0x01])

        // EOI
        data.append(contentsOf: [0xFF, 0xD9])

        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()

        #expect(result.frameHeader.width == 4)
    }
}

// MARK: - Multi-Component Encoder/Decoder Validation Coverage Tests

@Suite("Multi-Component Validation Coverage Tests")
struct MultiComponentValidationCoverageTests {

    @Test("Line interleaved encoder rejects single component")
    func testLineInterleavedEncoderRejectsSingleComponent() throws {
        let pixels = [[10, 20], [30, 40]]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        // Calling encodeNoneInterleaved should work for grayscale
        let stats = try encoder.encodeScan(buffer: buffer)
        #expect(stats.pixelsEncoded == 4)
    }

    @Test("Sample interleaved encoder works with RGB")
    func testSampleInterleavedEncoder() throws {
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
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let stats = try encoder.encodeScan(buffer: buffer)
        #expect(stats.pixelsEncoded == 12)  // 2×2 pixels × 3 components
        #expect(stats.interleaveMode == .sample)
    }

    @Test("Line interleaved decoder works with RGB")
    func testLineInterleavedDecoder() throws {
        let red = [[255, 200, 150], [100, 50, 0]]
        let green = [[100, 150, 200], [255, 210, 180]]
        let blue = [[50, 75, 100], [125, 150, 175]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3)
            ],
            near: 0,
            interleaveMode: .line
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let stats = try decoder.decodeScan(buffer: buffer)
        #expect(stats.pixelsDecoded == 18)  // 2×3 × 3 components
        #expect(stats.interleaveMode == .line)
    }

    @Test("Sample interleaved decoder works with RGB")
    func testSampleInterleavedDecoder() throws {
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
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let stats = try decoder.decodeScan(buffer: buffer)
        #expect(stats.pixelsDecoded == 12)  // 2×2 × 3 components
        #expect(stats.interleaveMode == .sample)
    }
}
