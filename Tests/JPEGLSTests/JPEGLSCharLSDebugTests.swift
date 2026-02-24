import Testing
import Foundation
@testable import JPEGLS

struct JPEGLSCharLSDebugTests {
    @Test("Debug first pixel of t16e0.jls")
    func testT16e0FirstPixel() throws {
        let jlsData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/t16e0.jls"))
        let pgmData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/test16.pgm"))
        
        // Parse PGM header
        var hdrLen = 0; var lf = 0
        for i in 0..<pgmData.count { if pgmData[i] == 10 { lf += 1; if lf == 3 { hdrLen = i+1; break } } }
        let exp0 = Int(pgmData[hdrLen]) * 256 + Int(pgmData[hdrLen+1])
        let exp1 = Int(pgmData[hdrLen+2]) * 256 + Int(pgmData[hdrLen+3])
        let exp256 = Int(pgmData[hdrLen + 256*2]) * 256 + Int(pgmData[hdrLen + 256*2 + 1])
        print("Expected pixel (0,0)=\(exp0), (0,1)=\(exp1), (1,0)=\(exp256)")
        
        let decoder = JPEGLSDecoder()
        do {
            let result = try decoder.decode(jlsData)
            let comp = result.components[0]
            print("Decoded (0,0)=\(comp.pixels[0][0]), (0,1)=\(comp.pixels[0][1])")
            if result.components[0].pixels.count > 1 {
                print("Decoded (1,0)=\(comp.pixels[1][0])")
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    @Test("Debug first pixel of t8c0e0.jls (non-interleaved 8-bit, should pass)")
    func testT8c0e0FirstPixel() throws {
        let jlsData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/t8c0e0.jls"))
        let ppmData = try Data(contentsOf: URL(fileURLWithPath: "/home/runner/work/JLSwift/JLSwift/Tests/JPEGLSTests/TestFixtures/test8.ppm"))
        
        // Parse PPM header (P6\n256 256\n255\n = 15 bytes)
        var hdrLen = 0; var lf = 0
        for i in 0..<ppmData.count { if ppmData[i] == 10 { lf += 1; if lf == 3 { hdrLen = i+1; break } } }
        let expR0 = Int(ppmData[hdrLen])
        let expG0 = Int(ppmData[hdrLen+1])
        let expB0 = Int(ppmData[hdrLen+2])
        print("Expected RGB (0,0)=(\(expR0),\(expG0),\(expB0))")
        
        let decoder = JPEGLSDecoder()
        do {
            let result = try decoder.decode(jlsData)
            let r = result.components.first(where: { $0.id == 1 })?.pixels[0][0] ?? -1
            let g = result.components.first(where: { $0.id == 2 })?.pixels[0][0] ?? -1
            let b = result.components.first(where: { $0.id == 3 })?.pixels[0][0] ?? -1
            print("Decoded RGB (0,0)=(\(r),\(g),\(b))")
        } catch {
            print("Error: \(error)")
        }
    }
}
