/// Tests for JPEG-LS scan header

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Scan Header Tests")
struct JPEGLSScanHeaderTests {
    @Test("Create valid grayscale lossless scan header")
    func testGrayscaleLossless() throws {
        let header = try JPEGLSScanHeader.grayscaleLossless()
        
        #expect(header.componentCount == 1)
        #expect(header.components.count == 1)
        #expect(header.components[0].id == 1)
        #expect(header.near == 0)
        #expect(header.interleaveMode == .none)
        #expect(header.isLossless)
        #expect(!header.isNearLossless)
    }
    
    @Test("Create valid RGB lossless scan header")
    func testRGBLossless() throws {
        let header = try JPEGLSScanHeader.rgbLossless()
        
        #expect(header.componentCount == 3)
        #expect(header.components.count == 3)
        #expect(header.components[0].id == 1)
        #expect(header.components[1].id == 2)
        #expect(header.components[2].id == 3)
        #expect(header.near == 0)
        #expect(header.interleaveMode == .sample)
        #expect(header.isLossless)
        #expect(!header.isNearLossless)
    }
    
    @Test("Create near-lossless scan header")
    func testNearLossless() throws {
        let header = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 5,
            interleaveMode: .none
        )
        
        #expect(header.near == 5)
        #expect(!header.isLossless)
        #expect(header.isNearLossless)
    }
    
    @Test("Valid NEAR parameter range (0-255)")
    func testValidNearRange() throws {
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 0,
            interleaveMode: .none
        )
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 128,
            interleaveMode: .none
        )
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 255,
            interleaveMode: .none
        )
    }
    
    @Test("Invalid NEAR parameter throws error")
    func testInvalidNearParameter() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: -1,
                interleaveMode: .none
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: 256,
                interleaveMode: .none
            )
        }
    }
    
    @Test("Invalid component count throws error")
    func testInvalidComponentCount() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 0,
                components: [],
                near: 0,
                interleaveMode: .none
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 5,
                components: [.init(id: 1), .init(id: 2), .init(id: 3), .init(id: 4), .init(id: 5)],
                near: 0,
                interleaveMode: .none
            )
        }
    }
    
    @Test("Component count mismatch throws error")
    func testComponentCountMismatch() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 3,
                components: [.init(id: 1), .init(id: 2)],  // Only 2 components
                near: 0,
                interleaveMode: .sample
            )
        }
    }
    
    @Test("Invalid interleave mode for component count")
    func testInvalidInterleaveMode() {
        // Line interleave requires multiple components
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: 0,
                interleaveMode: .line
            )
        }
        
        // Sample interleave requires multiple components
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: 0,
                interleaveMode: .sample
            )
        }
    }
    
    @Test("Valid interleave modes")
    func testValidInterleaveModes() throws {
        // None is valid for single component
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 0,
            interleaveMode: .none
        )
        
        // Line and sample are valid for multiple components
        _ = try JPEGLSScanHeader(
            componentCount: 3,
            components: [.init(id: 1), .init(id: 2), .init(id: 3)],
            near: 0,
            interleaveMode: .line
        )
        _ = try JPEGLSScanHeader(
            componentCount: 3,
            components: [.init(id: 1), .init(id: 2), .init(id: 3)],
            near: 0,
            interleaveMode: .sample
        )
    }
    
    @Test("Valid point transform range")
    func testValidPointTransform() throws {
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 0,
            interleaveMode: .none,
            pointTransform: 0
        )
        _ = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 0,
            interleaveMode: .none,
            pointTransform: 15
        )
    }
    
    @Test("Invalid point transform throws error")
    func testInvalidPointTransform() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: 0,
                interleaveMode: .none,
                pointTransform: -1
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [.init(id: 1)],
                near: 0,
                interleaveMode: .none,
                pointTransform: 16
            )
        }
    }
    
    @Test("Validate against compatible frame header")
    func testValidateAgainstFrameHeader() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        
        // Should not throw
        try scanHeader.validate(against: frameHeader)
    }
    
    @Test("Validate detects missing component in frame")
    func testValidateDetectsMissingComponent() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        // Try to use RGB scan header with grayscale frame
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        
        #expect(throws: JPEGLSError.self) {
            try scanHeader.validate(against: frameHeader)
        }
    }
    
    @Test("Validate detects non-interleaved scan with multiple components")
    func testValidateNonInterleavedMultipleComponents() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        // Non-interleaved scan with 3 components is invalid
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [.init(id: 1), .init(id: 2), .init(id: 3)],
            near: 0,
            interleaveMode: .none
        )
        
        #expect(throws: JPEGLSError.self) {
            try scanHeader.validate(against: frameHeader)
        }
    }
    
    @Test("Validate detects interleaved scan with missing components")
    func testValidateInterleavedMissingComponents() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 640,
            height: 480
        )
        
        // Interleaved scan should include all frame components
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 2,
            components: [.init(id: 1), .init(id: 2)],
            near: 0,
            interleaveMode: .sample
        )
        
        #expect(throws: JPEGLSError.self) {
            try scanHeader.validate(against: frameHeader)
        }
    }
    
    @Test("Description includes key information")
    func testDescription() throws {
        let header = try JPEGLSScanHeader(
            componentCount: 3,
            components: [.init(id: 1), .init(id: 2), .init(id: 3)],
            near: 5,
            interleaveMode: .sample
        )
        
        let desc = header.description
        #expect(desc.contains("3"))
        #expect(desc.contains("5"))
        #expect(desc.contains("Sample") || desc.contains("sample"))
    }
    
    @Test("Equality works correctly")
    func testEquality() throws {
        let header1 = try JPEGLSScanHeader.grayscaleLossless()
        let header2 = try JPEGLSScanHeader.grayscaleLossless()
        let header3 = try JPEGLSScanHeader(
            componentCount: 1,
            components: [.init(id: 1)],
            near: 5,
            interleaveMode: .none
        )
        
        #expect(header1 == header2)
        #expect(header1 != header3)
    }
    
    @Test("Interleave mode description")
    func testInterleaveModDescription() {
        #expect(JPEGLSInterleaveMode.none.description == "None")
        #expect(JPEGLSInterleaveMode.line.description == "Line")
        #expect(JPEGLSInterleaveMode.sample.description == "Sample")
    }
    
    @Test("Interleave mode validity check")
    func testInterleaveModeValidity() {
        #expect(JPEGLSInterleaveMode.none.isValid(forComponentCount: 1))
        #expect(JPEGLSInterleaveMode.none.isValid(forComponentCount: 3))
        
        #expect(!JPEGLSInterleaveMode.line.isValid(forComponentCount: 1))
        #expect(JPEGLSInterleaveMode.line.isValid(forComponentCount: 3))
        
        #expect(!JPEGLSInterleaveMode.sample.isValid(forComponentCount: 1))
        #expect(JPEGLSInterleaveMode.sample.isValid(forComponentCount: 3))
    }
}
