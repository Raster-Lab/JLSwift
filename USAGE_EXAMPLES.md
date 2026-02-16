# JLSwift Usage Examples

Comprehensive real-world examples demonstrating how to use JLSwift for JPEG-LS compression in various scenarios.

## Table of Contents

- [Basic Examples](#basic-examples)
  - [Simple Grayscale Encoding](#simple-grayscale-encoding)
  - [RGB Image Encoding](#rgb-image-encoding)
  - [Near-Lossless Compression](#near-lossless-compression)
  - [Decoding JPEG-LS Files](#decoding-jpeg-ls-files)
- [Advanced Examples](#advanced-examples)
  - [Medical Imaging Workflow](#medical-imaging-workflow)
  - [Batch Image Processing](#batch-image-processing)
  - [Large Image Processing with Tiling](#large-image-processing-with-tiling)
  - [Custom Preset Parameters](#custom-preset-parameters)
  - [Multi-Component with Different Interleaving](#multi-component-with-different-interleaving)
- [Performance Optimization Examples](#performance-optimization-examples)
  - [Using Buffer Pooling](#using-buffer-pooling)
  - [Cache-Friendly Data Layout](#cache-friendly-data-layout)
  - [Platform-Specific Acceleration](#platform-specific-acceleration)
  - [Memory-Efficient Streaming](#memory-efficient-streaming)
- [Error Handling Examples](#error-handling-examples)
  - [Robust File Processing](#robust-file-processing)
  - [Validation and Error Recovery](#validation-and-error-recovery)
- [Command-Line Tool Examples](#command-line-tool-examples)
  - [File Analysis and Inspection](#file-analysis-and-inspection)
  - [Batch Verification](#batch-verification)
  - [Scripting and Automation](#scripting-and-automation)

## Basic Examples

### Simple Grayscale Encoding

Encode a simple 8-bit grayscale image to JPEG-LS format:

```swift
import JPEGLS

// Example: Encoding a simple gradient image
func encodeGrayscaleImage() throws {
    // Create a simple 256x256 gradient image
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
    
    // Create grayscale image data
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    // Create lossless scan header
    let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
    
    // Create encoder
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    // Encode the image
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("Encoded \(statistics.pixelsEncoded) pixels")
    print("Encoded \(statistics.regularModeCount) in regular mode")
    print("Encoded \(statistics.runModeCount) in run mode")
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
        red: red,
        green: green,
        blue: blue,
        bitsPerSample: 8
    )
    
    // Create lossless RGB scan header (uses sample interleaving by default)
    let scanHeader = try JPEGLSScanHeader.rgbLossless()
    
    // Create encoder
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    // Encode the image
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("Encoded RGB image: \(width)x\(height)")
    print("Total pixels: \(statistics.pixelsEncoded)")
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
    
    // Create near-lossless scan header with NEAR=3
    // This allows maximum error of ±3 gray levels
    let scanHeader = try JPEGLSScanHeader(
        componentCount: 1,
        components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
        near: 3,  // Maximum error: ±3
        interleaveMode: .none
    )
    
    // Create encoder
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    // Encode
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("Near-lossless encoding (NEAR=3)")
    print("Pixels encoded: \(statistics.pixelsEncoded)")
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
    
    // Parse the file structure
    let parser = JPEGLSParser()
    let parseResult = try parser.parse(data: data)
    
    print("File parsed successfully:")
    print("  Dimensions: \(parseResult.frameHeader.width)x\(parseResult.frameHeader.height)")
    print("  Bits per sample: \(parseResult.frameHeader.bitsPerSample)")
    print("  Components: \(parseResult.frameHeader.componentCount)")
    print("  Scans: \(parseResult.scanHeaders.count)")
    
    // Display scan information
    for (index, scanHeader) in parseResult.scanHeaders.enumerated() {
        print("\nScan \(index + 1):")
        print("  Components: \(scanHeader.componentCount)")
        print("  NEAR: \(scanHeader.near) (\(scanHeader.near == 0 ? "lossless" : "near-lossless"))")
        print("  Interleave mode: \(scanHeader.interleaveMode)")
    }
    
    // TODO: Full decoding requires bitstream reader integration (Phase 7.1 - encode/decode commands)
    // See MILESTONES.md Phase 7.1 for status of bitstream I/O integration
    // For now, we can validate the file structure
}

// Example usage
try decodeJPEGLSFile(from: "medical_image.jls")
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
    let maxValue = (1 << bitsPerSample) - 1  // Example: 4095 when bitsPerSample is 12
    
    // Load medical image data (example: CT scan)
    let pixels = loadMedicalImageData(width: width, height: height)
    
    // Create image data
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: bitsPerSample
    )
    
    // Use lossless compression for diagnostic images
    let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
    
    // Create encoder
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    // Use buffer pooling for better performance
    let contextBuffer = sharedBufferPool.acquire(type: .contextArrays, size: 365)
    defer { sharedBufferPool.release(contextBuffer, type: .contextArrays) }
    
    // Encode
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("Medical image encoded:")
    print("  Dimensions: \(width)x\(height)")
    print("  Bit depth: \(bitsPerSample)-bit (\(maxValue + 1) gray levels)")
    print("  Pixels: \(statistics.pixelsEncoded)")
    print("  Compression: lossless")
    
    // Calculate compression statistics
    let uncompressedSize = width * height * 2  // 2 bytes per pixel for 12-bit
    print("  Uncompressed size: \(uncompressedSize) bytes")
    // Compressed size would come from bitstream writer (not yet integrated)
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
            
            // Create scan header
            let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
            
            // Create encoder
            let encoder = try JPEGLSMultiComponentEncoder(
                frameHeader: imageData.frameHeader,
                scanHeader: scanHeader
            )
            
            // Encode
            let buffer = JPEGLSPixelBuffer(imageData: imageData)
            let statistics = try encoder.encodeScan(buffer: buffer)
            
            print("  ✓ Success: \(statistics.pixelsEncoded) pixels")
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

### Large Image Processing with Tiling

Process large images efficiently using tile-based approach:

```swift
import JPEGLS

func processLargeImageWithTiles() throws {
    let imageWidth = 8192
    let imageHeight = 8192
    let tileWidth = 512
    let tileHeight = 512
    
    print("Processing large image: \(imageWidth)x\(imageHeight)")
    
    // Create tile processor
    let tileProcessor = JPEGLSTileProcessor(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        configuration: TileConfiguration(
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            overlap: 4
        )
    )
    
    // Calculate memory savings
    let savings = tileProcessor.estimateMemorySavings(bytesPerPixel: 2)
    print("Estimated memory reduction: \(Int(savings * 100))%")
    
    // Get tiles with overlap for proper boundary handling
    let tiles = tileProcessor.calculateTilesWithOverlap()
    print("Image divided into \(tiles.count) tiles")
    
    // Process each tile
    for (index, tile) in tiles.enumerated() {
        print("\nProcessing tile \(index + 1)/\(tiles.count):")
        print("  Position: (\(tile.x), \(tile.y))")
        print("  Size: \(tile.width)x\(tile.height)")
        
        // Load only the tile data (not the entire image)
        let tilePixels = loadImageTile(
            x: tile.x, y: tile.y,
            width: tile.width, height: tile.height,
            imageWidth: imageWidth, imageHeight: imageHeight
        )
        
        // Create image data for this tile
        let imageData = try MultiComponentImageData.grayscale(
            pixels: tilePixels,
            bitsPerSample: 8
        )
        
        // Encode the tile
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        print("  ✓ Encoded: \(statistics.pixelsEncoded) pixels")
    }
    
    print("\n✓ Large image processing complete")
}

func loadImageTile(x: Int, y: Int, width: Int, height: Int, 
                   imageWidth: Int, imageHeight: Int) -> [[Int]] {
    // Simulate loading a specific tile from a large image
    // In practice, this would read from file or memory-mapped data
    var pixels: [[Int]] = []
    
    for row in y..<min(y + height, imageHeight) {
        var pixelRow: [Int] = []
        for col in x..<min(x + width, imageWidth) {
            // Generate test pattern
            let value = (row + col) % 256
            pixelRow.append(value)
        }
        pixels.append(pixelRow)
    }
    
    return pixels
}

try processLargeImageWithTiles()
```

### Custom Preset Parameters

Use custom preset parameters for specialized compression:

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
        maxval: 255,      // Maximum sample value
        t1: 5,            // Threshold 1 (default: 3)
        t2: 10,           // Threshold 2 (default: 7)
        t3: 25,           // Threshold 3 (default: 21)
        reset: 128        // Context reset (default: 64)
    )
    
    // Create frame header with custom presets
    var frameHeader = imageData.frameHeader
    frameHeader.presetParameters = customPresets
    
    // Create scan header
    let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
    
    // Create encoder with custom presets
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: frameHeader,
        scanHeader: scanHeader
    )
    
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("Encoded with custom preset parameters:")
    print("  T1=\(customPresets.t1), T2=\(customPresets.t2), T3=\(customPresets.t3)")
    print("  RESET=\(customPresets.reset)")
    print("  Pixels: \(statistics.pixelsEncoded)")
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
        red: red,
        green: green,
        blue: blue,
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
                      mode: JPEGLSScanHeader.InterleaveMode) throws {
    // Create scan header with specified interleaving mode
    let scanHeader = try JPEGLSScanHeader(
        componentCount: 3,
        components: [
            JPEGLSScanHeader.ComponentSelector(id: 1),
            JPEGLSScanHeader.ComponentSelector(id: 2),
            JPEGLSScanHeader.ComponentSelector(id: 3)
        ],
        near: 0,
        interleaveMode: mode
    )
    
    // Create encoder
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    // Encode
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("  Mode: \(mode)")
    print("  Pixels encoded: \(statistics.pixelsEncoded)")
    print("  Regular mode: \(statistics.regularModeCount)")
    print("  Run mode: \(statistics.runModeCount)")
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

## Performance Optimization Examples

### Using Buffer Pooling

Optimize performance with buffer reuse:

```swift
import JPEGLS

func efficientBatchProcessing(imageCount: Int) throws {
    print("Processing \(imageCount) images with buffer pooling...")
    
    // Use shared buffer pool for context arrays
    for i in 0..<imageCount {
        // Acquire buffer from pool
        let buffer = sharedBufferPool.acquire(type: .contextArrays, size: 365)
        
        // Process image (simplified example)
        let pixels = createTestImage(width: 512, height: 512)
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: 8
        )
        
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let pixelBuffer = JPEGLSPixelBuffer(imageData: imageData)
        _ = try encoder.encodeScan(buffer: pixelBuffer)
        
        // Release buffer back to pool
        sharedBufferPool.release(buffer, type: .contextArrays)
        
        if (i + 1) % 10 == 0 {
            print("Processed \(i + 1) images...")
        }
    }
    
    // Check pool statistics
    print("\nBuffer pool statistics:")
    print("  Available buffers: \(sharedBufferPool.availableCount(for: .contextArrays))")
}

try efficientBatchProcessing(imageCount: 50)
```

### Cache-Friendly Data Layout

Use cache-friendly buffers for better performance:

```swift
import JPEGLS

func useCacheFriendlyBuffer() throws {
    let width = 1024
    let height = 1024
    
    // Create test image
    let pixels = createTestImage(width: width, height: height)
    
    // Create cache-friendly buffer
    let cacheFriendlyBuffer = JPEGLSCacheFriendlyBuffer(
        width: width,
        height: height,
        initialValue: 0
    )
    
    // Load image data into cache-friendly format
    for y in 0..<height {
        for x in 0..<width {
            cacheFriendlyBuffer.setPixel(x: x, y: y, value: pixels[y][x])
        }
    }
    
    print("Cache-friendly buffer created:")
    print("  Size: \(width)x\(height)")
    print("  Memory layout: contiguous row-major order")
    
    // Access pixels efficiently
    let topLeftPixel = cacheFriendlyBuffer.pixel(x: 0, y: 0)
    print("  Top-left pixel: \(topLeftPixel)")
    
    // Get entire row for vectorized operations
    let firstRow = cacheFriendlyBuffer.row(y: 0)
    print("  First row has \(firstRow.count) pixels")
    
    // Get neighbor pixels (efficient for prediction)
    if let neighbors = cacheFriendlyBuffer.getNeighbors(x: 10, y: 10) {
        print("  Neighbor access at (10, 10):")
        print("    West (a): \(neighbors.a)")
        print("    North (b): \(neighbors.b)")
        print("    NorthWest (c): \(neighbors.c)")
        print("    NorthEast (d): \(neighbors.d)")
    }
}

try useCacheFriendlyBuffer()
```

### Platform-Specific Acceleration

Leverage hardware acceleration automatically:

```swift
import JPEGLS

func demonstratePlatformAcceleration() {
    // Get the optimal accelerator for current platform
    let accelerator = selectPlatformAccelerator()
    
    print("Platform Accelerator: \(type(of: accelerator).platformName)")
    
    // Example pixel values
    let a = 100  // West
    let b = 110  // North
    let c = 105  // NorthWest
    let d = 115  // NorthEast
    
    // 1. Compute gradients
    let (d1, d2, d3) = accelerator.computeGradients(a: a, b: b, c: c)
    print("\nGradient Computation:")
    print("  D1 (horizontal): \(d1)")
    print("  D2 (vertical): \(d2)")
    print("  D3 (diagonal): \(d3)")
    
    // 2. MED prediction
    let predicted = accelerator.medPredictor(a: a, b: b, c: c)
    print("\nMED Prediction:")
    print("  Predicted value: \(predicted)")
    
    // 3. Quantize gradients
    let t1 = 3, t2 = 7, t3 = 21
    let (q1, q2, q3) = accelerator.quantizeGradients(
        d1: d1, d2: d2, d3: d3,
        t1: t1, t2: t2, t3: t3
    )
    print("\nGradient Quantization:")
    print("  Q1: \(q1), Q2: \(q2), Q3: \(q3)")
    
    // 4. Compute context
    let context = accelerator.computeContext(q1: q1, q2: q2, q3: q3)
    print("\nContext Computation:")
    print("  Context index: \(context)")
    
    #if arch(arm64)
    print("\nOptimizations: Using ARM NEON/SIMD instructions")
    #elseif arch(x86_64)
    print("\nOptimizations: Using SSE/AVX instructions")
    #else
    print("\nOptimizations: Using scalar operations")
    #endif
}

demonstratePlatformAcceleration()
```

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
        
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        totalPixelsProcessed += statistics.pixelsEncoded
        
        print("  ✓ Processed \(statistics.pixelsEncoded) pixels")
        
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
        
        // Set up encoder
        print("  Setting up encoder...")
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        // Encode
        print("  Encoding...")
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        print("  ✓ Success!")
        print("    Pixels encoded: \(statistics.pixelsEncoded)")
        print("    Regular mode: \(statistics.regularModeCount)")
        print("    Run mode: \(statistics.runModeCount)")
        
        // Save result (requires bitstream writer integration)
        print("  Output would be saved to: \(outputPath)")
        
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
        
    case .invalidNearValue(let near):
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
        
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: near,
            interleaveMode: .none
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        print("✓ Encoding successful!")
        print("  Pixels: \(statistics.pixelsEncoded)")
        
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
    
    # Note: encode command requires bitstream writer integration
    # jpegls encode "$raw_file" "$output_file" \
    #     --width 512 --height 512 \
    #     --bits-per-sample 12 \
    #     --quiet
    
    # For now, using info command as example
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

## Next Steps

### Documentation Resources

- [README.md](README.md) - Project overview and features
- [GETTING_STARTED.md](GETTING_STARTED.md) - Quick start guide
- [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) - Performance optimization
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

See [Copilot Instructions](.github/copilot-instructions.md) for coding guidelines and contribution requirements.

---

For questions or issues, please visit the [GitHub repository](https://github.com/Raster-Lab/JLSwift).
