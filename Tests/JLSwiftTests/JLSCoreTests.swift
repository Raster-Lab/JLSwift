import Testing
@testable import JLSwift

@Suite("JLSCore Module Tests")
struct JLSCoreTests {
    @Test("Version is set correctly")
    func version() {
        #expect(JLSCore.version == "0.1.0")
    }
}
