import Testing
import Foundation
@testable import JPEGLS

@Suite("Updated File Tests")
struct UpdatedFileTests {
    @Test("Decode individual files after fix")
    func decodeIndividualFiles() throws {
        let decoder = JPEGLSDecoder()
        let files = ["t16e0.jls", "t8c0e0.jls", "t8c1e0.jls", "t8c2e0.jls", "t8c0e3.jls", "t16e3.jls", "t8c1e3.jls", "t8c2e3.jls"]
        
        for filename in files {
            do {
                let data = try TestFixtureLoader.loadFixture(named: filename)
                let result = try decoder.decode(data)
                print("\(filename): OK (\(result.frameHeader.width)x\(result.frameHeader.height) \(result.components.count) comp)")
            } catch {
                print("\(filename): FAIL (\(error))")
            }
        }
    }
}
