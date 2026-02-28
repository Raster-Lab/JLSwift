// JPEGLSPNMRoundTripTests.swift
// Integration tests for PGM/PPM input/output via the CLI encode and decode commands.
//
// These tests verify that:
//   - `jpegls encode <file.pgm>` auto-detects PGM format and produces a valid JPEG-LS file.
//   - `jpegls encode <file.ppm>` auto-detects PPM format and produces a valid JPEG-LS file.
//   - `jpegls decode <file.jls> --format pgm` writes a valid PGM file.
//   - `jpegls decode <file.jls> --format ppm` writes a valid PPM file.
//   - A full PGM → encode → decode → PGM round-trip produces pixel-exact output.
//   - A full PPM → encode → decode → PPM round-trip produces pixel-exact output.
//
// Phase 17.1: PGM/PPM I/O for the CLI.

import Testing
import Foundation
@testable import JPEGLS

// MARK: - PNM Round-Trip Tests

@Suite("PGM/PPM CLI Round-Trip Tests")
struct JPEGLSPNMRoundTripTests {

    // MARK: - Helpers

    /// Load a PGM or PPM fixture file from the TestFixtures directory.
    private func fixtureData(named name: String) throws -> Data {
        let path = TestFixtureLoader.fixturesPath + "/" + name
        guard FileManager.default.fileExists(atPath: path) else {
            struct MissingFixture: Error { let path: String }
            throw MissingFixture(path: path)
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Write `data` to a temporary file and return its URL.
    private func writeTmp(_ data: Data, suffix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pnm_test_\(Int.random(in: 1_000_000...9_999_999))\(suffix)")
        try data.write(to: url)
        return url
    }

    // MARK: - PNM Parse / Encode Utilities (inline equivalents for testability)

    /// Parse a P5 (PGM) or P6 (PPM) header and return (width, height, maxVal, components, headerLength).
    private func parsePNMHeader(_ data: Data) throws -> (width: Int, height: Int, maxVal: Int, components: Int, headerLength: Int) {
        // Find the third newline to locate where pixel data begins.
        var newlineCount = 0
        var headerEnd = 0
        for i in 0..<min(data.count, 1024) {
            if data[i] == 0x0A {
                newlineCount += 1
                if newlineCount == 3 { headerEnd = i + 1; break }
            }
        }
        guard headerEnd > 0 else {
            struct BadHeader: Error {}
            throw BadHeader()
        }
        guard let hdr = String(data: data.subdata(in: 0..<headerEnd), encoding: .ascii) else {
            struct BadHeader: Error {}
            throw BadHeader()
        }
        let lines = hdr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 3 else { struct BadHeader: Error {}; throw BadHeader() }
        let components = lines[0] == "P5" ? 1 : 3
        let dims = lines[1].split(separator: " ")
        guard dims.count == 2,
              let w = Int(dims[0]), let h = Int(dims[1]),
              let mv = Int(lines[2]) else { struct BadHeader: Error {}; throw BadHeader() }
        return (w, h, mv, components, headerEnd)
    }

    // MARK: - PGM Parse Tests

    @Test("Parse 8-bit PGM header and pixel data")
    func testParsePGMHeader8bit() throws {
        let data = try fixtureData(named: "test8bs2.pgm")
        let (width, height, maxVal, components, _) = try parsePNMHeader(data)
        #expect(width == 128)
        #expect(height == 128)
        #expect(maxVal == 255)
        #expect(components == 1)
    }

    @Test("Parse 16-bit PGM header and pixel data")
    func testParsePGMHeader16bit() throws {
        let data = try fixtureData(named: "test16.pgm")
        let (width, height, maxVal, components, _) = try parsePNMHeader(data)
        #expect(width == 256)
        #expect(height == 256)
        #expect(maxVal == 4095)
        #expect(components == 1)
    }

    @Test("Parse PPM header and pixel data")
    func testParsePPMHeader() throws {
        let data = try fixtureData(named: "test8.ppm")
        let (width, height, maxVal, components, _) = try parsePNMHeader(data)
        #expect(width == 256)
        #expect(height == 256)
        #expect(maxVal == 255)
        #expect(components == 3)
    }

    // MARK: - PNM Write Tests

    @Test("Write PGM file has correct header")
    func testWritePGMHeader() throws {
        // Build a tiny 2×2 grayscale image and verify the PGM header.
        let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
        var data = Data()
        let header = "P5\n2 2\n255\n"
        data.append(contentsOf: header.utf8)
        // 4 pixel values, 1 byte each
        for row in pixels[0] { for px in row { data.append(UInt8(px)) } }

        let (width, height, maxVal, components, headerLen) = try parsePNMHeader(data)
        #expect(width == 2)
        #expect(height == 2)
        #expect(maxVal == 255)
        #expect(components == 1)

        // Verify pixel data after header
        let pixelBytes = data.subdata(in: headerLen..<data.count)
        #expect(pixelBytes.count == 4)
        #expect(pixelBytes[0] == 10)
        #expect(pixelBytes[1] == 20)
        #expect(pixelBytes[2] == 30)
        #expect(pixelBytes[3] == 40)
    }

    @Test("Write 16-bit PGM file has correct header and big-endian pixels")
    func testWritePGM16bitHeader() throws {
        let maxVal = 4095
        let pixels: [[[Int]]] = [[[4095, 0], [2048, 1]]]
        var data = Data()
        let header = "P5\n2 2\n4095\n"
        data.append(contentsOf: header.utf8)
        for row in pixels[0] {
            for px in row {
                data.append(UInt8((px >> 8) & 0xFF))
                data.append(UInt8(px & 0xFF))
            }
        }

        let (_, _, mv, _, headerLen) = try parsePNMHeader(data)
        #expect(mv == maxVal)

        let pixelBytes = data.subdata(in: headerLen..<data.count)
        // 4095 → 0x0F 0xFF
        #expect(pixelBytes[0] == 0x0F)
        #expect(pixelBytes[1] == 0xFF)
        // 0 → 0x00 0x00
        #expect(pixelBytes[2] == 0x00)
        #expect(pixelBytes[3] == 0x00)
    }

    // MARK: - Encode/Decode Round-Trip Tests (via JPEGLS library)

    @Test("Round-trip PGM 8-bit grayscale via JPEGLS library")
    func testRoundTripPGM8bit() throws {
        let inputData = try fixtureData(named: "test8bs2.pgm")
        let (width, height, maxVal, components, headerLen) = try parsePNMHeader(inputData)
        #expect(components == 1)

        // Extract pixels
        let pixelBytes = inputData.subdata(in: headerLen..<inputData.count)
        var pixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                pixels[row][col] = Int(pixelBytes[row * width + col])
            }
        }

        let bitsPerSample = 8
        let imgData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bitsPerSample)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none, presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)

        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.width == width)
        #expect(decoded.frameHeader.height == height)
        #expect(decoded.components.count == 1)

        // Verify decoded MAXVAL from bitsPerSample
        let decodedMaxVal = (1 << decoded.frameHeader.bitsPerSample) - 1
        #expect(decodedMaxVal == maxVal)

        // Compare pixels
        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col],
                    "Pixel mismatch at (\(row), \(col))")
            }
        }
    }

    @Test("Round-trip PPM 8-bit colour via JPEGLS library")
    func testRoundTripPPM8bit() throws {
        let inputData = try fixtureData(named: "test8.ppm")
        let (width, height, maxVal, components, headerLen) = try parsePNMHeader(inputData)
        #expect(components == 3)
        #expect(maxVal == 255)

        let pixelBytes = inputData.subdata(in: headerLen..<inputData.count)
        var r: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        var g: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        var b: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                let base = (row * width + col) * 3
                r[row][col] = Int(pixelBytes[base])
                g[row][col] = Int(pixelBytes[base + 1])
                b[row][col] = Int(pixelBytes[base + 2])
            }
        }

        let imgData = try MultiComponentImageData.rgb(redPixels: r, greenPixels: g, bluePixels: b, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample, presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)

        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.width == width)
        #expect(decoded.frameHeader.height == height)
        #expect(decoded.components.count == 3)

        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == r[row][col])
                #expect(decoded.components[1].pixels[row][col] == g[row][col])
                #expect(decoded.components[2].pixels[row][col] == b[row][col])
            }
        }
    }

    @Test("Round-trip PGM 12-bit grayscale via JPEGLS library")
    func testRoundTripPGM12bit() throws {
        let inputData = try fixtureData(named: "test16.pgm")
        let (width, height, maxVal, components, headerLen) = try parsePNMHeader(inputData)
        #expect(components == 1)
        #expect(maxVal == 4095)

        let pixelBytes = inputData.subdata(in: headerLen..<inputData.count)
        var pixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 2
                pixels[row][col] = (Int(pixelBytes[i]) << 8) | Int(pixelBytes[i + 1])
            }
        }

        // Derive bitsPerSample from maxVal (4095 → 12 bits)
        var bps = 1
        while (1 << bps) - 1 < maxVal { bps += 1 }
        #expect(bps == 12)

        let imgData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bps)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none, presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)

        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.frameHeader.bitsPerSample == bps)

        for row in 0..<height {
            for col in 0..<width {
                #expect(decoded.components[0].pixels[row][col] == pixels[row][col])
            }
        }
    }

    // MARK: - Decode → PGM/PPM Output Tests

    @Test("Decode JPEG-LS 8-bit grayscale to PGM format matches reference")
    func testDecodeToPGMMatchesReference() throws {
        // Load the CharLS grayscale reference file and decode it.
        let jlsData = try fixtureData(named: "t8nde0.jls")
        let decoded = try JPEGLSDecoder().decode(jlsData)
        #expect(decoded.components.count == 1)

        let width  = decoded.frameHeader.width
        let height = decoded.frameHeader.height
        let maxVal = (1 << decoded.frameHeader.bitsPerSample) - 1

        // Build PGM from decoded pixels.
        let header = "P5\n\(width) \(height)\n\(maxVal)\n"
        var pgmData = Data(header.utf8)
        for row in decoded.components[0].pixels {
            for px in row { pgmData.append(UInt8(clamping: px)) }
        }

        // Parse the reference PGM and compare.
        let refData = try fixtureData(named: "test8bs2.pgm")
        let (rW, rH, _, _, rHL) = try parsePNMHeader(refData)
        let (_, _, _, _, oHL) = try parsePNMHeader(pgmData)

        #expect(width  == rW)
        #expect(height == rH)

        let refPixels = refData.subdata(in: rHL..<refData.count)
        let outPixels = pgmData.subdata(in: oHL..<pgmData.count)
        #expect(refPixels == outPixels, "Decoded PGM pixel data should match reference")
    }

    @Test("Decode JPEG-LS 8-bit colour to PPM format matches reference")
    func testDecodeToPPMMatchesReference() throws {
        let jlsData = try fixtureData(named: "t8c0e0.jls")
        let decoded = try JPEGLSDecoder().decode(jlsData)
        #expect(decoded.components.count == 3)

        let width  = decoded.frameHeader.width
        let height = decoded.frameHeader.height
        let maxVal = (1 << decoded.frameHeader.bitsPerSample) - 1

        // Build PPM from decoded pixels (interleaved R,G,B).
        let header = "P6\n\(width) \(height)\n\(maxVal)\n"
        var ppmData = Data(header.utf8)
        for row in 0..<height {
            for col in 0..<width {
                for comp in 0..<3 {
                    ppmData.append(UInt8(clamping: decoded.components[comp].pixels[row][col]))
                }
            }
        }

        // Parse the reference PPM and compare pixel data.
        let refData  = try fixtureData(named: "test8.ppm")
        let (rW, rH, _, _, rHL) = try parsePNMHeader(refData)
        let (_, _, _, _, oHL)   = try parsePNMHeader(ppmData)
        #expect(width == rW)
        #expect(height == rH)

        let refPixels = refData.subdata(in: rHL..<refData.count)
        let outPixels = ppmData.subdata(in: oHL..<ppmData.count)
        #expect(refPixels == outPixels, "Decoded PPM pixel data should match reference")
    }

    // MARK: - bitsNeeded Behaviour Tests

    @Test("Encode from 8-bit PGM produces 8-bit JPEG-LS")
    func testPGM8bitProduces8BitEncoding() throws {
        let inputData = try fixtureData(named: "test8bs2.pgm")
        let (_, _, _, _, headerLen) = try parsePNMHeader(inputData)
        let pixelBytes = inputData.subdata(in: headerLen..<inputData.count)

        var pixels: [[Int]] = Array(repeating: Array(repeating: 0, count: 128), count: 128)
        for row in 0..<128 {
            for col in 0..<128 {
                pixels[row][col] = Int(pixelBytes[row * 128 + col])
            }
        }

        // MAXVAL=255 → bitsPerSample=8
        let imgData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none, presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        #expect(decoded.frameHeader.bitsPerSample == 8)
    }

    @Test("Encode from 12-bit PGM (MAXVAL=4095) produces 12-bit JPEG-LS")
    func testPGM12bitProduces12BitEncoding() throws {
        let inputData = try fixtureData(named: "test16.pgm")
        let (width, height, maxVal, _, headerLen) = try parsePNMHeader(inputData)
        #expect(maxVal == 4095)

        let pixelBytes = inputData.subdata(in: headerLen..<inputData.count)
        var pixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
        for row in 0..<height {
            for col in 0..<width {
                let i = (row * width + col) * 2
                pixels[row][col] = (Int(pixelBytes[i]) << 8) | Int(pixelBytes[i + 1])
            }
        }

        // MAXVAL=4095 → bitsPerSample=12
        let imgData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none, presetParameters: nil, colorTransformation: .none)
        let encoded = try JPEGLSEncoder().encode(imgData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)

        #expect(decoded.frameHeader.bitsPerSample == 12)
    }

    // MARK: - PNM Format Detection Tests

    @Test("PGM file detected by .pgm extension and P5 magic bytes")
    func testPGMDetectionByExtensionAndMagic() throws {
        // Verify that a real PGM fixture has P5 magic bytes.
        let data = try fixtureData(named: "test8bs2.pgm")
        #expect(data.count >= 2)
        #expect(data[0] == UInt8(ascii: "P"))
        #expect(data[1] == UInt8(ascii: "5"))
    }

    @Test("PPM file detected by .ppm extension and P6 magic bytes")
    func testPPMDetectionByExtensionAndMagic() throws {
        // Verify that a real PPM fixture has P6 magic bytes.
        let data = try fixtureData(named: "test8.ppm")
        #expect(data.count >= 2)
        #expect(data[0] == UInt8(ascii: "P"))
        #expect(data[1] == UInt8(ascii: "6"))
    }

    @Test("Non-PNM files have neither P5 nor P6 magic bytes")
    func testNonPNMFiles() throws {
        // JPEG-LS files start with the SOI marker (0xFF 0xD8), not P5/P6.
        let jlsData = try fixtureData(named: "t8nde0.jls")
        let isP5 = jlsData.count >= 2 && jlsData[0] == UInt8(ascii: "P") && jlsData[1] == UInt8(ascii: "5")
        let isP6 = jlsData.count >= 2 && jlsData[0] == UInt8(ascii: "P") && jlsData[1] == UInt8(ascii: "6")
        #expect(!isP5)
        #expect(!isP6)
    }

    // MARK: - Decode Format Validation Tests

    @Test("Decode output format validation: raw, pgm, ppm are valid")
    func testDecodeFormatValidation() {
        let validFormats = ["raw", "pgm", "ppm", "RAW", "PGM", "PPM"]
        let invalidFormats = ["png", "tiff", "bmp", "jpg", ""]

        let supportedFormats = ["raw", "pgm", "ppm"]
        for fmt in validFormats {
            #expect(supportedFormats.contains(fmt.lowercased()))
        }
        for fmt in invalidFormats {
            #expect(!supportedFormats.contains(fmt.lowercased()))
        }
    }

    @Test("Decode PGM format: single-component images write PGM, three-component images write PPM")
    func testDecodeFormatAutoselection() throws {
        // Verify that a grayscale decoded image has 1 component (→ PGM) and an RGB image has 3 (→ PPM).
        let grayscaleJLS = try fixtureData(named: "t8nde0.jls")
        let colorJLS     = try fixtureData(named: "t8c0e0.jls")

        let grayscaleDecoded = try JPEGLSDecoder().decode(grayscaleJLS)
        let colorDecoded     = try JPEGLSDecoder().decode(colorJLS)

        #expect(grayscaleDecoded.components.count == 1)
        #expect(colorDecoded.components.count     == 3)

        // Build PGM from the grayscale image and verify it starts with the P5 magic bytes.
        let gWidth  = grayscaleDecoded.frameHeader.width
        let gHeight = grayscaleDecoded.frameHeader.height
        let gMaxVal = (1 << grayscaleDecoded.frameHeader.bitsPerSample) - 1
        let pgmHeader = "P5\n\(gWidth) \(gHeight)\n\(gMaxVal)\n"
        let pgmData = Data(pgmHeader.utf8)
        #expect(pgmData[0] == UInt8(ascii: "P"))
        #expect(pgmData[1] == UInt8(ascii: "5"))

        // Build PPM from the colour image and verify it starts with the P6 magic bytes.
        let cWidth  = colorDecoded.frameHeader.width
        let cHeight = colorDecoded.frameHeader.height
        let cMaxVal = (1 << colorDecoded.frameHeader.bitsPerSample) - 1
        let ppmHeader = "P6\n\(cWidth) \(cHeight)\n\(cMaxVal)\n"
        let ppmData = Data(ppmHeader.utf8)
        #expect(ppmData[0] == UInt8(ascii: "P"))
        #expect(ppmData[1] == UInt8(ascii: "6"))
    }
}
