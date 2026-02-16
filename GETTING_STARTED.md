# Getting Started with JLSwift

A quick guide to get you up and running with JPEG-LS compression using JLSwift.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
  - [Using the Library](#using-the-library)
  - [Using the Command-Line Tool](#using-the-command-line-tool)
- [Core Concepts](#core-concepts)
- [Common Patterns](#common-patterns)
- [Next Steps](#next-steps)

## Installation

### Swift Package Manager

Add JLSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
]
```

Then add the library to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["JPEGLS"]
)
```

### Building from Source

```bash
git clone https://github.com/Raster-Lab/JLSwift.git
cd JLSwift
swift build
```

## Quick Start

### 5-Minute Example: Encoding an Image

```swift
import JPEGLS

// 1. Prepare your image data as a 2D array
let pixels: [[Int]] = [
    [100, 110, 120, 130],
    [105, 115, 125, 135],
    [110, 120, 130, 140],
    [115, 125, 135, 145]
]

// 2. Create image data structure
let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: 8
)

// 3. Create a scan header (lossless compression)
let scanHeader = try JPEGLSScanHeader.grayscaleLossless()

// 4. Create the encoder
let encoder = try JPEGLSMultiComponentEncoder(
    frameHeader: imageData.frameHeader,
    scanHeader: scanHeader
)

// 5. Create pixel buffer and encode
let buffer = JPEGLSPixelBuffer(imageData: imageData)
let statistics = try encoder.encodeScan(buffer: buffer)

print("Encoded \(statistics.pixelsEncoded) pixels")
```

## Basic Usage

### Using the Library

#### Encoding a Grayscale Image

```swift
import JPEGLS

// Load your image data (example: 512x512 8-bit grayscale)
let width = 512
let height = 512
let pixels: [[Int]] = loadYourImageData() // Your image loading code

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

print("✓ Encoded \(statistics.pixelsEncoded) pixels")
```

#### Encoding an RGB Image

```swift
import JPEGLS

// Separate color channels (each is a 2D array)
let redPixels: [[Int]] = loadRedChannel()
let greenPixels: [[Int]] = loadGreenChannel()
let bluePixels: [[Int]] = loadBlueChannel()

// Create RGB image data
let imageData = try MultiComponentImageData.rgb(
    redPixels: redPixels,
    greenPixels: greenPixels,
    bluePixels: bluePixels,
    bitsPerSample: 8
)

// Create RGB lossless scan header (sample-interleaved)
let scanHeader = try JPEGLSScanHeader.rgbLossless()

// Create encoder
let encoder = try JPEGLSMultiComponentEncoder(
    frameHeader: imageData.frameHeader,
    scanHeader: scanHeader
)

// Encode the image
let buffer = JPEGLSPixelBuffer(imageData: imageData)
let statistics = try encoder.encodeScan(buffer: buffer)

print("✓ Encoded \(statistics.pixelsEncoded) pixels across \(statistics.componentCount) components")
```

#### Near-Lossless Encoding

For lossy compression with controlled error bounds:

```swift
// Create near-lossless scan header (NEAR=3 means max error of ±3)
let scanHeader = try JPEGLSScanHeader(
    componentCount: 1,
    components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
    near: 3,  // Maximum allowed error
    interleaveMode: .none
)

// Rest of encoding is the same...
```

#### Decoding a JPEG-LS File

```swift
import JPEGLS

// Load JPEG-LS file
let jpegLSData = try Data(contentsOf: URL(fileURLWithPath: "image.jls"))

// Parse the file
let parser = JPEGLSParser(data: jpegLSData)
let parseResult = try parser.parse()

// Inspect frame header
print("Image: \(parseResult.frameHeader.width)×\(parseResult.frameHeader.height)")
print("Bits per sample: \(parseResult.frameHeader.bitsPerSample)")
print("Components: \(parseResult.frameHeader.componentCount)")

// Inspect scan headers
for (index, scanHeader) in parseResult.scanHeaders.enumerated() {
    print("Scan \(index + 1): \(scanHeader.componentCount) components, \(scanHeader.interleaveMode)")
    print("  Mode: \(scanHeader.isLossless ? "lossless" : "near-lossless (NEAR=\(scanHeader.near))")")
}
```

### Using the Command-Line Tool

The `jpegls` command-line tool provides easy access to JPEG-LS operations.

#### Get Information About a File

```bash
# Human-readable output
jpegls info image.jls

# JSON output for programmatic use
jpegls info image.jls --json

# Quiet mode (single line)
jpegls info image.jls --quiet
```

#### Verify File Integrity

```bash
# Basic verification
jpegls verify image.jls

# Verbose output with details
jpegls verify image.jls --verbose

# Quiet mode (exit code 0 = success)
jpegls verify image.jls --quiet
echo $?  # Check exit code
```

#### Encode and Decode (Coming Soon)

Full encode/decode functionality requires bitstream integration (in progress):

```bash
# Encode raw pixel data to JPEG-LS
jpegls encode input.raw output.jls --width 512 --height 512 --bits-per-sample 8

# Decode JPEG-LS to raw pixel data
jpegls decode input.jls output.raw

# Near-lossless encoding
jpegls encode input.raw output.jls -w 512 -h 512 --near 3
```

#### Batch Processing

Process multiple files at once:

```bash
# Get info for all JPEG-LS files
jpegls batch info "images/*.jls"

# Verify all files with progress
jpegls batch verify "*.jls" --verbose

# Custom parallelism
jpegls batch info "*.jls" --parallelism 4
```

## Core Concepts

### Image Data Organization

JLSwift uses 2D arrays to represent image data:

```swift
// Grayscale: Single 2D array
let grayscale: [[Int]] = [
    [100, 110, 120],  // Row 0
    [105, 115, 125],  // Row 1
    [110, 120, 130]   // Row 2
]

// RGB: Three separate 2D arrays (one per color channel)
let red: [[Int]] = [[255, 200, 150], ...]
let green: [[Int]] = [[240, 190, 140], ...]
let blue: [[Int]] = [[230, 180, 130], ...]
```

### Frame Headers and Scan Headers

- **Frame Header**: Describes the entire image (dimensions, bits per sample, component count)
- **Scan Header**: Describes how the image is encoded (interleaving, NEAR parameter, components)

```swift
// Frame header (created automatically from image data)
let frameHeader = imageData.frameHeader

// Scan header (you create based on desired encoding)
let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
```

### Interleaving Modes

Three modes for multi-component images:

1. **None** (`.none`): Encode each component separately
2. **Line-interleaved** (`.line`): Interleave by scan lines
3. **Sample-interleaved** (`.sample`): Interleave pixel by pixel (best for RGB)

```swift
// Sample-interleaved (recommended for RGB)
let scanHeader = try JPEGLSScanHeader.rgbLossless()  // Uses .sample by default

// Line-interleaved
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
```

### Lossless vs Near-Lossless

- **Lossless** (`NEAR=0`): Perfect reconstruction, no quality loss
- **Near-Lossless** (`NEAR>0`): Controlled lossy compression with maximum error of ±NEAR

```swift
// Lossless (NEAR=0)
let lossless = try JPEGLSScanHeader.grayscaleLossless()

// Near-lossless (NEAR=3 means max error of ±3)
let nearLossless = try JPEGLSScanHeader(
    componentCount: 1,
    components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
    near: 3,
    interleaveMode: .none
)
```

## Common Patterns

### Pattern 1: Processing Large Images with Tiles

For memory-efficient processing of large images:

```swift
import JPEGLS

// Create tile processor
let processor = JPEGLSTileProcessor(
    imageWidth: 8192,
    imageHeight: 8192,
    configuration: TileConfiguration(
        tileWidth: 512,
        tileHeight: 512,
        overlap: 4
    )
)

// Calculate tiles
let tiles = processor.calculateTilesWithOverlap()

// Process each tile
for tile in tiles {
    print("Processing tile: \(tile.x),\(tile.y) size: \(tile.width)×\(tile.height)")
    // Load and process tile data...
}

// Estimate memory savings
let savings = processor.estimateMemorySavings(bytesPerPixel: 2)
print("Memory reduction: \(Int(savings * 100))%")
```

### Pattern 2: Buffer Pooling for Performance

Reuse buffers to reduce allocation overhead:

```swift
import JPEGLS

// Acquire buffer from pool
let buffer = sharedBufferPool.acquire(
    type: .contextArrays,
    size: 365  // JPEG-LS uses 365 regular contexts
)

// Use the buffer...
// (Your encoding/decoding code)

// Release buffer back to pool when done
defer {
    sharedBufferPool.release(buffer, type: .contextArrays)
}
```

### Pattern 3: Platform-Optimized Operations

Automatically use hardware acceleration:

```swift
import JPEGLS

// Get optimal accelerator for current platform
let accelerator = selectPlatformAccelerator()
print("Using: \(type(of: accelerator).platformName)")

// Use for gradient computations
let (d1, d2, d3) = accelerator.computeGradients(a: 100, b: 110, c: 105)

// Use for prediction
let predicted = accelerator.medPredictor(a: 100, b: 110, c: 105)

// Use for quantization
let (q1, q2, q3) = accelerator.quantizeGradients(
    d1: d1, d2: d2, d3: d3,
    t1: 3, t2: 7, t3: 21
)
```

### Pattern 4: Error Handling

Handle JPEG-LS errors gracefully:

```swift
import JPEGLS

do {
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
    let encoder = try JPEGLSMultiComponentEncoder(
        frameHeader: imageData.frameHeader,
        scanHeader: scanHeader
    )
    
    let buffer = JPEGLSPixelBuffer(imageData: imageData)
    let statistics = try encoder.encodeScan(buffer: buffer)
    
    print("✓ Success: Encoded \(statistics.pixelsEncoded) pixels")
    
} catch let error as JPEGLSError {
    switch error {
    case .invalidDimensions(let width, let height):
        print("✗ Invalid dimensions: \(width)×\(height)")
    case .invalidBitsPerSample(let bits):
        print("✗ Invalid bits per sample: \(bits) (must be 2-16)")
    case .invalidComponentCount(let count):
        print("✗ Invalid component count: \(count) (must be 1-4)")
    default:
        print("✗ Error: \(error)")
    }
} catch {
    print("✗ Unexpected error: \(error)")
}
```

## Next Steps

### Learn More

- **[README.md](README.md)**: Detailed feature documentation
- **[USAGE_EXAMPLES.md](USAGE_EXAMPLES.md)**: Comprehensive real-world usage examples
- **[MILESTONES.md](MILESTONES.md)**: Development roadmap and progress
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimization guide
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions

### API Documentation

Generate full API documentation using DocC:

```bash
swift package generate-documentation
```

### Examples

Check the test suite for comprehensive examples:

```bash
# View encoding examples
open Tests/JPEGLSTests/JPEGLSMultiComponentEncoderTests.swift

# View decoding examples
open Tests/JPEGLSTests/JPEGLSMultiComponentDecoderTests.swift

# View parser examples
open Tests/JPEGLSTests/CharLSConformanceTests.swift
```

### Performance Benchmarking

Run performance benchmarks to measure encoding/decoding speed:

```bash
swift test --filter JPEGLSPerformanceBenchmarks
```

### Community

- **Issues**: [GitHub Issues](https://github.com/Raster-Lab/JLSwift/issues)
- **Contributing**: See [Copilot Instructions](.github/copilot-instructions.md)

## Requirements

- Swift 6.2 or later
- Platforms: Linux, macOS 12+, iOS 15+
- Optimized for: Apple Silicon (M1/M2/M3) with ARM64 NEON
- Compatible with: x86-64 with SSE/AVX

---

Happy coding! 🚀
