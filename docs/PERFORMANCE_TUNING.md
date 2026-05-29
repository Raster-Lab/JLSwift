# Performance Tuning Guide

Optimise JPEG-LS encoding and decoding performance with JLSwift.

## Table of Contents

- [Overview](#overview)
- [Hardware Acceleration](#hardware-acceleration)
- [Memory Optimisation](#memory-optimisation)
- [Encoding Optimisation](#encoding-optimisation)
- [Decoding Optimisation](#decoding-optimisation)
- [Profiling and Benchmarking](#profiling-and-benchmarking)
- [Best Practices](#best-practices)

## Overview

JLSwift is designed for high performance on Apple Silicon while maintaining compatibility with x86-64. Performance characteristics vary significantly based on hardware, image characteristics, and encoding parameters.

### Performance Factors

| Factor | Impact | Optimisation |
|--------|---------|--------------|
| **Hardware** | High | Use ARM64 on Apple Silicon |
| **Image Size** | High | Consider tile-based processing for large images |
| **Bit Depth** | Medium | Higher bit depths require more processing |
| **Interleaving** | Medium | Sample-interleaved is fastest for RGB |
| **NEAR Parameter** | Low | Near-lossless slightly faster than lossless |
| **Image Content** | Medium | Flat regions compress faster (run mode) |

## Hardware Acceleration

### Platform Selection

JLSwift automatically selects the best accelerator for your platform:

```swift
import JPEGLS

let accelerator = selectPlatformAccelerator()
print("Using: \(type(of: accelerator).platformName)")
```

**Platform Priority:**
1. **ARM64**: Fastest on Apple Silicon (M1/M2/M3)
2. **x86-64**: Optimised for Intel processors
3. **Scalar**: Fallback for all platforms

### ARM64 / Apple Silicon (Best Performance)

- **NEON SIMD**: Vectorised gradient computation and prediction
- **Hardware**: M1, M2, M3, ARM64 processors
- **Speedup**: ~2-3x over scalar implementation

**Optimisation Tips:**
- Build with `-c release` for full optimisation
- Use Swift 6.2+ for best SIMD codegen
- Run on Apple Silicon devices for maximum benefit

```bash
# Build optimized for Apple Silicon
swift build -c release --arch arm64
```

### x86-64 / Intel (Good Performance)

- **SSE/AVX**: Vectorised operations on Intel processors
- **Hardware**: Intel Core, Xeon processors
- **Speedup**: ~1.5-2x over scalar implementation

```bash
# Build optimized for x86-64
swift build -c release --arch x86_64
```

### Accelerate Framework (Batch Operations)

For batch processing on Apple platforms:

```swift
import JPEGLS

#if canImport(Accelerate)
let accelerateAccel = AccelerateFrameworkAccelerator()

// Batch gradient computation for multiple pixels
let (d1Array, d2Array, d3Array) = accelerateAccel.computeBatchGradients(
    a: leftPixels,
    b: topPixels,
    c: topLeftPixels
)

// Statistical analysis
let stats = accelerateAccel.computeStatistics(pixelValues)
print("Mean: \(stats.mean), StdDev: \(stats.standardDeviation)")
#endif
```

**When to Use:**
- Processing large image regions (>1000 pixels)
- Preprocessing or statistical analysis
- Histogram computation

**When Not to Use:**
- Single-pixel operations (overhead outweighs benefits)
- Tight encoding/decoding loops

## Memory Optimisation

### Tile-Based Processing

For large images, tile-based processing reduces memory footprint:

```swift
import JPEGLS

// Configure tile processor
let processor = JPEGLSTileProcessor(
    imageWidth: 8192,
    imageHeight: 8192,
    configuration: TileConfiguration(
        tileWidth: 512,      // Adjust based on available memory
        tileHeight: 512,
        overlap: 4           // For boundary continuity
    )
)

// Estimate memory savings
let bytesPerPixel = 2  // 16-bit image
let savings = processor.estimateMemorySavings(bytesPerPixel: bytesPerPixel)
print("Memory reduction: \(Int(savings * 100))%")

// Calculate tiles
let tiles = processor.calculateTilesWithOverlap()

// Process tiles sequentially or in parallel
for tile in tiles {
    // Load only this tile's data
    let tileData = loadTileData(tile)
    
    // Process tile
    processTile(tileData)
}
```

**Tile Size Guidelines:**
- **Small tiles (256×256)**: Lower memory, more overhead
- **Medium tiles (512×512)**: Good balance ✓ Recommended
- **Large tiles (1024×1024)**: Higher memory, less overhead

**Memory Savings:**
- 8192×8192 image with 512×512 tiles: ~97% memory reduction
- 4096×4096 image with 512×512 tiles: ~94% memory reduction

### Buffer Pooling

Reuse buffers to reduce allocation overhead:

```swift
import JPEGLS

// Use global shared pool
let contextBuffer = sharedBufferPool.acquire(
    type: .contextArrays,
    size: 365
)
defer {
    sharedBufferPool.release(contextBuffer, type: .contextArrays)
}

// Or create a custom pool
let customPool = JPEGLSBufferPool()
let pixelBuffer = customPool.acquire(type: .pixelData, size: width * height)
defer {
    customPool.release(pixelBuffer, type: .pixelData)
}
```

**Buffer Types:**
- `.contextArrays`: 365 Int arrays for context states
- `.pixelData`: Large pixel data buffers
- `.bitstreamData`: Encoded bitstream buffers

**Performance Impact:**
- First allocation: Standard speed
- Reused allocations: ~5-10x faster
- Best for: Encoding/decoding many images in sequence

### Cache-Friendly Data Layout

Use contiguous memory for better cache locality:

```swift
import JPEGLS

// Convert 2D arrays to cache-friendly format
let cacheFriendlyBuffer = JPEGLSCacheFriendlyBuffer(
    pixelData: [
        1: pixels  // Component 1 (grayscale or red)
    ],
    width: width,
    height: height
)

// Access patterns optimized for CPU cache
let row = cacheFriendlyBuffer.getRow(componentId: 1, row: rowIndex)
let rows = cacheFriendlyBuffer.getRows(componentId: 1, rowStart: 0, rowEnd: 10)
```

**Benefits:**
- ~10-20% faster neighbour access
- Better prefetching from memory
- Reduced cache misses in tight loops

## Encoding Optimisation

### Interleaving Mode Selection

Choose interleaving based on image type:

```swift
// Greyscale: Always use .none
let greyscaleConfig = try JPEGLSEncoder.Configuration(
    near: 0,
    interleaveMode: .none  // Required for single component
)

// RGB: Use .sample for best performance
let rgbConfig = try JPEGLSEncoder.Configuration(
    near: 0,
    interleaveMode: .sample  // Best cache locality
)

// Alternative: Line-interleaved (slightly slower)
let lineConfig = try JPEGLSEncoder.Configuration(
    near: 0,
    interleaveMode: .line
)
```

**Performance Comparison:**
- Sample-interleaved: Fastest (best cache locality) ✓
- Line-interleaved: ~5-10% slower
- None (separate scans): ~10-15% slower

### Near-Lossless vs Lossless

Near-lossless encoding can be slightly faster:

```swift
// Lossless (NEAR=0)
let losslessData = try JPEGLSEncoder().encode(imageData)

// Near-lossless (NEAR=3)
let config = try JPEGLSEncoder.Configuration(near: 3)  // Allows ±3 error
let nearLosslessData = try JPEGLSEncoder().encode(imageData, configuration: config)
```

**Performance Impact:**
- Near-lossless: ~5-10% faster
- Compression ratio: ~10-30% better
- Use when: Perfect reconstruction not required

### Image Content Characteristics

Different content types compress at different speeds:

| Content Type | Relative Speed | Why |
|--------------|----------------|-----|
| Flat regions | Fastest (100%) | Run mode dominates |
| Gradients | Medium (70%) | Regular mode with smooth transitions |
| High-frequency | Slowest (50%) | Regular mode with many context switches |
| Medical images | Medium (65%) | Mix of flat and textured regions |

**Optimisation:**
- Pre-process images to increase flat regions (lossy only)
- Consider tiling to isolate different content types
- Use profiling to identify bottlenecks

## Decoding Optimisation

### Parser Optimisation

The parser reads and validates JPEG-LS file structure:

```swift
import JPEGLS

// Parse file
let data = try Data(contentsOf: fileURL)
let parser = JPEGLSParser(data: data)
let result = try parser.parse()

// Cache parsed results for multiple operations
let frameHeader = result.frameHeader
let scanHeaders = result.scanHeaders
let presetParams = result.presetParameters
```

**Tips:**
- Parse once, decode multiple times if needed
- Validate file structure before decoding
- Cache frame and scan headers

### Bitstream Reading

Efficient bitstream reading is critical:

```swift
import JPEGLS

let reader = JPEGLSBitstreamReader(data: encodedData)

// Reset bit buffer at scan boundaries
reader.resetBitBuffer()

// Seek to specific positions when needed
try reader.seek(to: scanDataOffset)
```

**Performance Tips:**
- Minimise bit buffer resets
- Use seek() sparingly (resets bit buffer)
- Read in larger chunks when possible

## Profiling and Benchmarking

### Built-in Benchmarks

Run comprehensive benchmarks:

```bash
# Run all performance benchmarks
swift test --filter JPEGLSPerformanceBenchmarks

# Run specific benchmark
swift test --filter "benchmarkEncode512x512"
```

**Benchmark Categories:**
1. **Encoding by size**: 256×256 to 4096×4096
2. **Encoding by bit depth**: 8-bit, 12-bit, 16-bit
3. **Encoding by component**: Greyscale, RGB
4. **Near-lossless**: NEAR=3, NEAR=10
5. **Interleaving modes**: none, line, sample
6. **Content types**: flat, gradient, medical-like

### Custom Benchmarking

```swift
import JPEGLS
import Foundation

// Measure encoding time
let startTime = Date()

let encoder = JPEGLSEncoder()
let jpegLSData = try encoder.encode(imageData)

let elapsed = Date().timeIntervalSince(startTime)

// Calculate throughput
let pixelCount = imageData.frameHeader.width * imageData.frameHeader.height
let throughputPixels = Double(pixelCount) / elapsed / 1_000_000.0  // Mpixels/s
let throughputBytes = Double(pixelCount) / elapsed / 1_000_000.0   // MB/s

print("Encoded \(pixelCount) pixels in \(elapsed) seconds")
print("Throughput: \(throughputPixels) Mpixels/s, \(throughputBytes) MB/s")
```

### Profiling Tools

**macOS / Xcode:**
```bash
# Use Instruments for detailed profiling
xcodebuild -scheme JPEGLS -configuration Release
# Open in Instruments: Time Profiler, Allocations, System Trace
```

**Linux:**
```bash
# Use perf for CPU profiling
swift build -c release
perf record --call-graph=dwarf .build/release/YourApp
perf report
```

### Platform Benchmarks

Compare performance across accelerators:

```bash
# Run platform benchmark tests
swift test --filter PlatformBenchmarks
```

**Expected Results (relative to scalar):**
- ARM64: 2-3x faster
- x86-64: 1.5-2x faster
- Accelerate (batch): 3-5x faster for large batches

## Best Practices

### Build Configuration

Always use release builds for production:

```bash
# Release build with optimizations
swift build -c release

# Debug build for development (slower)
swift build -c debug
```

**Optimisation flags:**
- `-c release`: Full optimisations, no debug symbols
- `-c debug`: No optimisations, full debug info

### Concurrency

Process multiple images in parallel:

```swift
import JPEGLS
import Foundation

// Process images concurrently
await withTaskGroup(of: Data.self) { group in
    for imageData in imageBatch {
        group.addTask {
            let encoder = JPEGLSEncoder()
            return try encoder.encode(imageData)
        }
    }
    
    for await encoded in group {
        print("Encoded \(encoded.count) bytes")
    }
}
```

**Scaling:**
- CPU-bound: Use processor count parallel tasks
- I/O-bound: Use 2-4x processor count
- Memory-limited: Use fewer parallel tasks

### Image Size Guidelines

| Image Size | Processing Strategy | Memory | Speed |
|------------|-------------------|---------|-------|
| < 512×512 | Direct encoding | Low | Fastest |
| 512-2048 | Direct or tiled | Medium | Fast |
| 2048-4096 | Tiled recommended | Medium | Medium |
| > 4096 | Tiled required | High | Slower |

### Memory Usage Estimates

| Image | Uncompressed | Tiled (512×512) | Savings |
|-------|--------------|-----------------|---------|
| 2048×2048, 8-bit | 4 MB | 256 KB | 94% |
| 4096×4096, 8-bit | 16 MB | 256 KB | 98% |
| 8192×8192, 16-bit | 128 MB | 512 KB | 99.6% |

### Monitoring Performance

Track key metrics:

```swift
import JPEGLS

// Monitor encoding statistics
let statistics = try encoder.encodeScan(buffer: buffer)

print("Pixels encoded: \(statistics.pixelsEncoded)")
print("Components: \(statistics.componentCount)")
print("Interleave mode: \(statistics.interleaveMode)")

// Calculate compression ratio (when bitstream I/O available)
// let uncompressedSize = width * height * bytesPerSample
// let compressedSize = encodedData.count
// let ratio = Double(uncompressedSize) / Double(compressedSize)
```

### Common Pitfalls

❌ **Avoid:**
- Debug builds in production
- Processing large images without tiling
- Ignoring platform-specific optimisations
- Frequent buffer allocations without pooling

✅ **Prefer:**
- Release builds with full optimisations
- Tile-based processing for large images
- Using `selectPlatformAccelerator()` for automatic optimisation
- Buffer pooling for repeated operations
- Cache-friendly data layouts for neighbour access

## Summary

### Quick Wins

1. **Use release builds**: 2-5x faster than debug
2. **Run on Apple Silicon**: 2-3x faster with ARM64
3. **Use tile-based processing**: 90%+ memory savings for large images
4. **Enable buffer pooling**: 5-10x faster allocations
5. **Choose sample-interleaving**: Fastest for RGB images

### Advanced Optimisations

1. Cache-friendly buffers for neighbour access
2. Accelerate framework for batch operations
3. Parallel processing for multiple images
4. Content-aware tile sizing
5. Custom profiling and benchmarking

### Measurement

Before optimising, always:
1. Profile your specific workload
2. Run benchmarks on target hardware
3. Measure memory usage patterns
4. Validate compression ratios
5. Test with representative images

---

For questions or performance issues, please [open an issue](https://github.com/Raster-Lab/JLSwift/issues) with:
- Hardware details (CPU, memory)
- Image characteristics (size, bit depth, content type)
- Benchmark results
- Profiling data if available
