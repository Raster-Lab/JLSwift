/// Tests for JPEG-LS error types

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Error Tests")
struct JPEGLSErrorTests {
    @Test("Error descriptions are informative")
    func testErrorDescriptions() {
        let error1 = JPEGLSError.invalidDimensions(width: 0, height: 100)
        #expect(error1.description.contains("0×100"))
        
        let error2 = JPEGLSError.invalidComponentCount(count: 5)
        #expect(error2.description.contains("5"))
        #expect(error2.description.contains("1-4"))
        
        let error3 = JPEGLSError.invalidBitsPerSample(bits: 17)
        #expect(error3.description.contains("17"))
        #expect(error3.description.contains("2-16"))
        
        let error4 = JPEGLSError.prematureEndOfStream
        #expect(error4.description.contains("Premature"))
    }
    
    @Test("Marker errors include marker information")
    func testMarkerErrors() {
        let error1 = JPEGLSError.markerNotFound(expected: .startOfImage)
        #expect(error1.description.contains("0xFFD8"))
        
        let error2 = JPEGLSError.invalidMarker(byte1: 0xFF, byte2: 0x99)
        #expect(error2.description.contains("0xFF"))
        #expect(error2.description.contains("99"))
    }
    
    @Test("File errors include paths")
    func testFileErrors() {
        let error1 = JPEGLSError.fileNotFound(path: "/tmp/test.jls")
        #expect(error1.description.contains("/tmp/test.jls"))
        
        let error2 = JPEGLSError.cannotReadFile(path: "/tmp/test.jls", underlying: nil)
        #expect(error2.description.contains("/tmp/test.jls"))
    }
    
    @Test("Buffer errors include size information")
    func testBufferErrors() {
        let error = JPEGLSError.insufficientBuffer(required: 1024, available: 512)
        #expect(error.description.contains("1024"))
        #expect(error.description.contains("512"))
    }
    
    @Test("Internal errors include reason")
    func testInternalErrors() {
        let error = JPEGLSError.internalError(reason: "test reason")
        #expect(error.description.contains("test reason"))
    }
}
