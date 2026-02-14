/// Tests for JPEG-LS preset parameters

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Preset Parameters Tests")
struct JPEGLSPresetParametersTests {
    @Test("Default parameters for 8-bit images")
    func testDefault8Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        
        #expect(params.maxValue == 255)
        #expect(params.threshold1 == 2)  // max(2, (255 + 128) / 256) = max(2, 1) = 2
        #expect(params.threshold2 == 3)  // max(3, (255 + 64) / 128) = max(3, 2) = 3
        #expect(params.threshold3 == 4)  // max(4, (255 + 42) / 85) = max(4, 3) = 4
        #expect(params.reset == 64)
        #expect(params.isDefault(forBitsPerSample: 8))
    }
    
    @Test("Default parameters for 12-bit images")
    func testDefault12Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 12)
        
        #expect(params.maxValue == 4095)
        #expect(params.threshold1 == 16)  // max(2, (4095 + 128) / 256) = max(2, 16) = 16
        #expect(params.threshold2 == 32)  // max(3, (4095 + 64) / 128) = max(3, 32) = 32
        #expect(params.threshold3 == 48)  // max(4, (4095 + 42) / 85) = max(4, 48) = 48
        #expect(params.reset == 64)
        #expect(params.isDefault(forBitsPerSample: 12))
    }
    
    @Test("Default parameters for 16-bit images")
    func testDefault16Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 16)
        
        #expect(params.maxValue == 65535)
        #expect(params.reset == 64)
        #expect(params.isDefault(forBitsPerSample: 16))
    }
    
    @Test("Default parameters for 2-bit images (minimum)")
    func testDefault2Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 2)
        
        #expect(params.maxValue == 3)
        #expect(params.threshold1 >= 1 && params.threshold1 <= 3)
        #expect(params.threshold2 >= params.threshold1 && params.threshold2 <= 3)
        #expect(params.threshold3 >= params.threshold2 && params.threshold3 <= 3)
        #expect(params.reset == 64)
    }
    
    @Test("Invalid bits per sample throws error")
    func testInvalidBitsPerSample() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 1)
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 17)
        }
    }
    
    @Test("Custom parameters with valid values")
    func testCustomParameters() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 10,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        
        #expect(params.maxValue == 255)
        #expect(params.threshold1 == 10)
        #expect(params.threshold2 == 20)
        #expect(params.threshold3 == 30)
        #expect(params.reset == 64)
        #expect(!params.isDefault(forBitsPerSample: 8))
    }
    
    @Test("Invalid MAXVAL throws error")
    func testInvalidMaxValue() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 0,
                threshold1: 1,
                threshold2: 2,
                threshold3: 3,
                reset: 64
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 65536,
                threshold1: 1,
                threshold2: 2,
                threshold3: 3,
                reset: 64
            )
        }
    }
    
    @Test("Invalid threshold ordering throws error")
    func testInvalidThresholdOrdering() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 20,  // T1 > T2 is invalid
                threshold2: 10,
                threshold3: 30,
                reset: 64
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 10,
                threshold2: 30,  // T2 > T3 is invalid
                threshold3: 20,
                reset: 64
            )
        }
    }
    
    @Test("Invalid T1 range throws error")
    func testInvalidT1Range() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 0,  // T1 must be >= 1
                threshold2: 10,
                threshold3: 20,
                reset: 64
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 256,  // T1 must be <= MAXVAL
                threshold2: 256,
                threshold3: 256,
                reset: 64
            )
        }
    }
    
    @Test("Invalid RESET throws error")
    func testInvalidReset() {
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 10,
                threshold2: 20,
                threshold3: 30,
                reset: 2  // RESET must be >= 3
            )
        }
        #expect(throws: JPEGLSError.self) {
            try JPEGLSPresetParameters(
                maxValue: 255,
                threshold1: 10,
                threshold2: 20,
                threshold3: 30,
                reset: 256  // RESET must be <= 255
            )
        }
    }
    
    @Test("Description includes all parameters")
    func testDescription() throws {
        let params = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 10,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        
        let desc = params.description
        #expect(desc.contains("255"))
        #expect(desc.contains("10"))
        #expect(desc.contains("20"))
        #expect(desc.contains("30"))
        #expect(desc.contains("64"))
    }
    
    @Test("Equality works correctly")
    func testEquality() throws {
        let params1 = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 10,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        
        let params2 = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 10,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        
        let params3 = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 11,
            threshold2: 20,
            threshold3: 30,
            reset: 64
        )
        
        #expect(params1 == params2)
        #expect(params1 != params3)
    }
}
