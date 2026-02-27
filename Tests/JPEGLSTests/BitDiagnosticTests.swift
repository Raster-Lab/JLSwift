import Testing
import Foundation
@testable import JPEGLS

@Suite("Bit Diagnostic")
struct BitDiagnosticTests {
    
    static let fixturesPath: String = {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if let bundlePath = Bundle.module.resourceURL?.path {
            return bundlePath + "/TestFixtures"
        }
        #endif
        return "Tests/JPEGLSTests/TestFixtures"
    }()

    @Test("Find bit-level divergence")
    func testBitDivergence() throws {
        let fixturesPath = Self.fixturesPath
        
        guard let pgmData = try? Data(contentsOf: URL(fileURLWithPath: "\(fixturesPath)/test16.pgm")),
              let jlsData = try? Data(contentsOf: URL(fileURLWithPath: "\(fixturesPath)/t16e0.jls")) else {
            print("Files not found"); return
        }
        
        // Parse PGM
        var headerEnd = 0; var newlines = 0
        for i in 0..<min(100, pgmData.count) {
            if pgmData[i] == 10 { newlines += 1; if newlines == 3 { headerEnd = i + 1; break } }
        }
        let w = 256, h = 256
        var pixels: [[Int]] = []
        let pixelData = pgmData.subdata(in: headerEnd..<pgmData.count)
        for row in 0..<h {
            var rowPixels: [Int] = []
            for col in 0..<w {
                let offset = (row * w + col) * 2
                rowPixels.append((Int(pixelData[offset]) << 8) | Int(pixelData[offset + 1]))
            }
            pixels.append(rowPixels)
        }
        
        // Encode
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 12)
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: 0)
        let encoded = try encoder.encode(imageData, configuration: config)
        
        // Find scan data starts
        func findScanStart(_ data: Data) -> Int {
            var idx = 0
            while idx < data.count - 1 {
                if data[idx] == 0xFF {
                    let marker = data[idx + 1]
                    if marker == 0xDA {
                        let len = Int(data[idx + 2]) << 8 | Int(data[idx + 3])
                        return idx + 2 + len
                    } else if marker == 0xD8 || marker == 0xD9 { idx += 2 }
                    else { let len = Int(data[idx + 2]) << 8 | Int(data[idx + 3]); idx += 2 + len }
                } else { idx += 1 }
            }
            return -1
        }
        
        let jlsStart = findScanStart(jlsData)
        let encStart = findScanStart(encoded)
        
        let jlsScan = Array(jlsData[jlsStart..<jlsData.count-2])
        let encScan = Array(encoded[encStart..<encoded.count-2])
        
        // Find first byte divergence
        var firstByteDiff = -1
        for i in 0..<min(jlsScan.count, encScan.count) {
            if jlsScan[i] != encScan[i] { firstByteDiff = i; break }
        }
        
        print("First byte divergence: \(firstByteDiff)")
        print("Total bits before divergence: \(firstByteDiff * 8)")
        
        // Now find first BIT divergence (could be earlier, just within the same byte)
        var firstBitDiff = -1
        // Actually byte diff IS bit diff since we compare bytes
        
        if firstByteDiff >= 5 {
            // Look at context: bytes around divergence
            let start = max(0, firstByteDiff - 5)
            let end = min(jlsScan.count, firstByteDiff + 20)
            print("CharLS bytes [\(start)..\(end)]: \(Array(jlsScan[start..<end]).map { String(format: "%02x", $0) }.joined(separator: " "))")
            print("JLSwift bytes [\(start)..<\(end)]: \(Array(encScan[start..<end]).map { String(format: "%02x", $0) }.joined(separator: " "))")
            
            // Print binary representation of divergence bytes
            let charLSByte = jlsScan[firstByteDiff]
            let jlswiftByte = encScan[firstByteDiff]
            print("CharLS byte \(firstByteDiff): \(String(charLSByte, radix: 2).padLeft(toLength: 8, withPad: "0")) = \(String(format: "%02x", charLSByte))")
            print("JLSwift byte \(firstByteDiff): \(String(jlswiftByte, radix: 2).padLeft(toLength: 8, withPad: "0")) = \(String(format: "%02x", jlswiftByte))")
            
            // Print 5 bytes before divergence in binary
            for i in (start..<firstByteDiff) {
                print("Both byte \(i): \(String(jlsScan[i], radix: 2).padLeft(toLength: 8, withPad: "0")) = \(String(format: "%02x", jlsScan[i]))")
            }
            
            // Is JLSwift = CharLS shifted?
            let charLSBits = Array(jlsScan[firstByteDiff..<min(firstByteDiff+8, jlsScan.count)])
            let encBits = Array(encScan[firstByteDiff..<min(firstByteDiff+8, encScan.count)])
            
            // Check if enc is CharLS shifted by 1 bit
            var charLSBitsStr = ""
            for b in charLSBits { charLSBitsStr += String(b, radix: 2).padLeft(toLength: 8, withPad: "0") }
            var encBitsStr = ""
            for b in encBits { encBitsStr += String(b, radix: 2).padLeft(toLength: 8, withPad: "0") }
            print("CharLS bits: \(charLSBitsStr)")
            print("JLSwift bits: \(encBitsStr)")
            
            // Check shift
            let charLSShift1 = "0" + charLSBitsStr.prefix(charLSBitsStr.count - 1)
            print("CharLS>>1:   \(charLSShift1)")
            print("Match shift-1: \(encBitsStr.prefix(32) == charLSShift1.prefix(32))")
        }
    }
}

extension String {
    func padLeft(toLength length: Int, withPad pad: String) -> String {
        let paddingLength = length - self.count
        if paddingLength <= 0 { return self }
        return String(repeating: pad, count: paddingLength) + self
    }
}
