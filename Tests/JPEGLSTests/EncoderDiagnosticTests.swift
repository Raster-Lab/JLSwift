// Temporary diagnostic test - to be placed in Tests/JPEGLSTests/
import Testing
import Foundation
@testable import JPEGLS

@Suite("Encoder Diagnostic")
struct EncoderDiagnosticTests {
    
    static let fixturesPath: String = {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if let bundlePath = Bundle.module.resourceURL?.path {
            return bundlePath + "/TestFixtures"
        }
        #endif
        return "Tests/JPEGLSTests/TestFixtures"
    }()

    @Test("Diagnose test16.pgm encoder vs CharLS reference")
    func testEncoderDivergence() throws {
        let fixturesPath = Self.fixturesPath
        
        guard let pgmData = try? Data(contentsOf: URL(fileURLWithPath: "\(fixturesPath)/test16.pgm")),
              let jlsData = try? Data(contentsOf: URL(fileURLWithPath: "\(fixturesPath)/t16e0.jls")) else {
            print("Could not load test fixtures - skipping")
            return
        }
        
        // Parse PGM
        var headerEnd = 0
        var newlines = 0
        for i in 0..<min(100, pgmData.count) {
            if pgmData[i] == 10 {
                newlines += 1
                if newlines == 3 { headerEnd = i + 1; break }
            }
        }
        
        let w = 256, h = 256
        var pixels: [[Int]] = []
        let pixelData = pgmData.subdata(in: headerEnd..<pgmData.count)
        for row in 0..<h {
            var rowPixels: [Int] = []
            for col in 0..<w {
                let offset = (row * w + col) * 2
                let hi = Int(pixelData[offset])
                let lo = Int(pixelData[offset + 1])
                rowPixels.append((hi << 8) | lo)
            }
            pixels.append(rowPixels)
        }
        
        print("First pixel of test16.pgm: \(pixels[0][0])")
        print("Pixel [0][1]: \(pixels[0][1])")
        print("Pixel [1][0]: \(pixels[1][0])")
        
        // Encode
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Find scan data start in CharLS reference
        var jlsScanStart = 0
        var idx = 0
        while idx < jlsData.count - 1 {
            if jlsData[idx] == 0xFF {
                let marker = jlsData[idx + 1]
                if marker == 0xDA {
                    let len = Int(jlsData[idx + 2]) << 8 | Int(jlsData[idx + 3])
                    jlsScanStart = idx + 2 + len
                    break
                } else if marker == 0xD8 || marker == 0xD9 {
                    idx += 2
                } else {
                    let len = Int(jlsData[idx + 2]) << 8 | Int(jlsData[idx + 3])
                    idx += 2 + len
                }
            } else { idx += 1 }
        }
        
        // Find scan data start in JLSwift encoded
        var encScanStart = 0
        idx = 0
        while idx < encoded.count - 1 {
            if encoded[idx] == 0xFF {
                let marker = encoded[idx + 1]
                if marker == 0xDA {
                    let len = Int(encoded[idx + 2]) << 8 | Int(encoded[idx + 3])
                    encScanStart = idx + 2 + len
                    break
                } else if marker == 0xD8 || marker == 0xD9 {
                    idx += 2
                } else {
                    let len = Int(encoded[idx + 2]) << 8 | Int(encoded[idx + 3])
                    idx += 2 + len
                }
            } else { idx += 1 }
        }
        
        // CharLS scan data excludes last 2 bytes (FF D9 = EOI)
        let jlsScan = Array(jlsData[jlsScanStart..<jlsData.count-2])
        let encScan = Array(encoded[encScanStart..<encoded.count-2])
        
        print("CharLS scan size: \(jlsScan.count) bytes")
        print("JLSwift scan size: \(encScan.count) bytes")
        
        var firstDiff = -1
        for i in 0..<min(jlsScan.count, encScan.count) {
            if jlsScan[i] != encScan[i] {
                firstDiff = i
                break
            }
        }
        
        if firstDiff == -1 {
            print("✓ Scan data matches!")
            #expect(true)
        } else {
            print("✗ First divergence at scan byte \(firstDiff)")
            let start = max(0, firstDiff - 5)
            let end = min(jlsScan.count, firstDiff + 20)
            print("CharLS [\(start)..\(end)]: \(Array(jlsScan[start..<end]).map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("JLSwift[\(start)..\(end)]: \(Array(encScan[start..<end]).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }
}
