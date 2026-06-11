/// Tests for DRI/RSTm restart-interval support: encoder emission, decoder
/// consumption, bitstream structure, and configuration validation.

import Foundation
import Testing
@testable import JPEGLS

@Suite("Restart interval (DRI/RSTm) support")
struct JPEGLSRestartIntervalTests {

    // MARK: - Helpers

    private func makeGradientPixels(width: Int, height: Int, maxValue: Int) -> [[Int]] {
        (0..<height).map { row in
            (0..<width).map { col in (row * 3 + col * 7) % (maxValue + 1) }
        }
    }

    /// Pixels with large flat regions to exercise run mode across interval
    /// boundaries.
    private func makeRunHeavyPixels(width: Int, height: Int, value: Int) -> [[Int]] {
        (0..<height).map { row in
            (0..<width).map { col in
                (row / 10) % 3 == 0 ? value : (col % 5 == 0 ? value : value / 2)
            }
        }
    }

    private func countRestartMarkers(_ data: Data) -> [UInt8] {
        var found: [UInt8] = []
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && (0xD0...0xD7).contains(bytes[i + 1]) {
                found.append(bytes[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return found
    }

    private func roundTrip(
        pixels: [[Int]], bitsPerSample: Int, restartInterval: Int
    ) throws -> (encoded: Data, decoded: [[Int]]) {
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels, bitsPerSample: bitsPerSample
        )
        let config = try JPEGLSEncoder.Configuration(restartInterval: restartInterval)
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        return (encoded, decoded.components[0].pixels)
    }

    // MARK: - Round-trip

    @Test("8-bit lossless round-trip with restart interval")
    func roundTrip8Bit() throws {
        let pixels = makeGradientPixels(width: 100, height: 64, maxValue: 255)
        let (encoded, decoded) = try roundTrip(pixels: pixels, bitsPerSample: 8, restartInterval: 16)
        #expect(decoded == pixels)
        // 64 lines / 16 per interval = 4 intervals -> 3 RST markers D0,D1,D2.
        #expect(countRestartMarkers(encoded) == [0xD0, 0xD1, 0xD2])
    }

    @Test("16-bit lossless round-trip with restart interval")
    func roundTrip16Bit() throws {
        let pixels = makeGradientPixels(width: 80, height: 50, maxValue: 4095)
        let (encoded, decoded) = try roundTrip(pixels: pixels, bitsPerSample: 12, restartInterval: 8)
        #expect(decoded == pixels)
        // ceil(50 / 8) = 7 intervals -> 6 RST markers.
        #expect(countRestartMarkers(encoded).count == 6)
    }

    @Test("Run-heavy image round-trips across interval boundaries")
    func roundTripRunHeavy() throws {
        let pixels = makeRunHeavyPixels(width: 64, height: 48, value: 200)
        let (_, decoded) = try roundTrip(pixels: pixels, bitsPerSample: 8, restartInterval: 7)
        #expect(decoded == pixels)
    }

    @Test("Marker index cycles through D0–D7 for many intervals")
    func markerCycling() throws {
        let pixels = makeGradientPixels(width: 16, height: 40, maxValue: 255)
        let (encoded, decoded) = try roundTrip(pixels: pixels, bitsPerSample: 8, restartInterval: 2)
        #expect(decoded == pixels)
        // 20 intervals -> 19 markers cycling D0..D7,D0..
        let markers = countRestartMarkers(encoded)
        #expect(markers.count == 19)
        for (i, marker) in markers.enumerated() {
            #expect(marker == 0xD0 + UInt8(i % 8))
        }
    }

    @Test("Restart interval >= height emits DRI but no RST markers")
    func intervalLargerThanImage() throws {
        let pixels = makeGradientPixels(width: 32, height: 16, maxValue: 255)
        let (encoded, decoded) = try roundTrip(pixels: pixels, bitsPerSample: 8, restartInterval: 64)
        #expect(decoded == pixels)
        #expect(countRestartMarkers(encoded).isEmpty)
    }

    @Test("Restart encoding is deterministic (parallel intervals)")
    func deterministicOutput() throws {
        let pixels = makeGradientPixels(width: 128, height: 96, maxValue: 1023)
        let (first, _) = try roundTrip(pixels: pixels, bitsPerSample: 10, restartInterval: 8)
        let (second, _) = try roundTrip(pixels: pixels, bitsPerSample: 10, restartInterval: 8)
        #expect(first == second)
    }

    @Test("Multi-component non-interleaved scans each honour the restart interval")
    func multiComponentNonInterleaved() throws {
        let red = makeGradientPixels(width: 40, height: 32, maxValue: 255)
        let green = makeRunHeavyPixels(width: 40, height: 32, value: 99)
        let blue = makeGradientPixels(width: 40, height: 32, maxValue: 200)
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red, greenPixels: green, bluePixels: blue, bitsPerSample: 8
        )
        let config = try JPEGLSEncoder.Configuration(
            interleaveMode: .none, restartInterval: 8
        )
        let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == red)
        #expect(decoded.components[1].pixels == green)
        #expect(decoded.components[2].pixels == blue)
        // 3 scans x (32/8 - 1) = 9 RST markers in total.
        #expect(countRestartMarkers(encoded).count == 9)
    }

    @Test("DRI marker segment is present and carries the interval")
    func driSegment() throws {
        let pixels = makeGradientPixels(width: 32, height: 32, maxValue: 255)
        let (encoded, _) = try roundTrip(pixels: pixels, bitsPerSample: 8, restartInterval: 5)
        let parser = JPEGLSParser(data: encoded)
        let result = try parser.parse()
        #expect(result.restartInterval == 5)
    }

    // MARK: - Validation

    @Test("Restart interval with near-lossless throws")
    func nearLosslessRejected() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(near: 2, restartInterval: 8)
        }
    }

    @Test("Restart interval with interleaved mode throws")
    func interleavedRejected() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(interleaveMode: .line, restartInterval: 8)
        }
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(interleaveMode: .sample, restartInterval: 8)
        }
    }

    @Test("Out-of-range restart interval throws")
    func outOfRangeRejected() {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(restartInterval: -1)
        }
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSEncoder.Configuration(restartInterval: 65536)
        }
    }
}
