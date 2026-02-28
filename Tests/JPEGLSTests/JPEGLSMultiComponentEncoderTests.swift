/// Tests for JPEG-LS multi-component encoder with interleaving support

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Multi-Component Encoder Tests")
struct JPEGLSMultiComponentEncoderTests {
    
    // MARK: - Initialization Tests
    
    @Test("Initialize encoder with grayscale")
    func initializeWithGrayscale() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )
        
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader
        )
        
        // Should initialise without errors
        #expect(encoder != nil)
    }
    
    @Test("Initialize encoder with RGB")
    func initializeWithRGB() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )
        
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader
        )
        
        // Should initialise without errors
        #expect(encoder != nil)
    }
    
    @Test("Validate scan header against frame header")
    func validateScanHeaderMismatch() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )
        
        // Try to create RGB scan for grayscale frame
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        
        #expect(throws: JPEGLSError.self) {
            try JPEGLSMultiComponentEncoder(
                frameHeader: frameHeader,
                scanHeader: scanHeader
            )
        }
    }
    
    // MARK: - None Interleaved Tests
    
    @Test("Encode grayscale with none interleaving")
    func encodeGrayscaleNoneInterleaved() throws {
        let pixels = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.componentCount == 1)
        #expect(statistics.pixelsEncoded == 16)  // 4×4 image
        #expect(statistics.interleaveMode == .none)
    }
    
    @Test("Reject none interleaving with multiple components")
    func rejectNoneInterleavingMultipleComponents() throws {
        let red = [[255, 200], [150, 100]]
        let green = [[100, 150], [200, 255]]
        let blue = [[50, 75], [100, 125]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Create scan with all 3 components but none interleaving
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3)
            ],
            near: 0,
            interleaveMode: .none
        )
        
        // Should fail validation
        #expect(throws: JPEGLSError.self) {
            let _ = try scanHeader.validate(against: imageData.frameHeader)
        }
    }
    
    // MARK: - Line Interleaved Tests
    
    @Test("Encode RGB with line interleaving")
    func encodeRGBLineInterleaved() throws {
        let red = [
            [255, 200, 150],
            [100, 50, 0]
        ]
        let green = [
            [100, 150, 200],
            [255, 210, 180]
        ]
        let blue = [
            [50, 75, 100],
            [125, 150, 175]
        ]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Create line-interleaved scan
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3)
            ],
            near: 0,
            interleaveMode: .line
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsEncoded == 18)  // 2×3 pixels × 3 components
        #expect(statistics.interleaveMode == .line)
    }
    
    @Test("Reject line interleaving with single component")
    func rejectLineInterleavingSingleComponent() throws {
        let pixels = [[10, 20], [30, 40]]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Try line interleaving with single component - should fail at scan header creation
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
                near: 0,
                interleaveMode: .line
            )
        }
    }
    
    // MARK: - Sample Interleaved Tests
    
    @Test("Encode RGB with sample interleaving")
    func encodeRGBSampleInterleaved() throws {
        let red = [
            [255, 200],
            [150, 100]
        ]
        let green = [
            [100, 150],
            [200, 255]
        ]
        let blue = [
            [50, 75],
            [100, 125]
        ]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsEncoded == 12)  // 2×2 pixels × 3 components
        #expect(statistics.interleaveMode == .sample)
    }
    
    @Test("Reject sample interleaving with single component")
    func rejectSampleInterleavingSingleComponent() throws {
        let pixels = [[10, 20], [30, 40]]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Try sample interleaving with single component - should fail at scan header creation
        #expect(throws: JPEGLSError.self) {
            try JPEGLSScanHeader(
                componentCount: 1,
                components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
                near: 0,
                interleaveMode: .sample
            )
        }
    }
    
    // MARK: - Near-Lossless Tests
    
    @Test("Encode grayscale with near-lossless")
    func encodeGrayscaleNearLossless() throws {
        let pixels = [
            [10, 20, 30],
            [40, 50, 60],
            [70, 80, 90]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Create near-lossless scan with NEAR=2
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: 2,
            interleaveMode: .none
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.componentCount == 1)
        #expect(statistics.pixelsEncoded == 9)  // 3×3 image
        #expect(statistics.interleaveMode == .none)
    }
    
    @Test("Encode RGB with near-lossless and sample interleaving")
    func encodeRGBNearLosslessSampleInterleaved() throws {
        let red = [[255, 200], [150, 100]]
        let green = [[100, 150], [200, 255]]
        let blue = [[50, 75], [100, 125]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Create near-lossless RGB scan with NEAR=3
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3)
            ],
            near: 3,
            interleaveMode: .sample
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsEncoded == 12)  // 2×2 pixels × 3 components
        #expect(statistics.interleaveMode == .sample)
    }
    
    // MARK: - Pixel Ordering Tests
    
    @Test("Verify none interleaving pixel order")
    func verifyNoneInterleavingPixelOrder() throws {
        // For none interleaving, pixels should be encoded in raster order:
        // (0,0), (0,1), (0,2), (1,0), (1,1), (1,2), etc.
        let pixels = [
            [1, 2, 3],
            [4, 5, 6]
        ]
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.pixelsEncoded == 6)
    }
    
    @Test("Verify line interleaving pixel order")
    func verifyLineInterleavingPixelOrder() throws {
        // For line interleaving with RGB, order should be:
        // R(0,0), R(0,1), G(0,0), G(0,1), B(0,0), B(0,1),
        // R(1,0), R(1,1), G(1,0), G(1,1), B(1,0), B(1,1)
        let red = [[1, 2], [3, 4]]
        let green = [[5, 6], [7, 8]]
        let blue = [[9, 10], [11, 12]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3)
            ],
            near: 0,
            interleaveMode: .line
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.pixelsEncoded == 12)  // 2×2 × 3 components
    }
    
    @Test("Verify sample interleaving pixel order")
    func verifySampleInterleavingPixelOrder() throws {
        // For sample interleaving with RGB, order should be:
        // R(0,0), G(0,0), B(0,0), R(0,1), G(0,1), B(0,1),
        // R(1,0), G(1,0), B(1,0), R(1,1), G(1,1), B(1,1)
        let red = [[1, 2], [3, 4]]
        let green = [[5, 6], [7, 8]]
        let blue = [[9, 10], [11, 12]]
        
        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        #expect(statistics.pixelsEncoded == 12)  // 2×2 × 3 components
    }
}
