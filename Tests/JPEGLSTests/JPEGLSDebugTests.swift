import Testing
import Foundation
@testable import JPEGLS

struct JPEGLSDebugTests {
    @Test("Inspect what decoder reads for t16e0")
    func testInspectT16e0() throws {
        let jlsData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/t16e0.jls"))
        
        // Manually figure out what scan data the decoder extracts
        // We know: SOI(2) + SOF(13) + SOS(10) = scan starts at byte 25
        let scanStart = 25
        print("Scan data starts at offset \(scanStart)")
        print("Scan bytes 25-44:", jlsData[scanStart..<scanStart+20].map{ String(format:"%02X",$0) }.joined(separator:" "))
        
        // Now simulate what readRunLength + decodeRunInterruption does
        // For 12-bit lossless: RANGE=4096, aInit=64, runIndex=0, J[0]=0
        // Pixel(0,0): all neighbors=0, gradients=0, run mode, runValue=a=0
        // Read run length:
        let byte0 = jlsData[scanStart]
        let firstBit = (byte0 >> 7) & 1  // MSB first
        print("First bit (run term J=0): \(firstBit) → runLength=0")
        
        // So runLength=0, interruption at col=0, Rb=0 (row=0), RItype=1
        // k for RItype=1: A[1]=64, N[1]=1 → k=6
        // Read Golomb k=6 from bits 1+
        var pos = 1  // bit position in stream (after run term bit)
        var zeros = 0
        var byte = jlsData[scanStart + pos/8]
        var bitInByte = 7 - (pos % 8)  // MSB first
        
        while true {
            let bit = (byte >> bitInByte) & 1
            if bit == 1 { break }
            zeros += 1
            pos += 1
            if pos % 8 == 0 { byte = jlsData[scanStart + pos/8] }
            bitInByte = 7 - (pos % 8)
        }
        pos += 1  // Skip the 1 bit
        print("Golomb unary zeros: \(zeros)")
        
        // Read 6 remainder bits
        var rem = 0
        for _ in 0..<6 {
            if pos % 8 == 0 { byte = jlsData[scanStart + pos/8] }
            bitInByte = 7 - (pos % 8)
            let b = Int((byte >> bitInByte) & 1)
            rem = (rem << 1) | b
            pos += 1
        }
        print("Golomb k=6 remainder: \(rem)")
        let merrval = (zeros << 6) | rem
        print("MErrval=\(merrval) for pixel(0,0)")
        
        // Decode with RItype=1, Ra=0, Rb=0, sign=+1, prediction=0
        let errval = merrval % 2 == 0 ? merrval/2 : -((merrval+1)/2)
        print("errval=\(errval)")
        var sample = 0 + 1 * errval  // sign=+1, prediction=0
        let range = 4096
        if sample < 0 { sample += range }
        if sample > 4095 { sample -= range }
        print("Decoded pixel(0,0) = \(sample), expected = 1963")
    }
}
