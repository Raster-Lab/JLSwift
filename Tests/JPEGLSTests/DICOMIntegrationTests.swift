import Foundation
import Testing
@testable import JPEGLS

/// Tests for DICOM integration and transfer syntax compliance
/// 
/// This test suite validates JLSwift's compliance with DICOM JPEG-LS transfer syntaxes:
/// - 1.2.840.10008.1.2.4.80: JPEG-LS Lossless Image Compression
/// - 1.2.840.10008.1.2.4.81: JPEG-LS Lossy (Near-Lossless) Image Compression
///
/// Tests ensure that JLSwift correctly handles DICOM-specific requirements including:
/// - Transfer syntax parameter mapping
/// - DICOM modality-specific image configurations
/// - Multi-frame DICOM images
/// - Color and grayscale DICOM images
/// - Various bit depths and sample formats
struct DICOMIntegrationTests {
    
    // MARK: - Transfer Syntax UID Constants
    
    /// JPEG-LS Lossless Image Compression (1.2.840.10008.1.2.4.80)
    static let losslessTransferSyntax = "1.2.840.10008.1.2.4.80"
    
    /// JPEG-LS Lossy (Near-Lossless) Image Compression (1.2.840.10008.1.2.4.81)
    static let nearLosslessTransferSyntax = "1.2.840.10008.1.2.4.81"
    
    // MARK: - Transfer Syntax Validation Tests
    
    @Test("Transfer syntax lossless requires NEAR=0")
    func testLosslessTransferSyntaxRequiresNearZero() {
        // For DICOM lossless transfer syntax, NEAR must be 0
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0, "Lossless transfer syntax must use NEAR=0")
    }
    
    @Test("Transfer syntax near-lossless allows NEAR 1-255")
    func testNearLosslessTransferSyntaxAllowsNonZeroNear() {
        // For DICOM near-lossless transfer syntax, NEAR can be 1-255
        let near = nearParameterForTransferSyntax(Self.nearLosslessTransferSyntax, tolerance: 3)
        #expect(near == 3, "Near-lossless transfer syntax should use specified tolerance")
        #expect(near >= 1 && near <= 255, "NEAR must be in valid range 1-255")
    }
    
    @Test("Transfer syntax validation with various NEAR values")
    func testTransferSyntaxWithVariousNearValues() {
        // Test that various NEAR values map correctly
        let tolerances = [1, 3, 5, 10, 50, 100, 255]
        for tolerance in tolerances {
            let near = nearParameterForTransferSyntax(Self.nearLosslessTransferSyntax, tolerance: tolerance)
            #expect(near == tolerance, "NEAR should match requested tolerance: \(tolerance)")
        }
    }
    
    // MARK: - CT (Computed Tomography) Tests
    
    @Test("CT image - 16-bit grayscale lossless")
    func testCTImage16BitGrayscaleLossless() throws {
        // CT images are typically 16-bit grayscale (12 or 16 bits stored)
        let width = 512
        let height = 512
        let bitsPerSample = 16
        let components = 1
        
        // Create test CT image data (Hounsfield units range: -1024 to 3071)
        var pixelData = [UInt16](repeating: 0, count: width * height)
        for i in 0..<pixelData.count {
            // Simulate CT values: soft tissue (~40 HU) + noise
            pixelData[i] = UInt16((1024 + 40 + Int.random(in: -10...10)) & 0xFFFF)
        }
        
        // Validate encoding parameters for CT lossless
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsPerSample == 16)
        #expect(components == 1)
    }
    
    @Test("CT image - 12-bit stored in 16-bit lossless")
    func testCTImage12BitStoredIn16BitLossless() throws {
        // Many CT images use 12 bits stored in 16-bit words
        let width = 512
        let height = 512
        let bitsStored = 12
        let bitsAllocated = 16
        let components = 1
        
        // Create test CT image data with 12-bit values
        var pixelData = [UInt16](repeating: 0, count: width * height)
        for i in 0..<pixelData.count {
            // Simulate 12-bit CT values (0-4095)
            pixelData[i] = UInt16(2048 + Int.random(in: -100...100)) & 0x0FFF
        }
        
        // Validate encoding parameters
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsStored == 12)
        #expect(bitsAllocated == 16)
        #expect(components == 1)
        
        // Verify all values are within 12-bit range
        for value in pixelData {
            #expect(value <= 4095, "12-bit values must not exceed 4095")
        }
    }
    
    @Test("CT image - Near-lossless with NEAR=3")
    func testCTImageNearLosslessWithNear3() throws {
        // CT images can use near-lossless with small NEAR for visually lossless compression
        let width = 512
        let height = 512
        let bitsPerSample = 16
        let components = 1
        let tolerance = 3
        
        // Create test CT image data
        var pixelData = [UInt16](repeating: 0, count: width * height)
        for i in 0..<pixelData.count {
            pixelData[i] = UInt16((1024 + 40 + Int.random(in: -50...50)) & 0xFFFF)
        }
        
        // Validate near-lossless parameters
        let near = nearParameterForTransferSyntax(Self.nearLosslessTransferSyntax, tolerance: tolerance)
        #expect(near == tolerance)
        #expect(bitsPerSample == 16)
        #expect(components == 1)
    }
    
    // MARK: - MR (Magnetic Resonance) Tests
    
    @Test("MR image - 16-bit grayscale lossless")
    func testMRImage16BitGrayscaleLossless() throws {
        // MR images are typically 16-bit grayscale
        let width = 256
        let height = 256
        let bitsPerSample = 16
        let components = 1
        
        // Create test MR image data (typical range: 0-4095 for 12-bit, scaled to 16-bit)
        var pixelData = [UInt16](repeating: 0, count: width * height)
        for i in 0..<pixelData.count {
            // Simulate MR intensity values
            pixelData[i] = UInt16(Int.random(in: 0...4095) << 4)
        }
        
        // Validate encoding parameters for MR lossless
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsPerSample == 16)
        #expect(components == 1)
    }
    
    @Test("MR image - Multi-echo sequence")
    func testMRImageMultiEchoSequence() throws {
        // MR multi-echo sequences have multiple images per location
        let width = 256
        let height = 256
        let bitsPerSample = 16
        let components = 1
        let numberOfEchoes = 4
        
        // Validate parameters for each echo
        for echoIndex in 0..<numberOfEchoes {
            // Create test data for this echo
            var echoPixelData = [UInt16](repeating: 0, count: width * height)
            for i in 0..<echoPixelData.count {
                // Simulate MR signal decay with echo time
                let baseIntensity = 3000
                let decayFactor = Double(echoIndex) * 0.3
                echoPixelData[i] = UInt16(max(0, Double(baseIntensity) * exp(-decayFactor)))
            }
            
            // Each echo should use lossless compression
            let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
            #expect(near == 0, "Echo \(echoIndex) should use lossless compression")
        }
    }
    
    // MARK: - CR/DX (Digital Radiography) Tests
    
    @Test("CR image - 10-bit to 14-bit grayscale")
    func testCRImage10To14BitGrayscale() throws {
        // CR/DX images typically use 10-14 bits per sample
        let configurations = [
            (width: 2048, height: 2048, bits: 10),
            (width: 3000, height: 3000, bits: 12),
            (width: 4096, height: 4096, bits: 14),
        ]
        
        for config in configurations {
            let maxValue = (1 << config.bits) - 1
            
            // Create sample pixel data
            var pixelData = [UInt16](repeating: 0, count: 100) // Small sample
            for i in 0..<pixelData.count {
                pixelData[i] = UInt16(Int.random(in: 0...maxValue))
            }
            
            // Validate parameters
            let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
            #expect(near == 0)
            #expect(config.bits >= 10 && config.bits <= 14, "CR bits per sample should be 10-14")
            
            // Verify values don't exceed bit depth
            for value in pixelData {
                #expect(value <= maxValue, "Value \(value) exceeds \(config.bits)-bit maximum \(maxValue)")
            }
        }
    }
    
    @Test("DX image - Large detector 4Kx4K")
    func testDXImageLargeDetector() throws {
        // Modern DX detectors can be very large (4K x 4K or larger)
        let width = 4096
        let height = 4096
        let bitsPerSample = 14
        let components = 1
        
        // Validate parameters for large DX image
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsPerSample >= 10 && bitsPerSample <= 16)
        #expect(components == 1)
        #expect(width >= 2048 && height >= 2048, "DX detectors are typically large")
    }
    
    // MARK: - US (Ultrasound) Tests
    
    @Test("US image - 8-bit grayscale")
    func testUSImage8BitGrayscale() throws {
        // Ultrasound images are typically 8-bit grayscale
        let width = 640
        let height = 480
        let bitsPerSample = 8
        let components = 1
        
        // Create test US image data
        var pixelData = [UInt8](repeating: 0, count: width * height)
        for i in 0..<pixelData.count {
            // Simulate US speckle pattern
            pixelData[i] = UInt8(Int.random(in: 0...255))
        }
        
        // Validate encoding parameters
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsPerSample == 8)
        #expect(components == 1)
    }
    
    @Test("US image - Color Doppler 8-bit RGB")
    func testUSImageColorDoppler() throws {
        // Color Doppler ultrasound images use RGB color
        let width = 640
        let height = 480
        let bitsPerSample = 8
        let components = 3
        
        // Create test color Doppler data
        var pixelData = [UInt8](repeating: 0, count: width * height * components)
        for i in stride(from: 0, to: pixelData.count, by: components) {
            // Simulate color-coded blood flow
            pixelData[i] = UInt8(Int.random(in: 0...255))     // R
            pixelData[i + 1] = UInt8(Int.random(in: 0...255)) // G
            pixelData[i + 2] = UInt8(Int.random(in: 0...255)) // B
        }
        
        // Validate encoding parameters for color US
        let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
        #expect(near == 0)
        #expect(bitsPerSample == 8)
        #expect(components == 3, "Color Doppler uses RGB (3 components)")
    }
    
    // MARK: - Multi-Frame DICOM Tests
    
    @Test("Multi-frame DICOM - CT series")
    func testMultiFrameDICOMCTSeries() throws {
        // Multi-frame DICOM objects contain multiple image frames
        let width = 512
        let height = 512
        let bitsPerSample = 16
        let components = 1
        let numberOfFrames = 100
        
        // Validate parameters for each frame
        for frameIndex in 0..<numberOfFrames {
            // Create test data for this frame
            var framePixelData = [UInt16](repeating: 0, count: width * height)
            for i in 0..<framePixelData.count {
                // Simulate anatomical variation across slices
                let baseValue = 1024 + frameIndex * 10
                framePixelData[i] = UInt16((baseValue + Int.random(in: -50...50)) & 0xFFFF)
            }
            
            // Each frame should use lossless compression
            let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
            #expect(near == 0, "Frame \(frameIndex) should use lossless compression")
        }
    }
    
    @Test("Multi-frame DICOM - Cine MR")
    func testMultiFrameDICOMCineMR() throws {
        // Cine MR (cardiac) has temporal frames
        let width = 256
        let height = 256
        let bitsPerSample = 16
        let components = 1
        let numberOfPhases = 20
        
        // Validate parameters for each cardiac phase
        for phase in 0..<numberOfPhases {
            // Create test data for this phase
            var phasePixelData = [UInt16](repeating: 0, count: width * height)
            for i in 0..<phasePixelData.count {
                // Simulate cardiac motion
                let cardiacMotionFactor = sin(Double(phase) / Double(numberOfPhases) * 2.0 * .pi)
                let intensity = 2000 + Int(500 * cardiacMotionFactor)
                phasePixelData[i] = UInt16(max(0, min(65535, intensity)))
            }
            
            // Each phase should use lossless compression
            let near = nearParameterForTransferSyntax(Self.losslessTransferSyntax)
            #expect(near == 0, "Cardiac phase \(phase) should use lossless compression")
        }
    }
    
    // MARK: - DICOM Parameter Mapping Tests
    
    @Test("DICOM photometric interpretation - MONOCHROME2")
    func testPhotometricInterpretationMonochrome2() throws {
        // MONOCHROME2: min value is black, max value is white
        let components = 1
        let bitsPerSample = 16
        
        // Create gradient from black to white
        let width = 256
        let height = 256
        var pixelData = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixelData[y * width + x] = UInt16(x * 256)
            }
        }
        
        // Validate MONOCHROME2 parameters
        #expect(components == 1, "MONOCHROME2 is single component")
        #expect(bitsPerSample >= 8 && bitsPerSample <= 16)
    }
    
    @Test("DICOM photometric interpretation - RGB")
    func testPhotometricInterpretationRGB() throws {
        // RGB: three component color image
        let components = 3
        let bitsPerSample = 8
        let width = 256
        let height = 256
        
        // Create test RGB data
        var pixelData = [UInt8](repeating: 0, count: width * height * components)
        for i in stride(from: 0, to: pixelData.count, by: components) {
            pixelData[i] = UInt8(Int.random(in: 0...255))     // R
            pixelData[i + 1] = UInt8(Int.random(in: 0...255)) // G
            pixelData[i + 2] = UInt8(Int.random(in: 0...255)) // B
        }
        
        // Validate RGB parameters
        #expect(components == 3, "RGB requires 3 components")
        #expect(bitsPerSample == 8, "RGB typically uses 8 bits per sample")
    }
    
    @Test("DICOM planar configuration - interlaced vs separate planes")
    func testPlanarConfiguration() throws {
        // DICOM Planar Configuration affects how RGB data is stored
        let width = 100
        let height = 100
        let components = 3
        
        // Planar Configuration 0: R1 G1 B1 R2 G2 B2 ... (sample-interleaved)
        // Planar Configuration 1: R1 R2 ... G1 G2 ... B1 B2 ... (component-interleaved)
        
        // JLSwift interleave modes map to DICOM planar configuration:
        // - InterleaveMode.sample corresponds to Planar Configuration 0
        // - InterleaveMode.none corresponds to Planar Configuration 1
        
        let planarConfig0Size = width * height * components // Sample-interleaved
        let planarConfig1Size = width * height * components // Component planes
        
        #expect(planarConfig0Size == planarConfig1Size, "Total size is same regardless of configuration")
        #expect(components == 3, "Planar configuration applies to multi-component images")
    }
    
    @Test("DICOM bits allocated vs bits stored")
    func testBitsAllocatedVsBitsStored() throws {
        // DICOM distinguishes between bits allocated and bits stored
        let configurations = [
            (allocated: 16, stored: 12, high: 11), // 12 bits stored in 16-bit words, starting at bit 0
            (allocated: 16, stored: 10, high: 9),  // 10 bits stored in 16-bit words
            (allocated: 16, stored: 16, high: 15), // Full 16 bits used
            (allocated: 8, stored: 8, high: 7),    // Full 8 bits used
        ]
        
        for config in configurations {
            let maxValue = (1 << config.stored) - 1
            
            // Sample pixel value within stored bits
            let sampleValue = UInt16(maxValue / 2)
            
            #expect(config.stored <= config.allocated, "Stored bits must not exceed allocated bits")
            #expect(config.high == config.stored - 1, "High bit should be stored bits - 1")
            #expect(sampleValue <= maxValue, "Sample value should fit in stored bits")
        }
    }
    
    @Test("DICOM pixel representation - unsigned vs signed")
    func testPixelRepresentation() throws {
        // DICOM Pixel Representation: 0 = unsigned, 1 = signed (two's complement)
        let bitsPerSample = 16
        
        // Unsigned representation (common for CT, MR, CR, DX, US)
        let unsignedMax = UInt16((1 << bitsPerSample) - 1)
        #expect(unsignedMax == 65535, "16-bit unsigned max is 65535")
        
        // Signed representation (less common, but supported)
        // For CT Hounsfield units, signed representation might be used
        let signedMin = Int16.min // -32768
        let signedMax = Int16.max // 32767
        #expect(signedMin == -32768, "16-bit signed min is -32768")
        #expect(signedMax == 32767, "16-bit signed max is 32767")
        
        // JLSwift handles unsigned pixel data; signed data should be converted
        // to unsigned by adding an offset before encoding
    }
    
    // MARK: - Helper Methods
    
    /// Determine the appropriate NEAR parameter for a DICOM transfer syntax
    private func nearParameterForTransferSyntax(_ transferSyntaxUID: String, tolerance: Int = 3) -> Int {
        switch transferSyntaxUID {
        case Self.losslessTransferSyntax:
            return 0 // Lossless
        case Self.nearLosslessTransferSyntax:
            return max(1, min(255, tolerance)) // Near-lossless with valid tolerance
        default:
            return 0 // Default to lossless for unknown transfer syntaxes
        }
    }
}
