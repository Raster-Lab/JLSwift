import Testing
import Foundation
@testable import JPEGLS

@Test("Debug flat region")
func debugFlatRegion() throws {
    let pixels: [[Int]] = [
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
    ]
    
    let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
    let encoded = try encoder.encode(imageData, configuration: config)
    
    print("Encoded size: \(encoded.count) bytes")
    let hexStr = encoded.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("Hex: \(hexStr)")
}

@Test("Debug decode flat region")
func debugDecodeFlat() throws {
    let pixels: [[Int]] = [
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
        [128, 128, 128, 128, 138, 148, 158, 168],
    ]
    
    let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
    let encoded = try encoder.encode(imageData, configuration: config)
    
    // Try to decode it
    let decoder = JPEGLSDecoder()
    do {
        let decoded = try decoder.decode(encoded)
        print("Decoded OK: \(decoded.components[0].pixels[0][0])")
    } catch {
        print("Decode error: \(error)")
        // Print byte count
        let hexStr = encoded.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("Hex (\(encoded.count) bytes): \(hexStr)")
    }
}
