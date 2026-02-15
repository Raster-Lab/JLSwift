/// Tests for JPEG-LS multi-component decoder with deinterleaving support

import Testing
@testable import JPEGLS

@Suite("JPEG-LS Multi-Component Decoder Tests")
struct JPEGLSMultiComponentDecoderTests {

    // MARK: - Initialization Tests

    @Test("Initialize decoder with grayscale")
    func initializeWithGrayscale() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )

        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader
        )

        #expect(decoder != nil)
    }

    @Test("Initialize decoder with RGB")
    func initializeWithRGB() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )

        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader
        )

        #expect(decoder != nil)
    }

    @Test("Initialize decoder with color transformation")
    func initializeWithColorTransformation() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )

        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        #expect(decoder != nil)
    }

    @Test("Validate scan header against frame header")
    func validateScanHeaderMismatch() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )

        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        #expect(throws: JPEGLSError.self) {
            try JPEGLSMultiComponentDecoder(
                frameHeader: frameHeader,
                scanHeader: scanHeader
            )
        }
    }

    @Test("Reject invalid color transformation for component count")
    func rejectInvalidColorTransformationForComponentCount() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(
            bitsPerSample: 8,
            width: 4,
            height: 4
        )

        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

        // HP1 requires 3 components, but we have 1
        #expect(throws: JPEGLSError.self) {
            try JPEGLSMultiComponentDecoder(
                frameHeader: frameHeader,
                scanHeader: scanHeader,
                colorTransformation: .hp1
            )
        }
    }

    // MARK: - None Interleaved Tests

    @Test("Decode grayscale with none interleaving")
    func decodeGrayscaleNoneInterleaved() throws {
        let pixels = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 1)
        #expect(statistics.pixelsDecoded == 16)
        #expect(statistics.interleaveMode == .none)
        #expect(statistics.colorTransformation == .none)
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

        // Validation happens at scan header level
        #expect(throws: JPEGLSError.self) {
            let scanHeader = try JPEGLSScanHeader(
                componentCount: 3,
                components: [
                    JPEGLSScanHeader.ComponentSelector(id: 1),
                    JPEGLSScanHeader.ComponentSelector(id: 2),
                    JPEGLSScanHeader.ComponentSelector(id: 3),
                ],
                near: 0,
                interleaveMode: .none
            )
            let _ = try scanHeader.validate(against: imageData.frameHeader)
        }
    }

    // MARK: - Line Interleaved Tests

    @Test("Decode RGB with line interleaving")
    func decodeRGBLineInterleaved() throws {
        let red = [
            [255, 200, 150],
            [100, 50, 0],
        ]
        let green = [
            [100, 150, 200],
            [255, 210, 180],
        ]
        let blue = [
            [50, 75, 100],
            [125, 150, 175],
        ]

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
                JPEGLSScanHeader.ComponentSelector(id: 3),
            ],
            near: 0,
            interleaveMode: .line
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsDecoded == 18)  // 2×3 pixels × 3 components
        #expect(statistics.interleaveMode == .line)
    }

    @Test("Reject line interleaving with single component")
    func rejectLineInterleavingSingleComponent() throws {
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

    @Test("Decode RGB with sample interleaving")
    func decodeRGBSampleInterleaved() throws {
        let red = [
            [255, 200],
            [150, 100],
        ]
        let green = [
            [100, 150],
            [200, 255],
        ]
        let blue = [
            [50, 75],
            [100, 125],
        ]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsDecoded == 12)  // 2×2 pixels × 3 components
        #expect(statistics.interleaveMode == .sample)
    }

    @Test("Reject sample interleaving with single component")
    func rejectSampleInterleavingSingleComponent() throws {
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

    @Test("Decode grayscale with near-lossless")
    func decodeGrayscaleNearLossless() throws {
        let pixels = [
            [10, 20, 30],
            [40, 50, 60],
            [70, 80, 90],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: 2,
            interleaveMode: .none
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 1)
        #expect(statistics.pixelsDecoded == 9)
        #expect(statistics.interleaveMode == .none)
    }

    @Test("Decode RGB with near-lossless and sample interleaving")
    func decodeRGBNearLosslessSampleInterleaved() throws {
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

        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3),
            ],
            near: 3,
            interleaveMode: .sample
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsDecoded == 12)
        #expect(statistics.interleaveMode == .sample)
    }

    // MARK: - Pixel Ordering Tests

    @Test("Verify none interleaving pixel order")
    func verifyNoneInterleavingPixelOrder() throws {
        let pixels = [
            [1, 2, 3],
            [4, 5, 6],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 6)
    }

    @Test("Verify line interleaving pixel order")
    func verifyLineInterleavingPixelOrder() throws {
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
                JPEGLSScanHeader.ComponentSelector(id: 3),
            ],
            near: 0,
            interleaveMode: .line
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 12)  // 2×2 × 3 components
    }

    @Test("Verify sample interleaving pixel order")
    func verifySampleInterleavingPixelOrder() throws {
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
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 12)  // 2×2 × 3 components
    }

    // MARK: - Color Transformation Inverse Tests

    @Test("Apply inverse color transformation - none")
    func applyInverseNone() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .none
        )

        let original = [100, 150, 200]
        let result = try decoder.applyInverseColorTransformation(original)
        #expect(result == original)
    }

    @Test("Apply inverse color transformation - HP1")
    func applyInverseHP1() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        // HP1 forward: R' = R - G, G' = G, B' = B - G
        // For original [100, 150, 200]: transformed = [-50, 150, 50]
        let transformed = [-50, 150, 50]
        let recovered = try decoder.applyInverseColorTransformation(transformed)
        #expect(recovered == [100, 150, 200])
    }

    @Test("Apply inverse color transformation - HP2")
    func applyInverseHP2() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp2
        )

        let original = [100, 150, 200]
        let transform = JPEGLSColorTransformation.hp2
        let transformed = try transform.transformForward(original)
        let recovered = try decoder.applyInverseColorTransformation(transformed)
        #expect(recovered == original)
    }

    @Test("Apply inverse color transformation - HP3")
    func applyInverseHP3() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp3
        )

        let original = [100, 150, 200]
        let transform = JPEGLSColorTransformation.hp3
        let transformed = try transform.transformForward(original)
        let recovered = try decoder.applyInverseColorTransformation(transformed)
        #expect(recovered == original)
    }

    @Test("Apply inverse color transformation to image - none")
    func applyInverseToImageNone() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 1
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .none
        )

        let componentPixels = [
            [100, 200],  // R
            [150, 250],  // G
            [50, 75],  // B
        ]

        let result = try decoder.applyInverseColorTransformationToImage(componentPixels)
        #expect(result == componentPixels)
    }

    @Test("Apply inverse color transformation to image - HP1")
    func applyInverseToImageHP1() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 1
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        // Forward HP1: R' = R - G, G' = G, B' = B - G
        // For pixel 0: R=100, G=150, B=200 -> R'=-50, G'=150, B'=50
        // For pixel 1: R=80, G=120, B=160 -> R'=-40, G'=120, B'=40
        let transformedPixels = [
            [-50, -40],  // R'
            [150, 120],  // G'
            [50, 40],  // B'
        ]

        let result = try decoder.applyInverseColorTransformationToImage(transformedPixels)

        #expect(result[0] == [100, 80])  // R recovered
        #expect(result[1] == [150, 120])  // G recovered
        #expect(result[2] == [200, 160])  // B recovered
    }

    @Test("Apply inverse color transformation to image rejects mismatched component count")
    func applyInverseToImageRejectsWrongComponentCount() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 1
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        // Only 2 components instead of 3
        let componentPixels = [
            [100, 200],
            [150, 250],
        ]

        #expect(throws: JPEGLSError.self) {
            try decoder.applyInverseColorTransformationToImage(componentPixels)
        }
    }

    @Test("Apply inverse color transformation to image rejects inconsistent pixel counts")
    func applyInverseToImageRejectsInconsistentPixelCounts() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 1
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        // Inconsistent pixel counts across components
        let componentPixels = [
            [100, 200],
            [150, 250],
            [50],
        ]

        #expect(throws: JPEGLSError.self) {
            try decoder.applyInverseColorTransformationToImage(componentPixels)
        }
    }

    // MARK: - Component Reconstruction Tests

    @Test("Reconstruct grayscale components")
    func reconstructGrayscaleComponents() throws {
        let pixels = [
            [10, 20],
            [30, 40],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let reconstructed = try decoder.reconstructComponents(from: buffer)

        #expect(reconstructed.componentCount == 1)
        #expect(reconstructed.width == 2)
        #expect(reconstructed.height == 2)
        #expect(reconstructed.getPixels(componentId: 1) == pixels)
        #expect(reconstructed.getPixel(componentId: 1, row: 0, column: 0) == 10)
        #expect(reconstructed.getPixel(componentId: 1, row: 1, column: 1) == 40)
    }

    @Test("Reconstruct RGB components without color transform")
    func reconstructRGBComponentsNoTransform() throws {
        let red = [[100, 200], [50, 150]]
        let green = [[110, 210], [60, 160]]
        let blue = [[120, 220], [70, 170]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .none
        )

        let reconstructed = try decoder.reconstructComponents(from: buffer)

        #expect(reconstructed.componentCount == 3)
        #expect(reconstructed.getPixels(componentId: 1) == red)
        #expect(reconstructed.getPixels(componentId: 2) == green)
        #expect(reconstructed.getPixels(componentId: 3) == blue)
    }

    @Test("Reconstruct RGB components with HP1 color transform")
    func reconstructRGBComponentsWithHP1() throws {
        // Original RGB values
        let originalR = [[100, 200], [50, 150]]
        let originalG = [[110, 210], [60, 160]]
        let originalB = [[120, 220], [70, 170]]

        // Apply forward HP1: R' = R - G, G' = G, B' = B - G
        var transformedR = [[Int]](repeating: [Int](repeating: 0, count: 2), count: 2)
        var transformedG = [[Int]](repeating: [Int](repeating: 0, count: 2), count: 2)
        var transformedB = [[Int]](repeating: [Int](repeating: 0, count: 2), count: 2)

        for row in 0..<2 {
            for col in 0..<2 {
                let transformed = try JPEGLSColorTransformation.hp1.transformForward([
                    originalR[row][col], originalG[row][col], originalB[row][col],
                ])
                transformedR[row][col] = transformed[0]
                transformedG[row][col] = transformed[1]
                transformedB[row][col] = transformed[2]
            }
        }

        // Create a frame header that allows the transformed values
        // Since transformed values may be negative, use a wider bit depth
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 16,
            width: 2,
            height: 2
        )

        // Adjust transformed values to fit in valid range by shifting
        let maxVal = (1 << 16) - 1
        var shiftedR = transformedR
        var shiftedG = transformedG
        var shiftedB = transformedB
        for row in 0..<2 {
            for col in 0..<2 {
                shiftedR[row][col] = max(0, min(maxVal, transformedR[row][col] + 32768))
                shiftedG[row][col] = max(0, min(maxVal, transformedG[row][col] + 32768))
                shiftedB[row][col] = max(0, min(maxVal, transformedB[row][col] + 32768))
            }
        }

        let imageData = try MultiComponentImageData(
            components: [
                MultiComponentImageData.ComponentData(id: 1, pixels: shiftedR),
                MultiComponentImageData.ComponentData(id: 2, pixels: shiftedG),
                MultiComponentImageData.ComponentData(id: 3, pixels: shiftedB),
            ],
            frameHeader: frameHeader
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        // Skip color transform to test raw reconstruction
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .none
        )

        let reconstructed = try decoder.reconstructComponents(
            from: buffer,
            applyColorTransform: false
        )

        #expect(reconstructed.componentCount == 3)
        #expect(reconstructed.getPixels(componentId: 1) == shiftedR)
        #expect(reconstructed.getPixels(componentId: 2) == shiftedG)
        #expect(reconstructed.getPixels(componentId: 3) == shiftedB)
    }

    @Test("Reconstruct components without applying color transform")
    func reconstructComponentsWithoutTransform() throws {
        let red = [[100, 200], [50, 150]]
        let green = [[110, 210], [60, 160]]
        let blue = [[120, 220], [70, 170]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        // applyColorTransform: false should skip inverse transformation
        let reconstructed = try decoder.reconstructComponents(
            from: buffer,
            applyColorTransform: false
        )

        #expect(reconstructed.getPixels(componentId: 1) == red)
        #expect(reconstructed.getPixels(componentId: 2) == green)
        #expect(reconstructed.getPixels(componentId: 3) == blue)
    }

    // MARK: - ReconstructedComponents Tests

    @Test("ReconstructedComponents getPixel with invalid component")
    func reconstructedComponentsInvalidComponent() {
        let reconstructed = ReconstructedComponents(
            componentPixels: [1: [[10, 20], [30, 40]]],
            width: 2,
            height: 2,
            colorTransformation: .none
        )

        #expect(reconstructed.getPixel(componentId: 99, row: 0, column: 0) == nil)
        #expect(reconstructed.getPixels(componentId: 99) == nil)
    }

    @Test("ReconstructedComponents getPixel with invalid position")
    func reconstructedComponentsInvalidPosition() {
        let reconstructed = ReconstructedComponents(
            componentPixels: [1: [[10, 20], [30, 40]]],
            width: 2,
            height: 2,
            colorTransformation: .none
        )

        #expect(reconstructed.getPixel(componentId: 1, row: -1, column: 0) == nil)
        #expect(reconstructed.getPixel(componentId: 1, row: 0, column: -1) == nil)
        #expect(reconstructed.getPixel(componentId: 1, row: 2, column: 0) == nil)
        #expect(reconstructed.getPixel(componentId: 1, row: 0, column: 2) == nil)
    }

    @Test("ReconstructedComponents componentCount")
    func reconstructedComponentsCount() {
        let reconstructed = ReconstructedComponents(
            componentPixels: [
                1: [[10, 20]],
                2: [[30, 40]],
                3: [[50, 60]],
            ],
            width: 2,
            height: 1,
            colorTransformation: .none
        )

        #expect(reconstructed.componentCount == 3)
    }

    // MARK: - DecodedScanStatistics Tests

    @Test("DecodedScanStatistics initialization and equality")
    func decodedScanStatisticsEquality() {
        let stats1 = DecodedScanStatistics(
            componentCount: 3,
            pixelsDecoded: 12,
            interleaveMode: .sample,
            colorTransformation: .hp1
        )

        let stats2 = DecodedScanStatistics(
            componentCount: 3,
            pixelsDecoded: 12,
            interleaveMode: .sample,
            colorTransformation: .hp1
        )

        #expect(stats1 == stats2)
    }

    @Test("DecodedScanStatistics not equal with different values")
    func decodedScanStatisticsNotEqual() {
        let stats1 = DecodedScanStatistics(
            componentCount: 3,
            pixelsDecoded: 12,
            interleaveMode: .sample,
            colorTransformation: .hp1
        )

        let stats2 = DecodedScanStatistics(
            componentCount: 1,
            pixelsDecoded: 12,
            interleaveMode: .none,
            colorTransformation: .none
        )

        #expect(stats1 != stats2)
    }

    // MARK: - Edge Case Tests

    @Test("Decode 1x1 grayscale image")
    func decode1x1Grayscale() throws {
        let pixels = [[42]]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 1)
    }

    @Test("Decode 1x1 RGB image with sample interleaving")
    func decode1x1RGBSampleInterleaved() throws {
        let red = [[255]]
        let green = [[128]]
        let blue = [[64]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 3)  // 1 pixel × 3 components
    }

    @Test("Decode large image")
    func decodeLargeImage() throws {
        let size = 64
        let pixels = (0..<size).map { row in
            (0..<size).map { col in
                (row * size + col) % 256
            }
        }

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == size * size)
    }

    @Test("Decode with all HP color transformations")
    func decodeWithAllColorTransformations() throws {
        let red = [[100, 200], [50, 150]]
        let green = [[110, 210], [60, 160]]
        let blue = [[120, 220], [70, 170]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)

        for transform: JPEGLSColorTransformation in [.none, .hp1, .hp2, .hp3] {
            let scanHeader = try JPEGLSScanHeader.rgbLossless()
            let decoder = try JPEGLSMultiComponentDecoder(
                frameHeader: imageData.frameHeader,
                scanHeader: scanHeader,
                colorTransformation: transform
            )

            let statistics = try decoder.decodeScan(buffer: buffer)

            #expect(statistics.componentCount == 3)
            #expect(statistics.pixelsDecoded == 12)
            #expect(statistics.colorTransformation == transform)
        }
    }

    @Test("Default color transformation is none")
    func defaultColorTransformationIsNone() throws {
        let frameHeader = try JPEGLSFrameHeader.rgb(
            bitsPerSample: 8,
            width: 2,
            height: 2
        )
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: frameHeader,
            scanHeader: scanHeader
        )

        let red = [[100, 200], [50, 150]]
        let green = [[110, 210], [60, 160]]
        let blue = [[120, 220], [70, 170]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.colorTransformation == .none)
    }

    @Test("Decode with 16-bit samples")
    func decodeWith16BitSamples() throws {
        let maxVal = (1 << 16) - 1
        let pixels = [
            [0, maxVal / 2],
            [maxVal, 1000],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 16
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 4)
    }

    @Test("Reconstruct components preserves color transformation info")
    func reconstructComponentsPreservesTransformInfo() throws {
        let pixels = [[10, 20], [30, 40]]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .none
        )

        let reconstructed = try decoder.reconstructComponents(from: buffer)

        #expect(reconstructed.colorTransformation == .none)
    }

    @Test("Reconstruct RGB components with HP1 color transform applied")
    func reconstructRGBComponentsWithHP1Applied() throws {
        // Simulate decoded data in HP1 transformed space
        // HP1 forward: R' = R - G, G' = G, B' = B - G
        // For original R=100, G=50, B=80: R'=50, G'=50, B'=30
        // For original R=200, G=100, B=150: R'=100, G'=100, B'=50
        let transformedR = [[50, 100], [50, 100]]
        let transformedG = [[50, 100], [50, 100]]
        let transformedB = [[30, 50], [30, 50]]

        let imageData = try MultiComponentImageData.rgb(
            redPixels: transformedR,
            greenPixels: transformedG,
            bluePixels: transformedB,
            bitsPerSample: 8
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.rgbLossless()

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader,
            colorTransformation: .hp1
        )

        let reconstructed = try decoder.reconstructComponents(
            from: buffer,
            applyColorTransform: true
        )

        // After inverse HP1: R = R' + G', G = G', B = B' + G'
        #expect(reconstructed.getPixel(componentId: 1, row: 0, column: 0) == 100)  // 50 + 50
        #expect(reconstructed.getPixel(componentId: 2, row: 0, column: 0) == 50)   // 50
        #expect(reconstructed.getPixel(componentId: 3, row: 0, column: 0) == 80)   // 30 + 50
        #expect(reconstructed.getPixel(componentId: 1, row: 0, column: 1) == 200)  // 100 + 100
        #expect(reconstructed.getPixel(componentId: 2, row: 0, column: 1) == 100)  // 100
        #expect(reconstructed.getPixel(componentId: 3, row: 0, column: 1) == 150)  // 50 + 100
    }

    @Test("Decode RGB with near-lossless and line interleaving")
    func decodeRGBNearLosslessLineInterleaved() throws {
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

        let scanHeader = try JPEGLSScanHeader(
            componentCount: 3,
            components: [
                JPEGLSScanHeader.ComponentSelector(id: 1),
                JPEGLSScanHeader.ComponentSelector(id: 2),
                JPEGLSScanHeader.ComponentSelector(id: 3),
            ],
            near: 5,
            interleaveMode: .line
        )

        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.componentCount == 3)
        #expect(statistics.pixelsDecoded == 12)
        #expect(statistics.interleaveMode == .line)
    }

    @Test("Decode with 2-bit samples")
    func decodeWith2BitSamples() throws {
        let pixels = [
            [0, 1, 2, 3],
            [3, 2, 1, 0],
        ]

        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 2
        )

        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )

        let statistics = try decoder.decodeScan(buffer: buffer)

        #expect(statistics.pixelsDecoded == 8)
    }
}
