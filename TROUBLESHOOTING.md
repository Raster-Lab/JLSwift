# Troubleshooting Guide

Common issues and solutions for JLSwift JPEG-LS compression.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Compilation Issues](#compilation-issues)
- [Runtime Errors](#runtime-errors)
- [Performance Issues](#performance-issues)
- [Memory Issues](#memory-issues)
- [File Format Issues](#file-format-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [Getting Help](#getting-help)

## Installation Issues

### Swift Package Manager Not Resolving Dependencies

**Problem**: Package resolution fails or takes very long.

**Solution**:
```bash
# Clear package cache
rm -rf .build
rm Package.resolved

# Resolve dependencies fresh
swift package resolve

# Update dependencies
swift package update
```

### Version Incompatibility

**Problem**: `error: package requires minimum Swift version 6.2`

**Solution**:
```bash
# Check your Swift version
swift --version

# Update Swift to 6.2 or later
# On macOS: Update Xcode to latest version
# On Linux: Download Swift 6.2+ from swift.org
```

### Missing Accelerate Framework

**Problem**: `error: no such module 'Accelerate'` on non-Apple platforms.

**Solution**:
The Accelerate framework is Apple-only. The library will fall back to scalar or x86-64 accelerators on Linux/Windows:

```swift
// Conditional import - safe on all platforms
#if canImport(Accelerate)
import Accelerate
let accel = AccelerateFrameworkAccelerator()
#else
let accel = selectPlatformAccelerator()  // Uses ARM64 or x86-64 or scalar
#endif
```

## Compilation Issues

### Architecture Mismatch

**Problem**: Compilation fails with architecture-specific code errors.

**Solution**:
Ensure you're building for the correct architecture:

```bash
# For Apple Silicon
swift build --arch arm64

# For Intel
swift build --arch x86_64

# Let Swift choose automatically (recommended)
swift build
```

### Conditional Compilation Errors

**Problem**: `#if arch(arm64)` or `#if arch(x86_64)` blocks causing errors.

**Solution**:
The code is designed to work across platforms. If you see errors:

1. Check Swift version (must be 6.2+)
2. Verify platform support
3. Report the issue with your platform details

### SIMD Type Errors

**Problem**: Errors with `SIMD4<Int32>` or other SIMD types.

**Solution**:
```bash
# Ensure Swift 6.2+ is installed
swift --version

# SIMD types are standard in Swift 5.0+
# Errors here usually indicate older Swift version
```

## Runtime Errors

### Invalid Dimensions Error

**Problem**: `JPEGLSError.invalidDimensions(width: X, height: Y)`

**Solution**:
```swift
// Check dimensions are valid (1-65535)
guard width >= 1 && width <= 65535,
      height >= 1 && height <= 65535 else {
    // Handle invalid dimensions
    print("Invalid dimensions: must be 1-65535")
    return
}

let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: 8
)
```

**Valid ranges**:
- Width: 1 to 65,535 pixels
- Height: 1 to 65,535 pixels

### Invalid Bits Per Sample Error

**Problem**: `JPEGLSError.invalidBitsPerSample(bits: X)`

**Solution**:
```swift
// Bits per sample must be 2-16
let validBits = max(2, min(16, bitsPerSample))

let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: validBits
)
```

**Valid range**: 2 to 16 bits per sample

**Common values**:
- 8-bit: Standard images
- 12-bit: Medical imaging (CT, MR)
- 16-bit: High-dynamic-range images

### Invalid Component Count Error

**Problem**: `JPEGLSError.invalidComponentCount(count: X)`

**Solution**:
```swift
// Component count must be 1-4
// 1 = Grayscale
// 3 = RGB
// 4 = CMYK (not yet supported)

// For grayscale
let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: 8
)  // componentCount = 1

// For RGB
let imageData = try MultiComponentImageData.rgb(
    redPixels: red,
    greenPixels: green,
    bluePixels: blue,
    bitsPerSample: 8
)  // componentCount = 3
```

### Invalid NEAR Parameter Error

**Problem**: `JPEGLSError.invalidNearParameter(near: X)`

**Solution**:
```swift
// NEAR must be 0-255
// 0 = lossless
// 1-255 = near-lossless with max error of ±NEAR

let validNear = max(0, min(255, near))

let scanHeader = try JPEGLSScanHeader(
    componentCount: 1,
    components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
    near: validNear,
    interleaveMode: .none
)
```

### Premature End of Stream Error

**Problem**: `JPEGLSError.prematureEndOfStream`

**Solution**:
This indicates corrupted or truncated JPEG-LS data:

```swift
do {
    let parser = JPEGLSParser(data: jpegLSData)
    let result = try parser.parse()
} catch JPEGLSError.prematureEndOfStream {
    print("File is corrupted or truncated")
    // Try to recover or use backup
} catch {
    print("Other error: \(error)")
}
```

**Common causes**:
- Incomplete file download
- Disk errors during write
- Truncated network transmission

### Invalid Marker Error

**Problem**: `JPEGLSError.invalidMarker(byte1: X, byte2: Y)`

**Solution**:
The file is not a valid JPEG-LS file:

```swift
do {
    let parser = JPEGLSParser(data: data)
    let result = try parser.parse()
} catch JPEGLSError.invalidMarker(let byte1, let byte2) {
    print("Not a valid JPEG-LS file: 0x\(String(format: "%02X%02X", byte1, byte2))")
    // Check if it's a different image format
} catch {
    print("Other error: \(error)")
}
```

**Verify file type**:
```bash
# Check file magic bytes
xxd -l 2 image.jls
# Should show: ff d8 (JPEG SOI marker)
```

## Performance Issues

### Slow Encoding/Decoding

**Problem**: Encoding or decoding is slower than expected.

**Solutions**:

1. **Use release builds**:
```bash
# Debug build (slow)
swift build

# Release build (fast) ✓
swift build -c release
```

2. **Check hardware acceleration**:
```swift
let accelerator = selectPlatformAccelerator()
print("Using: \(type(of: accelerator).platformName)")

// Should be:
// - "ARM64" on Apple Silicon
// - "x86-64" on Intel
// - "Scalar" as fallback
```

3. **Use appropriate interleaving**:
```swift
// For RGB: use sample-interleaved (fastest)
let scanHeader = try JPEGLSScanHeader.rgbLossless()  // .sample
```

4. **Profile your code**:
```bash
# macOS
xcodebuild -scheme YourTarget -configuration Release
# Open in Instruments > Time Profiler

# Linux
swift build -c release
perf record --call-graph=dwarf .build/release/YourApp
perf report
```

**See also**: [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)

### Throughput Lower Than Expected

**Problem**: Benchmark shows lower Mpixels/s than advertised.

**Factors affecting throughput**:
- Hardware (Apple Silicon > Intel > Others)
- Image content (flat regions > gradients > noise)
- Bit depth (8-bit > 12-bit > 16-bit)
- Component count (greyscale > RGB)
- Build configuration (release > debug)

**Expected ranges** (release build):
- Apple Silicon (M1/M2/M3): 10-50 Mpixels/s
- Intel (modern): 5-20 Mpixels/s
- x86-64 (generic): 2-10 Mpixels/s

**Benchmark your hardware**:
```bash
swift test -c release --filter JPEGLSPerformanceBenchmarks
```

## Memory Issues

### Out of Memory for Large Images

**Problem**: Encoding/decoding large images causes memory exhaustion.

**Solution**: Use tile-based processing:

```swift
import JPEGLS

// Instead of loading entire image
// let allPixels = loadEntireImage()  // ✗

// Load and process in tiles ✓
let processor = JPEGLSTileProcessor(
    imageWidth: 8192,
    imageHeight: 8192,
    configuration: TileConfiguration(
        tileWidth: 512,
        tileHeight: 512,
        overlap: 4
    )
)

let tiles = processor.calculateTilesWithOverlap()

for tile in tiles {
    let tilePixels = loadTileData(tile)
    processTile(tilePixels)
}
```

**Memory savings**:
- 4096×4096 with 512×512 tiles: 94% reduction
- 8192×8192 with 512×512 tiles: 97% reduction

### Memory Leaks

**Problem**: Memory usage grows over time when processing many images.

**Solution**: Use buffer pooling:

```swift
// Reuse buffers instead of allocating new ones
for imageData in imageBatch {
    let buffer = sharedBufferPool.acquire(
        type: .contextArrays,
        size: 365
    )
    defer {
        sharedBufferPool.release(buffer, type: .contextArrays)
    }
    
    // Use buffer for encoding/decoding
}
```

### Excessive Memory Allocation

**Problem**: Memory allocator spending too much time in allocation.

**Solution**:

1. **Pre-allocate buffers**:
```swift
// Pre-allocate with correct capacity
var pixels = [[Int]]()
pixels.reserveCapacity(height)

for _ in 0..<height {
    var row = [Int]()
    row.reserveCapacity(width)
    pixels.append(row)
}
```

2. **Use cache-friendly buffers**:
```swift
// Contiguous memory layout
let cacheFriendlyBuffer = JPEGLSCacheFriendlyBuffer(
    pixelData: [1: pixels],
    width: width,
    height: height
)
```

## File Format Issues

### Parser Cannot Read File

**Problem**: Parser fails to read a JPEG-LS file that opens in other tools.

**Possible causes**:

1. **CharLS extension markers**: JLSwift supports CharLS extension markers (0xFF60-0xFF7F)

2. **Non-standard markers**: Some encoders add proprietary markers

**Debug parsing**:
```swift
do {
    let parser = JPEGLSParser(data: data)
    let result = try parser.parse()
    
    print("Frame: \(result.frameHeader)")
    for (i, scan) in result.scanHeaders.enumerated() {
        print("Scan \(i): \(scan)")
    }
} catch {
    print("Parse error: \(error)")
    // Report the issue with file hex dump
}
```

**Hex dump for debugging**:
```bash
# First 64 bytes
xxd -l 64 problematic.jls

# Search for markers
xxd problematic.jls | grep "ffd8\|ffd9\|fff7\|fff8"
```

### Incompatible Files Between Encoders

**Problem**: File encoded by JLSwift doesn't decode in other tools (or vice versa).

**Note**: Full bitstream I/O is in development. Once complete:

1. **Validate with jpegls verify**:
```bash
jpegls verify image.jls --verbose
```

2. **Check conformance**:
```bash
# Run conformance tests
swift test --filter CharLSConformanceTests
```

3. **Report incompatibilities** with:
- File hex dump
- Error messages
- Software versions

## Platform-Specific Issues

### macOS / iOS

**Problem**: Build fails on macOS with Accelerate framework errors.

**Solution**:
```bash
# Ensure macOS 12+ (Monterey)
sw_vers

# Update Xcode to latest
# App Store > Updates > Xcode

# Clean build
rm -rf .build
swift build
```

**Problem**: Simulator build fails.

**Solution**:
```bash
# Build for simulator architecture
swift build --arch x86_64  # Intel simulator
swift build --arch arm64   # Apple Silicon simulator
```

### Linux

**Problem**: Platform accelerator not found on Linux.

**Solution**:
Linux uses x86-64 or scalar accelerator (Accelerate is Apple-only):

```swift
// This works on all platforms
let accelerator = selectPlatformAccelerator()
// Linux x86-64: Returns X86_64Accelerator
// Linux ARM64: Returns ARM64Accelerator  
// Linux other: Returns ScalarAccelerator
```

**Problem**: Build fails with Swift 6.2 on Ubuntu.

**Solution**:
```bash
# Download Swift 6.2 for your platform
wget https://download.swift.org/swift-6.2-release/...

# Extract and add to PATH
tar xzf swift-6.2-...
export PATH=/path/to/swift-6.2/usr/bin:$PATH

# Verify
swift --version
```

### Windows (Future Support)

JLSwift is designed for Apple platforms and Linux. Windows support is not currently planned but may work with Swift for Windows:

```bash
# Install Swift for Windows
# https://swift.org/download/

# Build (experimental)
swift build
```

## Getting Help

### Before Reporting an Issue

Please gather:

1. **Environment information**:
```bash
swift --version
uname -a
```

2. **JLSwift version**:
```bash
git rev-parse HEAD
```

3. **Minimal reproduction**:
```swift
// Simplest code that reproduces the issue
let pixels: [[Int]] = [[100, 110], [120, 130]]
let imageData = try MultiComponentImageData.grayscale(
    pixels: pixels,
    bitsPerSample: 8
)
// ... rest of code
```

4. **Error messages**: Complete error output

5. **File information** (for parsing issues):
```bash
xxd -l 128 problematic.jls > file-hex.txt
```

### Reporting Issues

[Create a GitHub issue](https://github.com/Raster-Lab/JLSwift/issues) with:

**Title**: Brief description (e.g., "Parser fails on CharLS file with extension markers")

**Body**:
```markdown
## Environment
- Swift version: 6.2
- Platform: macOS 14.0 (Apple Silicon M1)
- JLSwift version: commit abc123

## Problem
Describe what you're trying to do and what goes wrong.

## Reproduction
\`\`\`swift
// Minimal code to reproduce
let imageData = try MultiComponentImageData.grayscale(...)
\`\`\`

## Error Message
\`\`\`
Complete error output here
\`\`\`

## Expected Behavior
What you expected to happen.

## Additional Context
- File characteristics (if applicable)
- Workarounds tried
- Profiling data (if performance issue)
```

### Community Support

- **GitHub Discussions**: For questions and discussions
- **GitHub Issues**: For bug reports and feature requests
- **Contributing**: See `.github/copilot-instructions.md`

### Self-Service Debugging

**Enable verbose output**:
```swift
// Print debug information
print("Image: \(width)×\(height), \(bitsPerSample)-bit, \(componentCount) components")
print("Using accelerator: \(type(of: accelerator).platformName)")

do {
    let statistics = try encoder.encodeScan(buffer: buffer)
    print("Encoded: \(statistics.pixelsEncoded) pixels")
} catch {
    print("Error: \(error)")
    if let jpegLSError = error as? JPEGLSError {
        print("JPEG-LS error description: \(jpegLSError.description)")
    }
}
```

**Test with simple data**:
```swift
// Use known-good test data
let testPixels: [[Int]] = [
    [100, 100, 100, 100],
    [100, 100, 100, 100],
    [100, 100, 100, 100],
    [100, 100, 100, 100]
]

let testData = try MultiComponentImageData.grayscale(
    pixels: testPixels,
    bitsPerSample: 8
)

// If this works, issue is with your image data
```

### Useful Resources

- **[README.md](README.md)**: Project overview
- **[GETTING_STARTED.md](GETTING_STARTED.md)**: Quick start guide
- **[PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md)**: Performance optimisation
- **[MILESTONES.md](MILESTONES.md)**: Development roadmap
- **[API Documentation](https://developer.apple.com/documentation/docc)**: Generate with `swift package generate-documentation`

---

Can't find your issue? [Ask in GitHub Discussions](https://github.com/Raster-Lab/JLSwift/discussions) or [open a new issue](https://github.com/Raster-Lab/JLSwift/issues/new).
