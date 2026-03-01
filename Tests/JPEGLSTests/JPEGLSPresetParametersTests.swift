/// Tests for JPEG-LS preset parameters

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Preset Parameters Tests")
struct JPEGLSPresetParametersTests {
    @Test("Default parameters for 8-bit images")
    func testDefault8Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
        
        // Per ITU-T.87 Table C.2: factor = floor((255+128)/256) = 1
        // T1 = CLAMP(factor*(3-2)+2, 1, 255) = CLAMP(3, 1, 255) = 3
        // T2 = CLAMP(factor*(7-3)+3, T1, 255) = CLAMP(7, 3, 255) = 7
        // T3 = CLAMP(factor*(21-4)+4, T2, 255) = CLAMP(21, 7, 255) = 21
        #expect(params.maxValue == 255)
        #expect(params.threshold1 == 3)
        #expect(params.threshold2 == 7)
        #expect(params.threshold3 == 21)
        #expect(params.reset == 64)
        #expect(params.isDefault(forBitsPerSample: 8))
    }
    
    @Test("Default parameters for 12-bit images")
    func testDefault12Bit() throws {
        let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 12)
        
        // Per ITU-T.87 Table C.2: factor = floor((4095+128)/256) = 16
        // T1 = CLAMP(16*(3-2)+2, 1, 4095) = CLAMP(18, 1, 4095) = 18
        // T2 = CLAMP(16*(7-3)+3, T1, 4095) = CLAMP(67, 18, 4095) = 67
        // T3 = CLAMP(16*(21-4)+4, T2, 4095) = CLAMP(276, 67, 4095) = 276
        #expect(params.maxValue == 4095)
        #expect(params.threshold1 == 18)
        #expect(params.threshold2 == 67)
        #expect(params.threshold3 == 276)
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
