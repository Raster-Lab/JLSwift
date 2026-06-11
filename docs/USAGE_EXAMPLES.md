# JLSwift Usage Examples

Comprehensive real-world examples demonstrating how to use JLSwift for JPEG-LS compression in various scenarios.

## Table of Contents

- [Basic Examples](#basic-examples)
  - [Simple Greyscale Encoding](#simple-greyscale-encoding)
  - [RGB Image Encoding](#rgb-image-encoding)
  - [Near-Lossless Compression](#near-lossless-compression)
  - [Decoding JPEG-LS Files](#decoding-jpeg-ls-files)
  - [End-to-End: Encode, Decode and Verify](#end-to-end-encode-decode-and-verify)
- [Advanced Examples](#advanced-examples)
  - [Medical Imaging Workflow](#medical-imaging-workflow)
  - [Batch Image Processing](#batch-image-processing)
  - [Large Image Processing with Restart Intervals](#large-image-processing-with-restart-intervals)
  - [Custom Preset Parameters](#custom-preset-parameters)
  - [Multi-Component with Different Interleaving](#multi-component-with-different-interleaving)
  - [Part 2 Extensions: Colour Transforms and Mapping Tables](#part-2-extensions-colour-transforms-and-mapping-tables)
- [Performance Optimisation Examples](#performance-optimisation-examples)
  - [Built-In Optimisations](#built-in-optimisations)
  - [Memory-Efficient Streaming](#memory-efficient-streaming)
- [Error Handling Examples](#error-handling-examples)
  - [Robust File Processing](#robust-file-processing)
  - [Validation and Error Recovery](#validation-and-error-recovery)
- [Command-Line Tool Examples](#command-line-tool-examples)
  - [File Analysis and Inspection](#file-analysis-and-inspection)
  - [Batch Verification](#batch-verification)
  - [Scripting and Automation](#scripting-and-automation)
- [Non-DICOM Usage Examples](#non-dicom-usage-examples)
  - [General-Purpose Image Compression](#general-purpose-image-compression)
  - [Web Asset Compression](#web-asset-compression)
  - [Archival Storage](#archival-storage)

## Basic Examples

### Simple Greyscale Encoding

Encode a simple 8-bit greyscale image to JPEG-LS format:

```swift
import JPEGLS

// Example: Encoding a simple gradient image
func encodeGrayscaleImage() throws {
    // Create a simple 256×256 gradient image
    let width = 256
    let height = 256
    var pixels: [[Int]] = []
    
    for y in 0..<height {
        var row: [Int] = []
        for x in 0..<width {
            // Create a diagonal gradient
            let value = (x + y) % 256
            row.append(value)
        }
        pixels.append(row)
    }
    
    // Create greyscale image data
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    // Encode using the high-level encoder (lossless, no interleaving)
    let encoder = JPEGLSEncoder()
    let jpegLSData = try encoder.encode(imageData)
    
    print("Encoded \(width * height) pixels")
    print("Output size: \(jpegLSData.count) bytes")
}

try encodeGrayscaleImage()
```

### RGB Image Encoding

Encode a full-color RGB image with sample interleaving:

```swift
import JPEGLS

func encodeRGBImage() throws {
    let width = 512
    let height = 512
    
    // Create RGB test pattern (red gradient, green gradient, blue constant)
    var red: [[Int]] = []
    var green: [[Int]] = []
    var blue: [[Int]] = []
    
    for y in 0..<height {
        var redRow: [Int] = []
        var greenRow: [Int] = []
        var blueRow: [Int] = []
        
        for x in 0..<width {
            redRow.append((x * 255) / width)
            greenRow.append((y * 255) / height)
            blueRow.append(128)
        }
        
        red.append(redRow)
        green.append(greenRow)
        blue.append(blueRow)
    }
    
    // Create RGB image data
    let imageData = try MultiComponentImageData.rgb(
        redPixels: red,
        greenPixels: green,
        bluePixels: blue,
        bitsPerSample: 8
    )
    
    // Encode using the high-level encoder (lossless, sample-interleaved)
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(
        near: 0,
        interleaveMode: .sample
    )
    let jpegLSData = try encoder.encode(imageData, configuration: config)
    
    print("Encoded RGB image: \(width)×\(height)")
    print("Output size: \(jpegLSData.count) bytes")
    print("Interleave mode: sample-interleaved")
}

try encodeRGBImage()
```

### Near-Lossless Compression

Use near-lossless compression for higher compression ratios with controlled quality loss:

```swift
import JPEGLS

func encodeNearLossless() throws {
    // Load or create your image data
    let width = 512
    let height = 512
    let pixels = createTestImage(width: width, height: height)
    
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    // Encode with near-lossless (NEAR=3 allows maximum error of ±3 grey levels)
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(near: 3)
    let jpegLSData = try encoder.encode(imageData, configuration: config)
    
    print("Near-lossless encoding (NEAR=3)")
    print("Output size: \(jpegLSData.count) bytes")
    print("Expected better compression than lossless with minimal quality loss")
}

func createTestImage(width: Int, height: Int) -> [[Int]] {
    var pixels: [[Int]] = []
    for y in 0..<height {
        var row: [Int] = []
        for x in 0..<width {
            // Checkerboard pattern
            let value = ((x / 8) + (y / 8)) % 2 == 0 ? 200 : 50
            row.append(value)
        }
        pixels.append(row)
    }
    return pixels
}

try encodeNearLossless()
```

### Decoding JPEG-LS Files

Parse and decode JPEG-LS files:

```swift
import JPEGLS
import Foundation

func decodeJPEGLSFile(from path: String) throws {
    // Read the JPEG-LS file
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    
    // Decode using the high-level decoder
    let decoder = JPEGLSDecoder()
    let imageData = try decoder.decode(data)
    
    print("File decoded successfully:")
    print("  Dimensions: \(imageData.frameHeader.width)×\(imageData.frameHeader.height)")
    print("  Bits per sample: \(imageData.frameHeader.bitsPerSample)")
    print("  Components: \(imageData.frameHeader.componentCount)")
    
    // Access pixel data
    for (index, component) in imageData.components.enumerated() {
        print("  Component \(index + 1): \(component.pixels.count) rows × \(component.pixels.first?.count ?? 0) columns")
    }
}

// Example usage
try decodeJPEGLSFile(from: "medical_image.jls")
```

### End-to-End: Encode, Decode and Verify

Encode an image, decode it, and verify pixel-exact round-trip:

```swift
import JPEGLS

/// Encodes image data to JPEG-LS, decodes it back, and verifies pixel equality.
func roundTripVerify() throws {
    let width = 128
    let height = 128

    // Build a gradient test image
    let pixels: [[Int]] = (0..<height).map { y in
        (0..<width).map { x in (x + y) % 256 }
    }

    // --- Encode ---
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    let encoder = JPEGLSEncoder()
    let jpegLSData = try encoder.encode(imageData)

    print("Encoded: \(jpegLSData.count) bytes (original: \(width * height) bytes)")

    // --- Decode ---
    let decoder = JPEGLSDecoder()
    let decoded = try decoder.decode(jpegLSData)

    // --- Verify ---
    let decodedPixels = decoded.components[0].pixels
    var mismatch = 0
    for y in 0..<height {
        for x in 0..<width {
            if decodedPixels[y][x] != pixels[y][x] {
                mismatch += 1
            }
        }
    }

    if mismatch == 0 {
        print("✓ Lossless round-trip verified — all \(width * height) pixels match exactly.")
    } else {
        print("✗ \(mismatch) pixel(s) differ after round-trip.")
    }
}

try roundTripVerify()
```

Near-lossless round-trip with bounded error verification:

```swift
import JPEGLS

func roundTripNearLossless(near: Int = 3) throws {
    let pixels: [[Int]] = (0..<64).map { y in (0..<64).map { x in x * 4 } }

    let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)

    let config = try JPEGLSEncoder.Configuration(near: near, interleaveMode: .none)
    let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
    let decoded = try JPEGLSDecoder().decode(encoded)

    let decodedPixels = decoded.components[0].pixels
    let maxError = (0..<64).flatMap { y in (0..<64).map { x in
        abs(decodedPixels[y][x] - pixels[y][x])
    }}.max() ?? 0

    print("NEAR=\(near): max pixel error = \(maxError) (limit: \(near))")
    assert(maxError <= near, "Error exceeds NEAR bound")
}

try roundTripNearLossless()
```

## Advanced Examples

### Medical Imaging Workflow

Complete workflow for medical imaging with 12-bit depth:

```swift
import JPEGLS

func processMedicalImage() throws {
    // Medical images often use 12-bit or 16-bit depth
    let width = 2048
    let height = 2048
    let bitsPerSample = 12
    let maxValue = (1 << bitsPerSample) - 1  // Calculated maximum value (e.g., 4095 for 12-bit)
    
    // Load medical image data (example: CT scan)
    let pixels = loadMedicalImageData(width: width, height: height)
    
    // Create image data
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: bitsPerSample
    )
    
    // Use lossless compression for diagnostic images
    let encoder = JPEGLSEncoder()
    let jpegLSData = try encoder.encode(imageData)
    
    print("Medical image encoded:")
    print("  Dimensions: \(width)×\(height)")
    print("  Bit depth: \(bitsPerSample)-bit (\(maxValue + 1) grey levels)")
    print("  Compression: lossless")
    
    // Calculate compression statistics
    let uncompressedSize = width * height * 2  // 2 bytes per pixel for 12-bit
    print("  Uncompressed size: \(uncompressedSize) bytes")
    print("  Compressed size: \(jpegLSData.count) bytes")
    print("  Compression ratio: \(String(format: "%.2f", Double(uncompressedSize) / Double(jpegLSData.count)))×")
}

func loadMedicalImageData(width: Int, height: Int) -> [[Int]] {
    // Simulate loading a medical image with tissue and bone
    // NOTE: This is simplified example code. Production code should use more efficient
    // algorithms or pre-computed lookup tables for large images.
    var pixels: [[Int]] = []
    let centerX = width / 2
    let centerY = height / 2
    
    for y in 0..<height {
        var row: [Int] = []
        for x in 0..<width {
            // Simulate Hounsfield units mapped to 12-bit range
            // Air: 0, Soft tissue: 2048, Bone: 3500
            let dx = x - centerX
            let dy = y - centerY
            let distanceSquared = dx * dx + dy * dy
            let threshold1 = (width / 4) * (width / 4)
            let threshold2 = (width / 3) * (width / 3)
            
            let value: Int
            if distanceSquared < threshold1 {
                value = 3500  // Bone
            } else if distanceSquared < threshold2 {
                value = 2048  // Soft tissue
            } else {
                value = 100   // Air
            }
            row.append(value)
        }
        pixels.append(row)
    }
    return pixels
}

try processMedicalImage()
```

### Batch Image Processing

Process multiple images efficiently:

```swift
import JPEGLS
import Foundation

struct ImageFile {
    let path: String
    let width: Int
    let height: Int
    let bitsPerSample: Int
}

func batchEncodeImages(images: [ImageFile]) throws {
    print("Processing \(images.count) images...")
    
    var successCount = 0
    var failureCount = 0
    
    for (index, imageFile) in images.enumerated() {
        do {
            print("\n[\(index + 1)/\(images.count)] Processing: \(imageFile.path)")
            
            // Load image data
            let pixels = try loadRawImage(path: imageFile.path, 
                                          width: imageFile.width, 
                                          height: imageFile.height)
            
            // Create image data
            let imageData = try MultiComponentImageData.grayscale(
                pixels: pixels,
                bitsPerSample: imageFile.bitsPerSample
            )
            
            // Encode using the high-level encoder
            let encoder = JPEGLSEncoder()
            let jpegLSData = try encoder.encode(imageData)
            
            print("  ✓ Success: \(jpegLSData.count) bytes")
            successCount += 1
            
        } catch {
            print("  ✗ Failed: \(error)")
            failureCount += 1
        }
    }
    
    print("\n--- Batch Summary ---")
    print("Total: \(images.count)")
    print("Success: \(successCount)")
    print("Failed: \(failureCount)")
}

func loadRawImage(path: String, width: Int, height: Int) throws -> [[Int]] {
    // Load raw image data from file
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    
    var pixels: [[Int]] = []
    var offset = 0
    
    for _ in 0..<height {
        var row: [Int] = []
        for _ in 0..<width {
            if offset < data.count {
                let value = Int(data[offset])
                row.append(value)
                offset += 1
            }
        }
        pixels.append(row)
    }
    
    return pixels
}

// Example usage
let images = [
    ImageFile(path: "image1.raw", width: 512, height: 512, bitsPerSample: 8),
    ImageFile(path: "image2.raw", width: 1024, height: 1024, bitsPerSample: 8),
    ImageFile(path: "image3.raw", width: 2048, height: 2048, bitsPerSample: 12)
]

try batchEncodeImages(images: images)
```

### Large Image Processing with Restart Intervals

Process large images efficiently using restart-interval parallelism
(ITU-T.87 DRI/RSTm). There is no tiling API — the codec works on one flat
pixel plane per scan; restart intervals are the parallelism and
error-resilience mechanism. Supported for lossless (NEAR = 0),
non-interleaved scans:

```swift
import JPEGLS

func processLargeImageWithRestartIntervals() throws {
    let imageWidth = 8192
    let imageHeight = 8192
    
    print("Processing large image: \(imageWidth)x\(imageHeight)")
    
    // Load the full frame (test pattern here; read from file in practice)
    var pixels: [[Int]] = []
    for row in 0..<imageHeight {
        var pixelRow: [Int] = []
        for col in 0..<imageWidth {
            pixelRow.append((row + col) % 256)
        }
        pixels.append(pixelRow)
    }
    
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    // Large frames: parallelise a single image across cores with restart markers
    let config = try JPEGLSEncoder.Configuration(restartInterval: 256)
    let jpegLSData = try JPEGLSEncoder().encode(imageData, configuration: config)
    // Decoding splits at the RST markers automatically and decodes intervals concurrently.
    
    print("✓ Encoded: \(jpegLSData.count) bytes")
}

try processLargeImageWithRestartIntervals()
```

### Custom Preset Parameters

Use custom preset parameters for specialised compression:

```swift
import JPEGLS

func encodeWithCustomPresets() throws {
    let width = 512
    let height = 512
    let pixels = createTestImage(width: width, height: height)
    
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    // Create custom preset parameters
    // Adjust thresholds for different image characteristics
    let customPresets = try JPEGLSPresetParameters(
        maxValue: 255,       // Maximum sample value
        threshold1: 5,       // Threshold 1 (default: 3)
        threshold2: 10,      // Threshold 2 (default: 7)
        threshold3: 25,      // Threshold 3 (default: 21)
        reset: 64            // Context reset (default: 64)
    )
    
    // Encode using the high-level encoder with custom preset parameters
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(
        near: 0,
        interleaveMode: .none,
        presetParameters: customPresets
    )
    let jpegLSData = try encoder.encode(imageData, configuration: config)
    
    print("Encoded with custom preset parameters:")
    print("  Threshold1=\(customPresets.threshold1), Threshold2=\(customPresets.threshold2), Threshold3=\(customPresets.threshold3)")
    print("  RESET=\(customPresets.reset)")
    print("  Encoded \(jpegLSData.count) bytes")
}

try encodeWithCustomPresets()
```

### Multi-Component with Different Interleaving

Compare different interleaving modes for RGB images:

```swift
import JPEGLS

func compareInterleavingModes() throws {
    let width = 512
    let height = 512
    
    // Create RGB test image
    let (red, green, blue) = createRGBTestImage(width: width, height: height)
    
    let imageData = try MultiComponentImageData.rgb(
        redPixels: red,
        greenPixels: green,
        bluePixels: blue,
        bitsPerSample: 8
    )
    
    // Test 1: No interleaving (separate component scans)
    print("1. No Interleaving (separate scans):")
    try testInterleaving(imageData: imageData, mode: .none)
    
    // Test 2: Line-interleaved
    print("\n2. Line-Interleaved:")
    try testInterleaving(imageData: imageData, mode: .line)
    
    // Test 3: Sample-interleaved (typical for RGB)
    print("\n3. Sample-Interleaved (recommended for RGB):")
    try testInterleaving(imageData: imageData, mode: .sample)
}

func testInterleaving(imageData: MultiComponentImageData,
                      mode: JPEGLSInterleaveMode) throws {
    // Encode with specified interleaving mode
    let encoder = JPEGLSEncoder()
    let config = try JPEGLSEncoder.Configuration(
        near: 0,
        interleaveMode: mode
    )
    let jpegLSData = try encoder.encode(imageData, configuration: config)
    
    print("  Mode: \(mode)")
    print("  Output size: \(jpegLSData.count) bytes")
}

func createRGBTestImage(width: Int, height: Int) -> ([[Int]], [[Int]], [[Int]]) {
    var red: [[Int]] = []
    var green: [[Int]] = []
    var blue: [[Int]] = []
    
    for y in 0..<height {
        var redRow: [Int] = []
        var greenRow: [Int] = []
        var blueRow: [Int] = []
        
        for x in 0..<width {
            // Create color gradients
            redRow.append((x * 255) / width)
            greenRow.append((y * 255) / height)
            blueRow.append(((x + y) * 255) / (width + height))
        }
        
        red.append(redRow)
        green.append(greenRow)
        blue.append(blueRow)
    }
    
    return (red, green, blue)
}

try compareInterleavingModes()
```

### Part 2 Extensions: Colour Transforms and Mapping Tables

#### Colour Transforms (HP1 / HP2 / HP3)

Colour space transformations decorrelate RGB components and can improve compression ratios for natural images:

```swift
import JPEGLS

func encodeWithColourTransform() throws {
    let width = 256
    let height = 256

    // Build a simple RGB gradient test image inline
    let red:   [[Int]] = (0..<height).map { _ in (0..<width).map { x in (x * 255) / width } }
    let green: [[Int]] = (0..<height).map { y in (0..<width).map { _ in (y * 255) / height } }
    let blue:  [[Int]] = (0..<height).map { y in (0..<width).map { x in ((x + y) * 255) / (width + height) } }

    let imageData = try MultiComponentImageData.rgb(
        redPixels: red, greenPixels: green, bluePixels: blue, bitsPerSample: 8
    )

    let encoder = JPEGLSEncoder()
    let decoder = JPEGLSDecoder()

    for transform in [JPEGLSColorTransformation.none, .hp1, .hp2, .hp3] {
        let config = try JPEGLSEncoder.Configuration(
            near: 0,
            interleaveMode: .sample,
            colorTransformation: transform
        )
        let encoded = try encoder.encode(imageData, configuration: config)
        let decoded = try decoder.decode(encoded)

        // Verify round-trip — decoded values must match original exactly for lossless
        let redDecoded   = decoded.components[0].pixels
        let greenDecoded = decoded.components[1].pixels
        let blueDecoded  = decoded.components[2].pixels

        var maxErr = 0
        for y in 0..<height {
            for x in 0..<width {
                maxErr = max(maxErr, abs(redDecoded[y][x] - red[y][x]))
                maxErr = max(maxErr, abs(greenDecoded[y][x] - green[y][x]))
                maxErr = max(maxErr, abs(blueDecoded[y][x] - blue[y][x]))
            }
        }

        print("\(transform): encoded=\(encoded.count) bytes, maxError=\(maxErr)")
    }
}

try encodeWithColourTransform()
```

#### Mapping Tables (Palette / Indexed Colour)

Mapping tables (LSE type 2) allow pixel indices to be looked up in a palette, enabling efficient encoding of palettised images:

```swift
import JPEGLS

func exploreMappingTables() throws {
    // Build a 4-level greyscale palette: index 0→0, 1→85, 2→170, 3→255
    let palette = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [0, 85, 170, 255])

    // Map raw decoded indices to palette values
    print(palette.map(0))   // 0
    print(palette.map(1))   // 85
    print(palette.map(2))   // 170
    print(palette.map(3))   // 255
    print(palette.map(99))  // 99 — out-of-range index returned unchanged

    print("Palette: \(palette)")  // JPEGLSMappingTable(id=1, entryWidth=1, entries=4)
}

try exploreMappingTables()
```

## Performance Optimisation Examples

### Built-In Optimisations

Buffer pooling, cache-friendly data layout, and platform-specific SIMD
acceleration are handled internally by the codec — there is no public API
for them and no setup is required. For parallelising large frames across
cores, use restart intervals:

```swift
import JPEGLS

// Large frames: parallelise a single image across cores with restart markers
let config = try JPEGLSEncoder.Configuration(restartInterval: 256)
let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
// Decoding splits at the RST markers automatically and decodes intervals concurrently.
```

See "Large Image Processing with Restart Intervals" above and
[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) for benchmarking guidance.

### Memory-Efficient Streaming

Process large images with minimal memory footprint:

```swift
import JPEGLS

func streamLargeImage() throws {
    let totalWidth = 16384
    let totalHeight = 16384
    let chunkHeight = 512  // Process 512 rows at a time
    
    print("Streaming large image: \(totalWidth)x\(totalHeight)")
    print("Chunk size: \(totalWidth)x\(chunkHeight)")
    
    var totalPixelsProcessed = 0
    
    // Process image in horizontal strips
    for chunkY in stride(from: 0, to: totalHeight, by: chunkHeight) {
        let currentChunkHeight = min(chunkHeight, totalHeight - chunkY)
        
        print("\nProcessing chunk at y=\(chunkY), height=\(currentChunkHeight)")
        
        // Load only one chunk into memory
        let chunkPixels = loadImageChunk(
            width: totalWidth,
            yStart: chunkY,
            height: currentChunkHeight
        )
        
        // Process the chunk
        let imageData = try MultiComponentImageData.grayscale(
            pixels: chunkPixels,
            bitsPerSample: 8
        )
        
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData)
        
        totalPixelsProcessed += totalWidth * currentChunkHeight
        
        print("  ✓ Processed \(jpegLSData.count) bytes")
        
        // The chunk data can now be discarded (garbage collected)
        // Only one chunk is in memory at a time
    }
    
    print("\n✓ Complete: Processed \(totalPixelsProcessed) pixels")
    print("  Peak memory: ~\(totalWidth * chunkHeight * 2) bytes per chunk")
}

func loadImageChunk(width: Int, yStart: Int, height: Int) -> [[Int]] {
    var pixels: [[Int]] = []
    
    for y in yStart..<(yStart + height) {
        var row: [Int] = []
        for x in 0..<width {
            // Generate test pattern
            let value = (x + y) % 256
            row.append(value)
        }
        pixels.append(row)
    }
    
    return pixels
}

try streamLargeImage()
```

## Error Handling Examples

### Robust File Processing

Handle errors gracefully in production code:

```swift
import JPEGLS
import Foundation

enum ProcessingError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
    case encodingFailed(String)
}

func processImageWithErrorHandling(inputPath: String, outputPath: String) {
    do {
        print("Processing: \(inputPath)")
        
        // Validate input file exists
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw ProcessingError.fileNotFound(inputPath)
        }
        
        // Load image data
        print("  Loading image data...")
        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        
        // Parse image dimensions from filename (example: image_512x512.raw)
        let filename = URL(fileURLWithPath: inputPath).lastPathComponent
        guard let dimensions = parseDimensions(from: filename) else {
            throw ProcessingError.invalidFormat("Could not parse dimensions from filename")
        }
        
        // Convert raw data to pixel array
        print("  Converting to pixel array...")
        let pixels = try convertDataToPixels(
            data: data,
            width: dimensions.width,
            height: dimensions.height
        )
        
        // Create image data structure
        print("  Creating image data structure...")
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        // Set up encoder and encode
        print("  Encoding...")
        let encoder = JPEGLSEncoder()
        let jpegLSData = try encoder.encode(imageData)
        
        print("  ✓ Success!")
        print("    Encoded \(jpegLSData.count) bytes")
        
        // Save result to output file
        try jpegLSData.write(to: URL(fileURLWithPath: outputPath))
        print("  Output saved to: \(outputPath)")
        
    } catch let error as JPEGLSError {
        print("  ✗ JPEG-LS Error: \(error)")
        handleJPEGLSError(error)
        
    } catch let error as ProcessingError {
        print("  ✗ Processing Error: \(error)")
        
    } catch {
        print("  ✗ Unexpected Error: \(error)")
    }
}

func handleJPEGLSError(_ error: JPEGLSError) {
    switch error {
    case .invalidDimensions(let width, let height):
        print("    Resolution \(width)x\(height) is not supported")
        print("    Valid range: 1-65535 for both dimensions")
        
    case .invalidBitsPerSample(let bits):
        print("    Bit depth \(bits) is not supported")
        print("    Valid range: 2-16 bits per sample")
        
    case .invalidComponentCount(let count):
        print("    Component count \(count) is not supported")
        print("    Valid values: 1 (grayscale) or 3 (RGB)")
        
    case .invalidNearParameter(let near):
        print("    NEAR value \(near) is not valid")
        print("    Valid range: 0-255")
        
    default:
        print("    Error details: \(error)")
    }
}

func parseDimensions(from filename: String) -> (width: Int, height: Int)? {
    // Example: "image_512x512.raw" -> (512, 512)
    let pattern = #"(\d+)x(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
          match.numberOfRanges == 3,
          let widthRange = Range(match.range(at: 1), in: filename),
          let heightRange = Range(match.range(at: 2), in: filename),
          let width = Int(filename[widthRange]),
          let height = Int(filename[heightRange]) else {
        return nil
    }
    return (width, height)
}

func convertDataToPixels(data: Data, width: Int, height: Int) throws -> [[Int]] {
    guard data.count >= width * height else {
        throw ProcessingError.invalidFormat("Data size mismatch")
    }
    
    var pixels: [[Int]] = []
    var offset = 0
    
    for _ in 0..<height {
        var row: [Int] = []
        for _ in 0..<width {
            row.append(Int(data[offset]))
            offset += 1
        }
        pixels.append(row)
    }
    
    return pixels
}

// Example usage
processImageWithErrorHandling(
    inputPath: "test_image_512x512.raw",
    outputPath: "output.jls"
)
```

### Validation and Error Recovery

Validate parameters before processing:

```swift
import JPEGLS

struct ImageValidation {
    static func validateDimensions(width: Int, height: Int) -> Result<Void, String> {
        if width < 1 || width > 65535 {
            return .failure("Width must be 1-65535, got \(width)")
        }
        if height < 1 || height > 65535 {
            return .failure("Height must be 1-65535, got \(height)")
        }
        return .success(())
    }
    
    static func validateBitsPerSample(_ bits: Int) -> Result<Void, String> {
        if bits < 2 || bits > 16 {
            return .failure("Bits per sample must be 2-16, got \(bits)")
        }
        return .success(())
    }
    
    static func validateNearValue(_ near: Int) -> Result<Void, String> {
        if near < 0 || near > 255 {
            return .failure("NEAR must be 0-255, got \(near)")
        }
        return .success(())
    }
    
    static func validatePixelData(pixels: [[Int]], width: Int, height: Int) -> Result<Void, String> {
        if pixels.count != height {
            return .failure("Expected \(height) rows, got \(pixels.count)")
        }
        
        for (index, row) in pixels.enumerated() {
            if row.count != width {
                return .failure("Row \(index): Expected \(width) pixels, got \(row.count)")
            }
        }
        
        return .success(())
    }
}

func safeImageEncoding(pixels: [[Int]], width: Int, height: Int, 
                       bitsPerSample: Int, near: Int) {
    print("Validating image parameters...")
    
    // Validate dimensions
    switch ImageValidation.validateDimensions(width: width, height: height) {
    case .success:
        print("  ✓ Dimensions valid: \(width)x\(height)")
    case .failure(let error):
        print("  ✗ \(error)")
        return
    }
    
    // Validate bits per sample
    switch ImageValidation.validateBitsPerSample(bitsPerSample) {
    case .success:
        print("  ✓ Bits per sample valid: \(bitsPerSample)")
    case .failure(let error):
        print("  ✗ \(error)")
        return
    }
    
    // Validate NEAR value
    switch ImageValidation.validateNearValue(near) {
    case .success:
        print("  ✓ NEAR value valid: \(near)")
    case .failure(let error):
        print("  ✗ \(error)")
        return
    }
    
    // Validate pixel data
    switch ImageValidation.validatePixelData(pixels: pixels, width: width, height: height) {
    case .success:
        print("  ✓ Pixel data valid")
    case .failure(let error):
        print("  ✗ \(error)")
        return
    }
    
    // All validations passed, proceed with encoding
    do {
        print("\nProceeding with encoding...")
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: bitsPerSample
        )
        
        let encoder = JPEGLSEncoder()
        let config = try JPEGLSEncoder.Configuration(near: near)
        let jpegLSData = try encoder.encode(imageData, configuration: config)
        
        print("✓ Encoding successful!")
        print("  Encoded \(jpegLSData.count) bytes")
        
    } catch {
        print("✗ Encoding failed: \(error)")
    }
}

// Test with valid data
let validPixels = createTestImage(width: 256, height: 256)
safeImageEncoding(
    pixels: validPixels,
    width: 256,
    height: 256,
    bitsPerSample: 8,
    near: 0
)

// Test with invalid dimensions
print("\n--- Testing invalid dimensions ---")
safeImageEncoding(
    pixels: validPixels,
    width: 70000,  // Invalid: > 65535
    height: 256,
    bitsPerSample: 8,
    near: 0
)
```

## Command-Line Tool Examples

### File Analysis and Inspection

Use the CLI tool to inspect JPEG-LS files:

```bash
# Get basic information about a JPEG-LS file
jpegls info medical_scan.jls

# Get detailed information in JSON format
jpegls info medical_scan.jls --json | jq .

# Quick one-line summary
jpegls info medical_scan.jls --quiet

# Check multiple files
for file in images/*.jls; do
    echo "File: $file"
    jpegls info "$file" --quiet
    echo ""
done
```

### Batch Verification

Verify multiple files in parallel:

```bash
# Verify all JPEG-LS files in a directory
jpegls batch verify "images/*.jls" --verbose

# Verify with custom parallelism (useful on systems with many CPU cores)
jpegls batch verify "images/*.jls" --parallelism 8

# Stop on first error (fail-fast mode)
jpegls batch verify "images/*.jls" --fail-fast

# Quiet mode for scripting (exit code indicates success/failure)
if jpegls batch verify "images/*.jls" --quiet; then
    echo "All files verified successfully"
else
    echo "Verification failed"
    exit 1
fi
```

### Scripting and Automation

Integrate JLSwift CLI into scripts:

```bash
#!/bin/bash
# automated_processing.sh - Process medical images

INPUT_DIR="./dicom_exports"
OUTPUT_DIR="./compressed"
LOG_FILE="processing.log"

mkdir -p "$OUTPUT_DIR"

echo "Starting batch processing..." | tee "$LOG_FILE"
echo "Input directory: $INPUT_DIR" | tee -a "$LOG_FILE"
echo "Output directory: $OUTPUT_DIR" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Count input files
file_count=$(ls -1 "$INPUT_DIR"/*.raw 2>/dev/null | wc -l)
echo "Found $file_count files to process" | tee -a "$LOG_FILE"

# Process each file
for raw_file in "$INPUT_DIR"/*.raw; do
    basename=$(basename "$raw_file" .raw)
    output_file="$OUTPUT_DIR/${basename}.jls"
    
    echo "Processing: $basename" | tee -a "$LOG_FILE"
    
    # Encode raw image to JPEG-LS
    jpegls encode "$raw_file" "$output_file" \
        --width 512 --height 512 \
        --bits-per-sample 12 \
        --quiet
    
    if [ -f "$output_file" ]; then
        jpegls info "$output_file" --quiet >> "$LOG_FILE"
    fi
done

echo "" | tee -a "$LOG_FILE"
echo "Processing complete!" | tee -a "$LOG_FILE"

# Verify all output files
echo "Verifying output files..." | tee -a "$LOG_FILE"
jpegls batch verify "$OUTPUT_DIR/*.jls" --quiet

if [ $? -eq 0 ]; then
    echo "✓ All files verified successfully" | tee -a "$LOG_FILE"
else
    echo "✗ Verification failed" | tee -a "$LOG_FILE"
    exit 1
fi
```

## Non-DICOM Usage Examples

JLSwift is a general-purpose JPEG-LS codec with no DICOM dependencies. It can be used in any
context where lossless or near-lossless compression of continuous-tone images is needed — no
knowledge of DICOM is required.

### General-Purpose Image Compression

Compress any greyscale or colour image using JPEG-LS — suitable for scientific imaging,
photography, or any application that needs lossless compression:

```swift
import JPEGLS

/// Compress raw pixel data to JPEG-LS bytes.
///
/// - Parameters:
///   - pixels: Row-major pixel values (one element per pixel).
///   - width: Image width in pixels.
///   - height: Image height in pixels.
///   - bitsPerSample: Bit depth (2–16).
/// - Returns: Compressed JPEG-LS byte stream.
func compressImage(pixels: [[Int]], width: Int, height: Int, bitsPerSample: Int) throws -> [UInt8] {
    let config = try JPEGLSEncoder.Configuration(
        width: width,
        height: height,
        bitsPerSample: bitsPerSample,
        componentCount: 1
    )
    let encoder = JPEGLSEncoder(configuration: config)
    return try encoder.encode(components: [pixels])
}

/// Decompress JPEG-LS bytes back to raw pixels.
func decompressImage(data: [UInt8]) throws -> (pixels: [[Int]], width: Int, height: Int) {
    let decoder = JPEGLSDecoder()
    let result = try decoder.decode(data)
    let frame = result.frameHeader
    return (result.components[0], frame.width, frame.height)
}

// Round-trip example
let width = 512, height = 512
var pixels = [[Int]](repeating: [Int](repeating: 0, count: width), count: height)
for y in 0..<height {
    for x in 0..<width {
        pixels[y][x] = (x ^ y) & 0xFF  // synthetic test pattern
    }
}

let compressed = try compressImage(pixels: pixels, width: width, height: height, bitsPerSample: 8)
let (restored, w, h) = try decompressImage(data: compressed)
print("Compressed \(width)×\(height) to \(compressed.count) bytes (ratio: \(String(format: "%.2f", Double(width * height) / Double(compressed.count)))×)")
```

### Web Asset Compression

Use JPEG-LS as a lossless intermediate format for high-quality web assets before final
conversion. This preserves full fidelity for assets that require repeated editing:

```swift
import JPEGLS

/// Archive lossless JPEG-LS from a 3-component (RGB) image.
func archiveRGBImage(r: [[Int]], g: [[Int]], b: [[Int]], width: Int, height: Int) throws -> [UInt8] {
    let config = try JPEGLSEncoder.Configuration(
        width: width,
        height: height,
        bitsPerSample: 8,
        componentCount: 3,
        interleaveMode: .sample
    )
    let encoder = JPEGLSEncoder(configuration: config)
    return try encoder.encode(components: [r, g, b])
}

/// Restore RGB planes from a JPEG-LS byte stream.
func restoreRGBImage(data: [UInt8]) throws -> (r: [[Int]], g: [[Int]], b: [[Int]]) {
    let decoder = JPEGLSDecoder()
    let result = try decoder.decode(data)
    return (result.components[0], result.components[1], result.components[2])
}
```

### Archival Storage

Store scientific or sensor data using near-lossless compression to reduce file size while
keeping per-pixel error below a specified bound. This is useful for remote sensing,
astronomy, or instrument data where slight numerical tolerance is acceptable:

```swift
import JPEGLS

/// Compress 16-bit sensor data with a defined per-pixel error tolerance.
///
/// - Parameters:
///   - data: 2-D array of 16-bit sample values.
///   - width: Image width.
///   - height: Image height.
///   - tolerance: Maximum allowed reconstruction error per pixel (NEAR parameter).
/// - Returns: Compressed byte stream.
func archiveSensorData(data: [[Int]], width: Int, height: Int, tolerance: Int) throws -> [UInt8] {
    let config = try JPEGLSEncoder.Configuration(
        width: width,
        height: height,
        bitsPerSample: 16,
        componentCount: 1,
        near: tolerance
    )
    let encoder = JPEGLSEncoder(configuration: config)
    return try encoder.encode(components: [data])
}

// Example: compress 4 Mpixel 16-bit instrument frame with tolerance ≤ 4 DN
let frameWidth = 2048, frameHeight = 2048
// ... populate sensorFrame: [[Int]] with actual instrument data ...
// let compressed = try archiveSensorData(data: sensorFrame, width: frameWidth,
//                                        height: frameHeight, tolerance: 4)
// print("Archive size: \(compressed.count) bytes")
```

## Next Steps

### Documentation Resources

- [README.md](../README.md) - Project overview and features
- [GETTING_STARTED.md](GETTING_STARTED.md) - Quick start guide
- [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) - Performance optimisation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [MILESTONES.md](MILESTONES.md) - Development roadmap

### API Reference

Generate full API documentation:

```bash
swift package generate-documentation
```

### Test Suite

Explore the comprehensive test suite for more examples:

```bash
# View test files
ls Tests/JPEGLSTests/

# Run specific test suites
swift test --filter JPEGLSMultiComponentEncoderTests
swift test --filter CharLSConformanceTests
swift test --filter JPEGLSPerformanceBenchmarks
```

### Contributing

See [Copilot Instructions](../.github/copilot-instructions.md) for coding guidelines and contribution requirements.

### Related Documentation

- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Quick start guide with basic examples
- **[SWIFTUI_EXAMPLES.md](SWIFTUI_EXAMPLES.md)** - SwiftUI integration guide for iOS/macOS apps
- **[APPKIT_EXAMPLES.md](APPKIT_EXAMPLES.md)** - AppKit integration guide for macOS applications
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)** - Performance optimisation and benchmarking
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions

---

For questions or issues, please visit the [GitHub repository](https://github.com/Raster-Lab/JLSwift).
