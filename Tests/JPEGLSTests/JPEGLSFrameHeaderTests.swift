/// Tests for JPEG-LS frame header

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Frame Header Tests")
struct JPEGLSFrameHeaderTests {
    @Test("Create valid grayscale frame header")
    func testGrayscaleHeader() throws {
        let header = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        #expect(header.bitsPerSample == 8)
        #expect(header.width == 640)
        #expect(header.height == 480)
        #expect(header.componentCount == 1)
        #expect(header.components.count == 1)
        #expect(header.components[0].id == 1)
    }
    
    @Test("Create valid RGB frame header")
    func testRGBHeader() throws {
        let header = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 1920,
            height: 1080
        )
        
        #expect(header.bitsPerSample == 8)
        #expect(header.width == 1920)
        #expect(header.height == 1080)
        #expect(header.componentCount == 3)
        #expect(header.components.count == 3)
        #expect(header.components[0].id == 1)
        #expect(header.components[1].id == 2)
        #expect(header.components[2].id == 3)
    }
    
    @Test("Valid bits per sample range (2-16)")
    func testValidBitsPerSample() throws {
        _ = try JPEGLSFrameHeader.grayscale(bitsPerSample: 2, width: 100, height: 100)
        _ = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 100, height: 100)
        _ = try JPEGLSFrameHeader.grayscale(bitsPerSample: 12, width: 100, height: 100)
        _ = try JPEGLSFrameHeader.grayscale(bitsPerSample: 16, width: 100, height: 100)
    }
    
    @Test("Invalid bits per sample throws error")
    func testInvalidBitsPerSample() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(bitsPerSample: 1, width: 100, height: 100)
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(bitsPerSample: 17, width: 100, height: 100)
        }
    }
    
    @Test("Invalid dimensions throw error")
    func testInvalidDimensions() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 0, height: 100)
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 100, height: 0)
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 65536, height: 100)
        }
    }
    
    @Test("Maximum valid dimensions")
    func testMaximumDimensions() throws {
        let header = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 65535,
            height: 65535
        )
        #expect(header.width == 65535)
        #expect(header.height == 65535)
    }
    
    @Test("Invalid component count throws error")
    func testInvalidComponentCount() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 100,
                componentCount: 0,
                components: []
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 100,
                componentCount: 5,
                components: [
                    .init(id: 1),
                    .init(id: 2),
                    .init(id: 3),
                    .init(id: 4),
                    .init(id: 5)
                ]
            )
        }
    }
    
    @Test("Component count mismatch throws error")
    func testComponentCountMismatch() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSFrameHeader(
                bitsPerSample: 8,
                height: 100,
                width: 100,
                componentCount: 3,
                components: [.init(id: 1), .init(id: 2)]  // Only 2 components
            )
        }
    }
    
    @Test("Component specification has correct default values")
    func testComponentSpecDefaults() {
        let spec = JPEGLSFrameHeader.ComponentSpec(id: 1)
        #expect(spec.id == 1)
        #expect(spec.horizontalSamplingFactor == 1)
        #expect(spec.verticalSamplingFactor == 1)
    }
    
    @Test("Component specification with custom sampling factors")
    func testComponentSpecCustomSampling() {
        let spec = JPEGLSFrameHeader.ComponentSpec(
            id: 1,
            horizontalSamplingFactor: 2,
            verticalSamplingFactor: 2
        )
        #expect(spec.id == 1)
        #expect(spec.horizontalSamplingFactor == 2)
        #expect(spec.verticalSamplingFactor == 2)
    }
    
    @Test("Description includes key information")
    func testDescription() throws {
        let header = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 12,
            width: 1024,
            height: 768
        )
        
        let desc = header.description
        #expect(desc.contains("1024"))
        #expect(desc.contains("768"))
        #expect(desc.contains("12"))
        #expect(desc.contains("1"))  // component count
    }
    
    @Test("Equality works correctly")
    func testEquality() throws {
        let header1 = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        let header2 = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        let header3 = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 800,
            height: 600
        )
        
        #expect(header1 == header2)
        #expect(header1 != header3)
    }
}
