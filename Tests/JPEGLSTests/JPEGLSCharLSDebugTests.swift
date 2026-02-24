import Testing
import Foundation
@testable import JPEGLS

struct JPEGLSCharLSDebugTests {
    @Test("Debug t16e0 scan data extraction")
    func testScanDataExtraction() throws {
        let jlsData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/t16e0.jls"))
        
        // Parse to get scan headers
        let parser = JPEGLSParser(data: jlsData)
        let result = try parser.parse()
        
        print("Frame: \(result.frameHeader.width)x\(result.frameHeader.height), bpp=\(result.frameHeader.bitsPerSample)")
        print("Scan headers: \(result.scanHeaders.count)")
        for sh in result.scanHeaders {
            print("  ScanHeader: near=\(sh.near), ILV=\(sh.interleaveMode), comps=\(sh.componentCount)")
        }
        
        // Check what presetParameters we're using
        let params: JPEGLSPresetParameters
        if let custom = result.presetParameters {
            params = custom
            print("Custom preset: MAXVAL=\(custom.maxValue), T1=\(custom.threshold1), T2=\(custom.threshold2), T3=\(custom.threshold3)")
        } else {
            params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: result.frameHeader.bitsPerSample)
            print("Default preset: MAXVAL=\(params.maxValue), T1=\(params.threshold1), T2=\(params.threshold2), T3=\(params.threshold3)")
        }
        
        // Compute aInit for 12-bit
        let range = params.maxValue + 1
        let aInit = max(2, (range + 32) / 64)
        print("RANGE=\(range), aInit=\(aInit)")
        
        // Initial Golomb k for run interruption
        var k = 0
        var thresh = 1  // N=1
        while thresh < aInit && k < 16 { thresh <<= 1; k += 1 }
        print("Initial run interruption k=\(k)")
    }
}
