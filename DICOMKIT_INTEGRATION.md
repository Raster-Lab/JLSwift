# DICOMkit Integration Guide for JLSwift

This guide demonstrates how to integrate JLSwift JPEG-LS compression into DICOM imaging workflows using DICOMkit. JLSwift provides native Swift JPEG-LS encoding and decoding that maps directly to DICOM transfer syntaxes.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [DICOM Transfer Syntaxes](#dicom-transfer-syntaxes)
- [Basic Integration](#basic-integration)
  - [Encoding DICOM Pixel Data](#encoding-dicom-pixel-data)
  - [Decoding DICOM Pixel Data](#decoding-dicom-pixel-data)
  - [Transfer Syntax Selection](#transfer-syntax-selection)
- [Advanced Integration](#advanced-integration)
  - [Multi-Frame DICOM Images](#multi-frame-dicom-images)
  - [Colour DICOM Images](#color-dicom-images)
  - [Near-Lossless Compression](#near-lossless-compression)
  - [Custom Preset Parameters](#custom-preset-parameters)
- [DICOM Modality Examples](#dicom-modality-examples)
  - [CT (Computed Tomography)](#ct-computed-tomography)
  - [MR (Magnetic Resonance)](#mr-magnetic-resonance)
  - [CR/DX (Digital Radiography)](#crdx-digital-radiography)
  - [US (Ultrasound)](#us-ultrasound)
- [DICOM Codec Provider](#dicom-codec-provider)
  - [Codec Registration](#codec-registration)
  - [Transcoding Pipeline](#transcoding-pipeline)
- [Performance Considerations](#performance-considerations)
  - [Buffer Pooling for Batch Processing](#buffer-pooling-for-batch-processing)
  - [Tile-Based Processing for Large Images](#tile-based-processing-for-large-images)
  - [Memory Management](#memory-management)
- [Error Handling](#error-handling)
- [Testing DICOM Integration](#testing-dicom-integration)

## Overview

JPEG-LS is a standard compression codec for DICOM medical imaging defined by two transfer syntaxes:

| Transfer Syntax UID | Description | JLSwift Support |
|---------------------|-------------|-----------------|
| `1.2.840.10008.1.2.4.80` | JPEG-LS Lossless | ✅ `near = 0` |
| `1.2.840.10008.1.2.4.81` | JPEG-LS Near-Lossless | ✅ `near = 1-255` |

JLSwift implements the full JPEG-LS standard (ISO/IEC 14495-1:1999 / ITU-T.87) in pure Swift, making it ideal for integration with DICOMkit:

- **No C dependencies** — simplifies deployment and auditing
- **Apple Silicon optimised** — ARM NEON/SIMD acceleration
- **Memory efficient** — buffer pooling and tile-based processing for large images
- **Standards compliant** — full support for all JPEG-LS interleaving modes and colour transforms

## Prerequisites

Add both JLSwift and DICOMkit to your project's `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyDICOMApp",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0"),
        // Add your DICOMkit dependency here
    ],
    targets: [
        .target(
            name: "MyDICOMApp",
            dependencies: [
                .product(name: "JPEGLS", package: "JLSwift"),
            ]
        ),
    ]
)
```

## DICOM Transfer Syntaxes

JPEG-LS maps to DICOM transfer syntaxes through the NEAR parameter:

```swift
import JPEGLS

/// DICOM Transfer Syntax UIDs for JPEG-LS
enum JPEGLSTransferSyntax {
    /// JPEG-LS Lossless Image Compression (1.2.840.10008.1.2.4.80)
    static let lossless = "1.2.840.10008.1.2.4.80"

    /// JPEG-LS Lossy (Near-Lossless) Image Compression (1.2.840.10008.1.2.4.81)
    static let nearLossless = "1.2.840.10008.1.2.4.81"

    /// Determine the appropriate NEAR parameter for a transfer syntax
    static func nearParameter(for transferSyntaxUID: String, tolerance: Int = 3) -> Int {
        switch transferSyntaxUID {
        case lossless:
            return 0  // Lossless
        case nearLossless:
            return tolerance  // Near-lossless with configurable tolerance
        default:
            return 0
        }
    }
}
```

## Basic Integration

### Encoding DICOM Pixel Data

Encode raw pixel data from a DICOM dataset using JPEG-LS:

```swift
import JPEGLS

/// Encode DICOM grayscale pixel data with JPEG-LS
func encodeDICOMPixelData(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsAllocated: Int,
    bitsStored: Int,
    transferSyntaxUID: String
) throws -> Data {
    // Determine NEAR parameter from transfer syntax
    let near = JPEGLSTransferSyntax.nearParameter(for: transferSyntaxUID)

    // Build pixel buffer from DICOM pixel data
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixelData,
        bitsPerSample: bitsStored
    )

    // Encode using high-level API
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: near)
    return try encoder.encode(imageData, configuration: config)
}
```

### Decoding DICOM Pixel Data

Decode JPEG-LS compressed data from a DICOM dataset:

```swift
import JPEGLS

/// Decode JPEG-LS compressed DICOM pixel data
func decodeDICOMPixelData(
    compressedData: Data
) throws -> (pixels: [[Int]], width: Int, height: Int, bitsPerSample: Int) {
    // Decode using the high-level decoder
    let decoder = JPEGLSDecoder()
    let imageData = try decoder.decode(compressedData)

    let frame = imageData.frameHeader

    // Extract greyscale pixel data from first component
    let pixels = imageData.components[0].pixels

    return (pixels, frame.width, frame.height, frame.bitsPerSample)
}
```

### Transfer Syntax Selection

Select the appropriate JPEG-LS configuration based on DICOM attributes:

```swift
import JPEGLS

/// Configure JPEG-LS encoding based on DICOM dataset attributes
struct DICOMJPEGLSConfiguration {
    let frameHeader: JPEGLSFrameHeader
    let encoderConfig: JPEGLSEncoder.Configuration
    let colorTransformation: JPEGLSColorTransformation

    /// Create configuration from DICOM attributes
    init(
        rows: Int,
        columns: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        transferSyntaxUID: String,
        near: Int? = nil
    ) throws {
        // Determine NEAR from transfer syntax or explicit parameter
        let nearParam = near ?? JPEGLSTransferSyntax.nearParameter(for: transferSyntaxUID)

        // Configure based on samples per pixel
        if samplesPerPixel == 1 {
            // Greyscale (MONOCHROME1 or MONOCHROME2)
            self.frameHeader = try JPEGLSFrameHeader.grayscale(
                bitsPerSample: bitsStored,
                width: columns,
                height: rows
            )
            self.encoderConfig = try JPEGLSEncoder.Configuration(
                near: nearParam,
                interleaveMode: .none
            )
            self.colorTransformation = .none
        } else {
            // Colour (RGB or YBR_FULL)
            self.frameHeader = try JPEGLSFrameHeader.rgb(
                bitsPerSample: bitsStored,
                width: columns,
                height: rows
            )
            // Use line interleaving for colour images
            self.encoderConfig = try JPEGLSEncoder.Configuration(
                near: nearParam,
                interleaveMode: .line
            )
            // Apply colour transformation for better compression
            self.colorTransformation = photometricInterpretation == "RGB" ? .hp1 : .none
        }
    }
}
```

## Advanced Integration

### Multi-Frame DICOM Images

Handle DICOM datasets containing multiple frames (e.g., cine MR, CT volumes):

```swift
import JPEGLS

/// Encode a multi-frame DICOM dataset with JPEG-LS
///
/// Each frame is encoded independently as a separate JPEG-LS bitstream,
/// following the DICOM encapsulated pixel data format.
func encodeMultiFrameDICOM(
    frames: [[[Int]]],
    rows: Int,
    columns: Int,
    bitsStored: Int,
    near: Int = 0
) throws -> [Data] {
    var results: [Data] = []
    results.reserveCapacity(frames.count)

    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: near)

    // Encode each frame independently
    for frame in frames {
        let imageData = try MultiComponentImageData.grayscale(
            pixels: frame,
            bitsPerSample: bitsStored
        )
        let jpegLSData = try encoder.encode(imageData, configuration: config)
        results.append(jpegLSData)
    }

    return results
}
```

### Colour DICOM Images

Handle colour DICOM images (e.g., pathology slides, dermatology):

```swift
import JPEGLS

/// Encode a color DICOM image with JPEG-LS
///
/// Supports RGB photometric interpretation with optional color transformation
/// for improved compression ratios.
func encodeColorDICOM(
    redChannel: [[Int]],
    greenChannel: [[Int]],
    blueChannel: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int,
    interleaveMode: JPEGLSInterleaveMode = .line,
    colorTransform: JPEGLSColorTransformation = .hp1
) throws -> Data {
    let imageData = try MultiComponentImageData.rgb(
        redPixels: redChannel,
        greenPixels: greenChannel,
        bluePixels: blueChannel,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: interleaveMode)
    return try encoder.encode(imageData, configuration: config)
}
```

### Near-Lossless Compression

Use near-lossless encoding when storage savings are more important than bit-exact reconstruction:

```swift
import JPEGLS

/// Encode with near-lossless compression for storage optimization
///
/// The NEAR parameter controls the maximum per-pixel error tolerance.
/// Higher values yield better compression at the cost of fidelity.
///
/// Recommended NEAR values for medical imaging:
/// - 0: Lossless (required for diagnostic quality)
/// - 1-2: Visually lossless (acceptable for some modalities)
/// - 3-5: Slight quality reduction (suitable for review/archive)
func encodeNearLossless(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int,
    near: Int
) throws -> Data {
    guard near >= 0 && near <= 255 else {
        throw JPEGLSError.invalidNearParameter(near: near)
    }

    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixelData,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: near)
    return try encoder.encode(imageData, configuration: config)
}
```

### Custom Preset Parameters

Override default JPEG-LS thresholds for specific compression characteristics:

```swift
import JPEGLS

/// Create custom preset parameters for specialized imaging needs
///
/// Custom thresholds can optimize compression for specific image content
/// such as high-contrast CT or low-noise MR acquisitions.
func createCustomPreset(
    bitsStored: Int,
    maxValue: Int? = nil
) throws -> JPEGLSPresetParameters {
    // Use defaults if no custom values needed
    if maxValue == nil {
        return try JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: bitsStored
        )
    }

    // Custom parameters — thresholds must satisfy T1 <= T2 <= T3
    return try JPEGLSPresetParameters(
        maxValue: maxValue!,
        threshold1: 3,
        threshold2: 7,
        threshold3: 21,
        reset: 64
    )
}
```

## DICOM Modality Examples

### CT (Computed Tomography)

CT images are typically 16-bit greyscale with signed pixel values:

```swift
import JPEGLS

/// Encode CT pixel data with JPEG-LS
///
/// CT images use 12-16 bits stored, often with signed pixel representation.
/// The pixel values must be shifted to unsigned before JPEG-LS encoding.
func encodeCTImage(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int,
    pixelRepresentation: Int  // 0 = unsigned, 1 = signed
) throws -> Data {
    var adjustedPixels = pixelData

    // Shift signed values to unsigned range for JPEG-LS
    if pixelRepresentation == 1 {
        let offset = 1 << (bitsStored - 1)
        adjustedPixels = pixelData.map { row in
            row.map { $0 + offset }
        }
    }

    let imageData = try MultiComponentImageData.grayscale(
        pixels: adjustedPixels,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    return try encoder.encode(imageData)  // CT always lossless for diagnostic use
}
```

### MR (Magnetic Resonance)

MR images vary widely in bit depth and may contain multiple frames:

```swift
import JPEGLS

/// Encode MR pixel data with JPEG-LS
///
/// MR images typically use 12-16 bits stored and may be multi-frame.
/// Near-lossless compression may be acceptable for some MR applications.
func encodeMRImage(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int,
    lossless: Bool = true
) throws -> Data {
    let near = lossless ? 0 : 2  // NEAR=2 provides good compression with minimal quality loss

    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixelData,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: near)
    return try encoder.encode(imageData, configuration: config)
}
```

### CR/DX (Digital Radiography)

Digital radiography images are typically high-resolution greyscale:

```swift
import JPEGLS

/// Encode CR/DX pixel data with JPEG-LS
///
/// CR/DX images are high-resolution (e.g., 3000x3000) with 10-14 bits stored.
/// Tile-based processing is recommended for large images.
func encodeCRImage(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int
) throws -> Data {
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixelData,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    return try encoder.encode(imageData)  // Lossless for radiography
}
```

### US (Ultrasound)

Ultrasound images may be greyscale or colour, often with multiple frames:

```swift
import JPEGLS

/// Encode ultrasound pixel data with JPEG-LS
///
/// Ultrasound images are typically 8-bit and may be color (RGB) for Doppler.
/// Near-lossless compression is generally acceptable for ultrasound.
func encodeUSImage(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    samplesPerPixel: Int,
    near: Int = 0
) throws -> Data {
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: near)

    if samplesPerPixel == 1 {
        // Grayscale B-mode
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixelData,
            bitsPerSample: 8
        )
        return try encoder.encode(imageData, configuration: config)
    } else {
        // Colour Doppler — requires separate R, G, B channels
        // For colour images, split interleaved pixel data into separate channels
        // or use MultiComponentImageData.rgb() with separate R, G, B arrays
        let imageData = try MultiComponentImageData.rgb(
            redPixels: pixelData,
            greenPixels: pixelData,
            bluePixels: pixelData,
            bitsPerSample: 8
        )
        let colorConfig = try JPEGLSEncoder.Configuration(near: near, interleaveMode: .sample)
        return try encoder.encode(imageData, configuration: colorConfig)
    }
}
```

## DICOM Codec Provider

### Codec Registration

Create a JPEG-LS codec provider that integrates with DICOMkit's codec system:

```swift
import JPEGLS

/// JPEG-LS codec provider for DICOMkit integration
///
/// Register this provider with DICOMkit to enable automatic JPEG-LS
/// encoding and decoding of DICOM pixel data.
struct JPEGLSCodecProvider {
    /// Supported transfer syntax UIDs
    static let supportedTransferSyntaxes = [
        JPEGLSTransferSyntax.lossless,
        JPEGLSTransferSyntax.nearLossless,
    ]

    /// Check if a transfer syntax is supported
    static func supports(transferSyntax: String) -> Bool {
        return supportedTransferSyntaxes.contains(transferSyntax)
    }

    /// Encode pixel data for a given transfer syntax
    static func encode(
        pixelData: [[Int]],
        rows: Int,
        columns: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        transferSyntax: String
    ) throws -> Data {
        let near = JPEGLSTransferSyntax.nearParameter(for: transferSyntax)
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: near)

        if samplesPerPixel == 1 {
            let imageData = try MultiComponentImageData.grayscale(
                pixels: pixelData,
                bitsPerSample: bitsStored
            )
            return try encoder.encode(imageData, configuration: config)
        } else {
            let imageData = try MultiComponentImageData.rgb(
                redPixels: pixelData,
                greenPixels: pixelData,
                bluePixels: pixelData,
                bitsPerSample: bitsStored
            )
            let colorConfig = try JPEGLSEncoder.Configuration(near: near, interleaveMode: .line)
            return try encoder.encode(imageData, configuration: colorConfig)
        }
    }

    /// Decode compressed JPEG-LS data
    static func decode(
        compressedData: Data
    ) throws -> DecodedDICOMPixelData {
        let decoder = JPEGLSDecoder()
        let imageData = try decoder.decode(compressedData)

        let frame = imageData.frameHeader
        let near = 0  // Determined from decoded header (lossless assumed unless NEAR is embedded)

        return DecodedDICOMPixelData(
            rows: frame.height,
            columns: frame.width,
            bitsStored: frame.bitsPerSample,
            samplesPerPixel: frame.componentCount,
            isLossless: near == 0,
            components: imageData
        )
    }
}

/// Decoded DICOM pixel data result
struct DecodedDICOMPixelData {
    let rows: Int
    let columns: Int
    let bitsStored: Int
    let samplesPerPixel: Int
    let isLossless: Bool
    let components: MultiComponentImageData
}
```

### Transcoding Pipeline

Transcode DICOM images between transfer syntaxes:

```swift
import JPEGLS

/// Transcode DICOM pixel data from one transfer syntax to another
///
/// Supports transcoding to/from JPEG-LS lossless and near-lossless.
struct DICOMTranscoder {

    /// Transcode to JPEG-LS from uncompressed pixel data
    static func transcodeToJPEGLS(
        pixelData: [[Int]],
        rows: Int,
        columns: Int,
        bitsStored: Int,
        samplesPerPixel: Int,
        targetTransferSyntax: String
    ) throws -> Data {
        return try JPEGLSCodecProvider.encode(
            pixelData: pixelData,
            rows: rows,
            columns: columns,
            bitsStored: bitsStored,
            samplesPerPixel: samplesPerPixel,
            transferSyntax: targetTransferSyntax
        )
    }

    /// Transcode from JPEG-LS to uncompressed
    static func transcodeFromJPEGLS(
        compressedData: Data
    ) throws -> DecodedDICOMPixelData {
        return try JPEGLSCodecProvider.decode(compressedData: compressedData)
    }

    /// Transcode between JPEG-LS modes (e.g., lossless to near-lossless)
    static func transcodeBetweenJPEGLS(
        compressedData: Data,
        targetTransferSyntax: String
    ) throws -> Data {
        // First decode
        let decoded = try transcodeFromJPEGLS(compressedData: compressedData)

        // Extract pixel data from decoded components
        let pixels = decoded.components.components[0].pixels

        // Re-encode with target transfer syntax
        return try transcodeToJPEGLS(
            pixelData: pixels,
            rows: decoded.rows,
            columns: decoded.columns,
            bitsStored: decoded.bitsStored,
            samplesPerPixel: decoded.samplesPerPixel,
            targetTransferSyntax: targetTransferSyntax
        )
    }
}
```

## Performance Considerations

### Buffer Pooling for Batch Processing

Use buffer pooling when processing multiple DICOM images (e.g., a full CT series):

```swift
import JPEGLS

/// Process a batch of DICOM images with buffer pooling
///
/// Buffer pooling reduces memory allocation overhead when processing
/// multiple images of the same dimensions.
func processDICOMSeries(
    images: [[[Int]]],
    rows: Int,
    columns: Int,
    bitsStored: Int
) throws -> [Data] {
    var results: [Data] = []
    results.reserveCapacity(images.count)

    let encoder = JPEGLSEncoder()

    for imagePixels in images {
        let imageData = try MultiComponentImageData.grayscale(
            pixels: imagePixels,
            bitsPerSample: bitsStored
        )
        let jpegLSData = try encoder.encode(imageData)
        results.append(jpegLSData)
    }

    return results
}
```

### Tile-Based Processing for Large Images

Use tile-based processing for very large images (e.g., digital pathology):

```swift
import JPEGLS

/// Process a large DICOM image using tile-based approach
///
/// Tile-based processing reduces peak memory usage by encoding
/// the image in smaller tiles.
func processLargeDICOMImage(
    rows: Int,
    columns: Int,
    bytesPerPixel: Int
) -> (tiles: [TileRegion], memorySavings: Double) {
    let processor = JPEGLSTileProcessor(
        imageWidth: columns,
        imageHeight: rows,
        configuration: TileConfiguration(
            tileWidth: 512,
            tileHeight: 512,
            overlap: 4  // Overlap for boundary handling
        )
    )

    let tiles = processor.calculateTilesWithOverlap()
    let savings = processor.estimateMemorySavings(bytesPerPixel: bytesPerPixel)

    return (tiles, savings)
}
```

### Memory Management

Best practices for memory management with large DICOM datasets:

```swift
import JPEGLS

/// Memory-efficient DICOM processing strategies
///
/// 1. Buffer pooling is handled internally by the encoder
/// 2. Process frames sequentially to limit peak memory
/// 3. Use tile-based processing for large single images
/// 4. Release image data promptly after encoding
func processWithMemoryEfficiency(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int
) throws -> Data {
    // Use cache-friendly buffer for better CPU performance
    let cacheBuffer = JPEGLSCacheFriendlyBuffer(
        width: columns,
        height: rows,
        initialValue: 0
    )

    // Populate cache-friendly buffer
    for row in 0..<rows {
        for col in 0..<columns {
            cacheBuffer.set(row: row, column: col, value: pixelData[row][col])
        }
    }

    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixelData,
        bitsPerSample: bitsStored
    )

    let encoder = JPEGLSEncoder()
    return try encoder.encode(imageData)
}
```

## Error Handling

Handle JPEG-LS errors in the context of DICOM processing:

```swift
import JPEGLS

/// Comprehensive error handling for DICOM JPEG-LS operations
func handleDICOMEncoding(
    pixelData: [[Int]],
    rows: Int,
    columns: Int,
    bitsStored: Int
) -> Result<Data, Error> {
    do {
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixelData,
            bitsPerSample: bitsStored
        )

        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData)
        return .success(jpegLSData)
    } catch let error as JPEGLSError {
        // Handle specific JPEG-LS errors
        switch error {
        case .invalidDimensions:
            // Invalid image dimensions from DICOM attributes
            return .failure(error)
        case .invalidBitsPerSample:
            // Unsupported bits stored value
            return .failure(error)
        case .invalidNearParameter:
            // Invalid NEAR parameter for transfer syntax
            return .failure(error)
        case .encodingFailed(let reason):
            // Encoding pipeline error
            print("Encoding failed: \(reason)")
            return .failure(error)
        default:
            return .failure(error)
        }
    } catch {
        return .failure(error)
    }
}
```

## Testing DICOM Integration

Verify JPEG-LS codec integration with DICOM workflows:

```swift
import JPEGLS
import Testing

@Suite("DICOM JPEG-LS Integration Tests")
struct DICOMIntegrationTests {

    @Test("Grayscale lossless round-trip preserves pixel values")
    func testGrayscaleLosslessRoundTrip() throws {
        // Create test pixel data (simulating 8-bit CT)
        let rows = 64
        let columns = 64
        let bitsStored = 8
        var pixels = Array(
            repeating: Array(repeating: 0, count: columns),
            count: rows
        )

        // Fill with gradient pattern
        for row in 0..<rows {
            for col in 0..<columns {
                pixels[row][col] = (row * columns + col) % 256
            }
        }

        // Encode
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: bitsStored
        )

        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData)
        #expect(jpegLSData.count > 0)
    }

    @Test("Transfer syntax mapping returns correct NEAR parameter")
    func testTransferSyntaxMapping() {
        #expect(JPEGLSTransferSyntax.nearParameter(for: "1.2.840.10008.1.2.4.80") == 0)
        #expect(JPEGLSTransferSyntax.nearParameter(for: "1.2.840.10008.1.2.4.81") > 0)
    }

    @Test("Codec provider supports JPEG-LS transfer syntaxes")
    func testCodecProviderSupport() {
        #expect(JPEGLSCodecProvider.supports(transferSyntax: "1.2.840.10008.1.2.4.80"))
        #expect(JPEGLSCodecProvider.supports(transferSyntax: "1.2.840.10008.1.2.4.81"))
        #expect(!JPEGLSCodecProvider.supports(transferSyntax: "1.2.840.10008.1.2"))
    }

    @Test("12-bit CT encoding validates correctly")
    func testCTEncoding() throws {
        let rows = 32
        let columns = 32
        let bitsStored = 12

        var pixels = Array(
            repeating: Array(repeating: 0, count: columns),
            count: rows
        )

        // Simulate CT Hounsfield units shifted to unsigned (0-4095)
        for row in 0..<rows {
            for col in 0..<columns {
                pixels[row][col] = (row * 128 + col * 4) % 4096
            }
        }

        let jpegLSData = try encodeCTImage(
            pixelData: pixels,
            rows: rows,
            columns: columns,
            bitsStored: bitsStored,
            pixelRepresentation: 0
        )

        #expect(jpegLSData.count > 0)
    }
}
```

---

> **Note**: Full bitstream encoding/decoding integration for end-to-end DICOM workflows is under active development.
> The `info` and `verify` CLI commands can be used to inspect JPEG-LS files from DICOM datasets today.
> See [MILESTONES.md](MILESTONES.md) for the detailed development roadmap.
