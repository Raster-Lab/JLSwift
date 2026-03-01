# Metal GPU Acceleration

## Overview

JLSwift includes optional GPU acceleration using Apple's Metal framework for JPEG-LS encoding operations. Metal compute shaders provide massive parallelism for pixel-level operations, significantly improving performance for large medical images on Apple Silicon and Intel Macs with discrete GPUs.

## Architecture

### Design Philosophy

The Metal GPU acceleration follows these principles:

1. **Smart Workload Distribution**: GPU is used only when beneficial (large batches), with automatic CPU fallback for small images
2. **Bit-Exact Results**: GPU and CPU implementations produce identical results
3. **Zero Dependencies**: Conditionally compiled only on platforms with Metal support
4. **Graceful Degradation**: Falls back to CPU when Metal is unavailable

### Components

```
Platform/Metal/
├── MetalAccelerator.swift      # Swift API for GPU acceleration
└── JPEGLSShaders.metal         # Metal compute shaders (MSL)
```

### Supported Operations (Phase 15.1)

| Shader | Description |
|--------|-------------|
| `compute_gradients` | Batch D1/D2/D3 gradient computation |
| `compute_med_prediction` | Batch MED (Median Edge Detector) prediction |
| `compute_quantize_gradients` | Batch gradient quantisation to context indices [-4, 4] |
| `compute_colour_transform_hp1_forward` | HP1 forward colour transform (R′=R−G, B′=B−G) |
| `compute_colour_transform_hp1_inverse` | HP1 inverse colour transform |
| `compute_colour_transform_hp2_forward` | HP2 forward colour transform |
| `compute_colour_transform_hp2_inverse` | HP2 inverse colour transform |
| `compute_colour_transform_hp3_forward` | HP3 forward colour transform |
| `compute_colour_transform_hp3_inverse` | HP3 inverse colour transform |
| `compute_encoding_pipeline` | **Full encoding preprocessing**: gradients + NEAR-aware quantisation + MED prediction + prediction error — single pass |
| `compute_decoding_pipeline` | **Full decoding reconstruction**: MED prediction + pixel reconstruction from entropy-decoded errors — single pass |

### Encoding Pipeline Shader

The `compute_encoding_pipeline` shader combines four operations into a single GPU dispatch:
1. Compute gradients D1, D2, D3 from neighbours (a=north, b=west, c=northwest)
2. Quantise gradients using NEAR-aware thresholds (supports both lossless and near-lossless)
3. Compute MED prediction from the same neighbours
4. Compute raw prediction error = pixel − prediction

This eliminates three separate dispatch calls, reducing GPU overhead for the hot encoding path:

```swift
// Old: three separate dispatches
let (d1, d2, d3) = try acc.computeGradientsBatch(a: a, b: b, c: c)
let (q1, q2, q3) = try acc.quantizeGradientsBatch(d1: d1, d2: d2, d3: d3, t1: 3, t2: 7, t3: 21)
let predictions  = try acc.computeMEDPredictionBatch(a: a, b: b, c: c)

// New: single dispatch
let (pred, err, q1, q2, q3) = try acc.computeEncodingPipelineBatch(
    a: a, b: b, c: c, x: currentPixels, near: 0, t1: 3, t2: 7, t3: 21)
```

### Decoding Pipeline Shader

The `compute_decoding_pipeline` shader reconstructs pixel values from the entropy-decoded
prediction errors. The CPU entropy decoder (Golomb-Rice) provides the errors; the GPU
handles the MED prediction and reconstruction for the entire row:

```swift
// Reconstruct pixels after Golomb-Rice decoding on CPU
let reconstructed = try acc.computeDecodingPipelineBatch(
    a: northPixels, b: westPixels, c: nwPixels, errval: entropyDecodedErrors)
```

## GPU vs CPU Decision

The `MetalAccelerator` automatically decides whether to use GPU or CPU based on batch size:

- **Small batches** (< 1024 pixels): Use CPU fallback
  - GPU overhead (buffer creation, data transfer) exceeds benefits
  - CPU single-pixel operations are more efficient
  
- **Large batches** (≥ 1024 pixels): Use GPU acceleration
  - Massive parallelism outweighs transfer overhead
  - Ideal for processing large medical images (e.g., 2048×2048 or larger)

## Usage

### Basic Usage

```swift
#if canImport(Metal)
import Metal

// Check Metal availability
guard MetalAccelerator.isSupported else {
    print("Metal not available, using CPU fallback")
    return
}

// Initialize Metal accelerator
let accelerator = try MetalAccelerator()

// Compute gradients for large batch
let a: [Int32] = // ... north pixel values
let b: [Int32] = // ... west pixel values  
let c: [Int32] = // ... northwest pixel values

let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)

// Compute MED predictions
let predictions = try accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)

// Quantise gradients to context indices (T1=3, T2=7, T3=21)
let (q1, q2, q3) = try accelerator.quantizeGradientsBatch(
    d1: d1, d2: d2, d3: d3, t1: 3, t2: 7, t3: 21)

// Apply HP1 colour transform
let (rPrime, gPrime, bPrime) = try accelerator.applyColourTransformForwardBatch(
    transform: .hp1, r: rPixels, g: gPixels, b: bPixels)
#endif
```

### Integration with Encoder

The Metal accelerator can be integrated into the encoding pipeline for processing image tiles:

```swift
#if canImport(Metal)
// For large images, use Metal for batch operations
if image.width * image.height >= 1024 * 1024 {
    let metalAccelerator = try? MetalAccelerator()
    // Use metalAccelerator for tile processing
}
#endif
```

### Error Handling

```swift
do {
    let accelerator = try MetalAccelerator()
    let results = try accelerator.computeGradientsBatch(a: a, b: b, c: c)
} catch MetalAcceleratorError.metalNotAvailable {
    print("Metal not supported on this device")
} catch MetalAcceleratorError.commandBufferExecutionFailed {
    print("GPU execution failed, falling back to CPU")
} catch {
    print("Unexpected error: \(error)")
}
```

## Performance Characteristics

### GPU Advantages

- **Massive Parallelism**: Process thousands of pixels simultaneously
- **Vectorised Operations**: SIMD operations on pixel data
- **Memory Bandwidth**: High-bandwidth GPU memory for large datasets

### GPU Overhead

- **Buffer Creation**: Allocating GPU buffers for input/output
- **Data Transfer**: CPU ↔ GPU memory transfers
- **Synchronization**: Waiting for GPU command completion

### Optimal Use Cases

✅ **Good for GPU:**
- Large images (2048×2048 or larger)
- Batch processing of multiple images
- High-resolution medical imaging (4K, 8K)
- Video frame processing

❌ **Better on CPU:**
- Small images (< 512×512)
- Single-pixel operations
- Real-time interactive editing
- Memory-constrained environments

## Platform Support

### Requirements

- **macOS 10.13+** (High Sierra or later)
- **iOS 11+**
- **tvOS 11+**
- **Mac with GPU**: Apple Silicon (M1/M2/M3) or Intel Mac with discrete GPU

### Conditional Compilation

Metal code is conditionally compiled only on supported platforms:

```swift
#if canImport(Metal)
// Metal GPU code
#endif
```

This ensures the library builds on Linux and other non-Apple platforms without Metal.

## Implementation Details

### Compute Shaders

The Metal shaders implement nine operations across three categories:

**Gradient Computation and Prediction:**

1. **Gradient Computation** (`compute_gradients`)
2. **MED Prediction** (`compute_med_prediction`)
3. **Gradient Quantisation** (`compute_quantize_gradients`) — maps each gradient to [-4, 4] using T1/T2/T3 thresholds

**Colour Space Transformations:**

4. **HP1 Forward** (`compute_colour_transform_hp1_forward`) — R′=R−G, G′=G, B′=B−G
5. **HP1 Inverse** (`compute_colour_transform_hp1_inverse`) — R=R′+G′, G=G′, B=B′+G′
6. **HP2 Forward** (`compute_colour_transform_hp2_forward`) — R′=R−G, G′=G, B′=B−((R+G)>>1)
7. **HP2 Inverse** (`compute_colour_transform_hp2_inverse`)
8. **HP3 Forward** (`compute_colour_transform_hp3_forward`) — B′=B, R′=R−B, G′=G−((R+B)>>1)
9. **HP3 Inverse** (`compute_colour_transform_hp3_inverse`)

### Thread Group Configuration

The accelerator dynamically calculates optimal thread group sizes based on:
- Pipeline state maximum threads per threadgroup
- Batch size
- GPU capabilities

```swift
let threadGroupSize = MTLSize(
    width: min(pipelineState.maxTotalThreadsPerThreadgroup, count),
    height: 1,
    depth: 1
)
```

### Memory Management

- **Shared Memory Mode**: Uses `.storageModeShared` for zero-copy access on Apple Silicon
- **Unified Memory**: Leverages Apple Silicon unified memory architecture
- **Automatic Buffer Management**: Buffers are automatically released after use

## Benchmarking

### Measuring Performance

```swift
let accelerator = try MetalAccelerator()
let startTime = Date()

let (d1, d2, d3) = try accelerator.computeGradientsBatch(a: a, b: b, c: c)

let elapsed = Date().timeIntervalSince(startTime)
let throughput = Double(a.count) / elapsed / 1_000_000.0 // Mpixels/s
print("Throughput: \(throughput) Mpixels/s")
```

### Expected Performance (Apple Silicon M1)

| Image Size | Pixels | GPU Throughput | CPU Throughput | Speedup |
|-----------|--------|----------------|----------------|---------|
| 512×512 | 262K | ~50 Mpixels/s | ~40 Mpixels/s | 1.25× |
| 1024×1024 | 1M | ~200 Mpixels/s | ~50 Mpixels/s | 4× |
| 2048×2048 | 4M | ~500 Mpixels/s | ~50 Mpixels/s | 10× |
| 4096×4096 | 16M | ~800 Mpixels/s | ~50 Mpixels/s | 16× |

*Note: Actual performance varies by device, image content, and system load.*

## Testing

The Metal accelerator includes comprehensive tests:

```bash
# Run Metal-specific tests (macOS/iOS only)
swift test --filter MetalAcceleratorTests

# Run Phase 15 GPU compute tests
swift test --filter MetalPhase15Tests
```

Tests verify:
- ✅ Initialisation and device detection
- ✅ Gradient computation correctness
- ✅ MED prediction correctness
- ✅ Gradient quantisation correctness (Phase 15.1)
- ✅ HP1 forward and inverse colour transforms (Phase 15.1)
- ✅ HP2 forward and inverse colour transforms (Phase 15.1)
- ✅ HP3 forward and inverse colour transforms (Phase 15.1)
- ✅ CPU fallback for small batches
- ✅ GPU execution for large batches
- ✅ Bit-exact match between Metal GPU and Vulkan CPU fallback
- ✅ Round-trip correctness (forward → inverse restores original)
- ✅ Edge cases and boundary values
- ✅ Error handling

## Future Enhancements

Potential improvements for future versions:

1. **Persistent Command Buffers**: Reuse command buffers for repeated operations
2. **Async Execution**: Non-blocking GPU operations with completion handlers
3. **Multi-GPU Support**: Distribute work across multiple GPUs
4. **Metal Performance Shaders**: Leverage MPS for additional optimisations
5. **Context Quantisation**: GPU-accelerated context computation
6. **Full Pipeline**: End-to-end encoding on GPU

## Troubleshooting

### Metal Not Available

**Problem**: `MetalAcceleratorError.metalNotAvailable`

**Solutions**:
- Verify running on macOS 10.13+ or iOS 11+
- Check that device has GPU (use `MTLCreateSystemDefaultDevice()`)
- For VMs or CI: Metal may not be available in virtualized environments

### Command Buffer Execution Failed

**Problem**: `MetalAcceleratorError.commandBufferExecutionFailed`

**Solutions**:
- Check GPU memory availability
- Reduce batch size if hitting memory limits
- Verify shader compilation succeeded
- Check system console for GPU errors

### Performance Not Improving

**Problem**: GPU slower than CPU

**Possible causes**:
- Batch size too small (< 1024 pixels) - GPU overhead dominates
- System under heavy GPU load
- Thermal throttling on mobile devices
- Data transfer overhead for repeated small operations

**Solutions**:
- Increase batch size (process larger tiles)
- Batch multiple operations together
- Profile with Instruments to identify bottlenecks
- Consider CPU-only mode for small images

## References

- **Metal Programming Guide**: https://developer.apple.com/metal/
- **Metal Shading Language Specification**: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
- **JPEG-LS Standard**: ISO/IEC 14495-1:1999 / ITU-T.87
- **Apple Silicon Performance**: https://developer.apple.com/documentation/apple-silicon

## Contributing

When contributing to Metal GPU acceleration:

1. Ensure bit-exact results match CPU implementations
2. Add comprehensive tests for new operations
3. Profile performance on various image sizes
4. Update documentation with benchmarks
5. Test on both Intel and Apple Silicon Macs
6. Verify conditional compilation works on non-Apple platforms
