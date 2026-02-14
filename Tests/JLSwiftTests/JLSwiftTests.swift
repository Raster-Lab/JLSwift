import Testing
@testable import JLSwift

@Suite("JLSwift Module Tests")
struct JLSwiftTests {
    @Test("Version is set correctly")
    func version() {
        #expect(JLSwift.version == "0.1.0")
    }
}
