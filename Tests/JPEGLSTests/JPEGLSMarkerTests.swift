/// Tests for JPEG-LS marker types

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Marker Tests")
struct JPEGLSMarkerTests {
    @Test("SOI marker has correct value")
    func testSOIMarker() {
        #expect(JPEGLSMarker.startOfImage.rawValue == 0xD8)
        let (prefix, code) = JPEGLSMarker.startOfImage.bytes
        #expect(prefix == 0xFF)
        #expect(code == 0xD8)
    }
    
    @Test("EOI marker has correct value")
    func testEOIMarker() {
        #expect(JPEGLSMarker.endOfImage.rawValue == 0xD9)
        let (prefix, code) = JPEGLSMarker.endOfImage.bytes
        #expect(prefix == 0xFF)
        #expect(code == 0xD9)
    }
    
    @Test("SOF55 marker has correct value")
    func testSOF55Marker() {
        #expect(JPEGLSMarker.startOfFrameJPEGLS.rawValue == 0xF7)
        let (prefix, code) = JPEGLSMarker.startOfFrameJPEGLS.bytes
        #expect(prefix == 0xFF)
        #expect(code == 0xF7)
    }
    
    @Test("SOS marker has correct value")
    func testSOSMarker() {
        #expect(JPEGLSMarker.startOfScan.rawValue == 0xDA)
    }
    
    @Test("LSE marker has correct value")
    func testLSEMarker() {
        #expect(JPEGLSMarker.jpegLSExtension.rawValue == 0xF8)
    }
    
    @Test("Markers without length field")
    func testMarkersWithoutLength() {
        #expect(!JPEGLSMarker.startOfImage.hasLength)
        #expect(!JPEGLSMarker.endOfImage.hasLength)
        #expect(!JPEGLSMarker.restart0.hasLength)
        #expect(!JPEGLSMarker.restart7.hasLength)
    }
    
    @Test("Markers with length field")
    func testMarkersWithLength() {
        #expect(JPEGLSMarker.startOfFrameJPEGLS.hasLength)
        #expect(JPEGLSMarker.startOfScan.hasLength)
        #expect(JPEGLSMarker.jpegLSExtension.hasLength)
        #expect(JPEGLSMarker.applicationMarker0.hasLength)
        #expect(JPEGLSMarker.comment.hasLength)
    }
    
    @Test("All restart markers have correct values")
    func testRestartMarkers() {
        #expect(JPEGLSMarker.restart0.rawValue == 0xD0)
        #expect(JPEGLSMarker.restart1.rawValue == 0xD1)
        #expect(JPEGLSMarker.restart2.rawValue == 0xD2)
        #expect(JPEGLSMarker.restart3.rawValue == 0xD3)
        #expect(JPEGLSMarker.restart4.rawValue == 0xD4)
        #expect(JPEGLSMarker.restart5.rawValue == 0xD5)
        #expect(JPEGLSMarker.restart6.rawValue == 0xD6)
        #expect(JPEGLSMarker.restart7.rawValue == 0xD7)
    }
    
    @Test("Extension type codes")
    func testExtensionTypes() {
        #expect(JPEGLSExtensionType.presetCodingParameters.rawValue == 0x01)
        #expect(JPEGLSExtensionType.mappingTable.rawValue == 0x02)
        #expect(JPEGLSExtensionType.mappingTableContinuation.rawValue == 0x03)
        #expect(JPEGLSExtensionType.extendedDimensions.rawValue == 0x04)
    }
}
