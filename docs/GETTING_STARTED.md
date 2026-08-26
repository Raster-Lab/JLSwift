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

// 3. Create the encoder and encode (lossless by default)
let encoder = JPEGLSEncoder()
let jpegLSData = try encoder.encode(imageData)

print("Encoded \(pixels.count * pixels[0].count) pixels")
print("Output size: \(jpegLSData.count) bytes")
```

## Basic Usage

### Using the Library

#### Encoding a Greyscale Image

```swift
import JPEGLS

// Load your image data (example: 512×512 8-bit greyscale)
let width = 512
let height = 512
let pixels: [[Int]] = loadYourImageData() // Your image loading code

// Create greyscale image data
let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: 8
)

// Encode lossless using the high-level encoder
let encoder = JPEGLSEncoder()
let jpegLSData = try encoder.encode(imageData)

print("✓ Encoded \(width * height) pixels")
print("✓ Output: \(jpegLSData.count) bytes")
```

#### Encoding an RGB Image

```swift
import JPEGLS

// Separate colour channels (each is a 2D array)
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

// Encode lossless, sample-interleaved (recommended for RGB)
let encoder = JPEGLSEncoder()
let config = try JPEGLSEncoder.Configuration(
    near: 0,
    interleaveMode: .sample
)
let jpegLSData = try encoder.encode(imageData, configuration: config)

print("✓ Encoded \(jpegLSData.count) bytes across 3 components")
```

#### Near-Lossless Encoding

For lossy compression with controlled error bounds:

```swift
// Encode near-lossless (NEAR=3 means max error of ±3)
let encoder = JPEGLSEncoder()
let config = try JPEGLSEncoder.Configuration(near: 3)
let jpegLSData = try encoder.encode(imageData, configuration: config)

// Rest of encoding is the same...
```

#### Decoding a JPEG-LS File

```swift
import JPEGLS

// Load JPEG-LS file
let jpegLSData = try Data(contentsOf: URL(fileURLWithPath: "image.jls"))

// Decode using the high-level decoder
let decoder = JPEGLSDecoder()
let imageData = try decoder.decode(jpegLSData)

// Inspect frame header
print("Image: \(imageData.frameHeader.width)×\(imageData.frameHeader.height)")
print("Bits per sample: \(imageData.frameHeader.bitsPerSample)")
print("Components: \(imageData.frameHeader.componentCount)")

// Access pixel data
for (index, component) in imageData.components.enumerated() {
    print("Component \(index + 1): \(component.pixels.count) rows × \(component.pixels.first?.count ?? 0) cols")
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

#### Encode and Decode

Encode raw pixel data or PGM/PPM images to JPEG-LS, and decode them back:

```bash
# Encode raw pixel data to JPEG-LS
jpegls encode input.raw output.jls --width 512 --height 512 --bits-per-sample 8

# Encode a PGM or PPM image (dimensions detected automatically)
jpegls encode input.pgm output.jls
jpegls encode input.ppm output.jls

# Near-lossless encoding
jpegls encode input.pgm output.jls --near 3

# Decode JPEG-LS to PGM/PPM
jpegls decode input.jls output.pgm
jpegls decode input.jls output.ppm

# Compare two JPEG-LS or PGM/PPM files
jpegls compare original.jls decoded.jls
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

### Image Data Organisation

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
- **Encoder Configuration**: Specifies how the image is encoded (interleaving, NEAR parameter)

```swift
// Frame header (created automatically from image data)
let frameHeader = imageData.frameHeader
print("Width: \(frameHeader.width), Height: \(frameHeader.height)")

// Encoder configuration
let config = try JPEGLSEncoder.Configuration(
    near: 0,               // 0 = lossless
    interleaveMode: .none  // .none, .line, or .sample
)
```

### Interleaving Modes

Three modes for multi-component images:

1. **None** (`.none`): Encode each component separately
2. **Line-interleaved** (`.line`): Interleave by scan lines
3. **Sample-interleaved** (`.sample`): Interleave pixel by pixel (best for RGB)

```swift
// Sample-interleaved (recommended for RGB)
let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .sample)

// Line-interleaved
let config = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .line)
```

### Lossless vs Near-Lossless

- **Lossless** (`NEAR=0`): Perfect reconstruction, no quality loss
- **Near-Lossless** (`NEAR>0`): Controlled lossy compression with maximum error of ±NEAR

```swift
// Lossless (NEAR=0, the default)
let losslessData = try JPEGLSEncoder().encode(imageData)

// Near-lossless (NEAR=3 means max error of ±3)
let config = try JPEGLSEncoder.Configuration(near: 3)
let nearLosslessData = try JPEGLSEncoder().encode(imageData, configuration: config)
```

## Common Patterns

### Pattern 1: Processing Large Images with Restart Intervals

For large frames, parallelise a single image across cores with restart markers
(ITU-T.87 DRI/RSTm). There is no tiling API — the codec decodes each scan into
one flat pixel plane; restart intervals are the parallelism and
error-resilience mechanism:

```swift
import JPEGLS

// Large frames: parallelise a single image across cores with restart markers
let config = try JPEGLSEncoder.Configuration(restartInterval: 256)
let encoded = try JPEGLSEncoder().encode(imageData, configuration: config)
// Decoding splits at the RST markers automatically and decodes intervals concurrently.
```

Restart intervals are currently supported for lossless (NEAR = 0),
non-interleaved scans. Buffer pooling and SIMD acceleration are handled
internally by the codec — no setup is required.

### Pattern 2: Error Handling

Handle JPEG-LS errors gracefully:

```swift
import JPEGLS

do {
    let imageData = try MultiComponentImageData.grayscale(
        pixels: pixels,
        bitsPerSample: 8
    )
    
    let encoder = JPEGLSEncoder()
    let jpegLSData = try encoder.encode(imageData)
    
    print("✓ Success: Encoded \(jpegLSData.count) bytes")
    
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

- **[README.md](../README.md)**: Detailed feature documentation
- **[USAGE_EXAMPLES.md](USAGE_EXAMPLES.md)**: Comprehensive real-world usage examples
- **[MILESTONES.md](MILESTONES.md)**: Development roadmap and progress
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimisation guide
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
open Tests/JPEGLSTests/JPEGLSConformanceTests.swift
```

### Performance Benchmarking

Run performance benchmarks to measure encoding/decoding speed:

```bash
swift test --filter JPEGLSPerformanceBenchmarks
```

### Community

- **Issues**: [GitHub Issues](https://github.com/Raster-Lab/JLSwift/issues)
- **Contributing**: See [Copilot Instructions](../.github/copilot-instructions.md)

### Related Documentation

- **[USAGE_EXAMPLES.md](USAGE_EXAMPLES.md)** - Comprehensive real-world usage examples
- **[SWIFTUI_EXAMPLES.md](SWIFTUI_EXAMPLES.md)** - SwiftUI integration guide with image loading examples
- **[APPKIT_EXAMPLES.md](APPKIT_EXAMPLES.md)** - AppKit integration guide for macOS applications
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)** - Performance optimisation and benchmarking
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions

## Requirements

- Swift 6.2 or later
- Platforms: Linux, macOS 12+, iOS 15+
- Optimised for: Apple Silicon (M1/M2/M3) with ARM64 NEON
- Compatible with: x86-64 with SSE/AVX

---

Happy coding! 🚀
