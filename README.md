# JLSwift

A native Swift implementation of **JPEG-LS** (ISO/IEC 14495-1:1999 / ITU-T.87) compression for DICOM medical imaging. Optimized for Apple Silicon with hardware acceleration support.

[![CI](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml)

## Overview

JLSwift provides a native Swift JPEG-LS compression library designed for the DICOMkit project and optimized for medical imaging workflows. The library emphasizes:

- **Type Safety**: Leverages Swift 6.2+ strict concurrency and type system
- **Performance**: Optimized implementations with support for hardware acceleration
- **Reliability**: Comprehensive test coverage exceeding 95% for all modules
- **DICOM Compatible**: Full support for DICOM transfer syntaxes

### Library Modules

| Module | Description |
|--------|-------------|
| **JPEGLS** | Native Swift JPEG-LS compression for medical imaging (DICOM compatible) |
| **jpegls** | Command-line tool for JPEG-LS encoding and decoding |

## Requirements

- **Swift 6.2** or later
- **Platforms**: Linux, macOS 12+ (Monterey), iOS 15+
- **Primary Target**: Apple Silicon (M1/M2/M3) with ARM64 optimizations

## Installation

Add JLSwift as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
]
```

Then add JPEGLS as a dependency of your target:

```swift
// For JPEG-LS compression functionality
.target(name: "YourTarget", dependencies: ["JPEGLS"])
```

## JPEGLS Module

**JPEGLS** is a native Swift implementation of JPEG-LS (ISO/IEC 14495-1:1999 / ITU-T.87) compression, designed for the DICOMkit project and optimized for medical imaging workflows.

### What is JPEG-LS?

JPEG-LS is a lossless/near-lossless compression standard specifically designed for continuous-tone images. It's widely used in medical imaging (DICOM) due to its excellent compression ratio while maintaining image fidelity—critical for diagnostic accuracy.

### Current Implementation Status

| Phase | Component | Status | Coverage |
|-------|-----------|--------|----------|
| 2.2 | Core Types & Bitstream | ✅ Complete | 96.24% |
| 2.3 | Context Modeling | ✅ Complete | 96.91% |
| 3.1 | Regular Mode Encoding | ✅ Complete | 100.00% |
| 3.2 | Run Mode Encoding | ✅ Complete | 100.00% |
| 3.3 | Near-Lossless Encoding | ✅ Complete | 100.00% |
| 3.4 | Multi-Component Encoding | ✅ Complete | 100.00% |
| 4.1 | Bitstream Parsing | ✅ Complete | 100.00% |
| 4.2 | Regular Mode Decoding | ✅ Complete | 96.90% |
| 4.3 | Run Mode Decoding | ✅ Complete | 100.00% |
| 4.4 | Multi-Component Decoding | ✅ Complete | 92.10% |
| 5.1 | ARM NEON / SIMD Optimization | ✅ Complete | 100.00% |
| 5.2 | Apple Accelerate Integration | ✅ Complete | 100.00% |
| 5.4 | Memory Optimization | ✅ Complete | 100.00% |

**Overall Project Coverage: >95%**

### Key Features

| Feature | Description |
|---------|-------------|
| **Native Swift** | Pure Swift implementation with no external C dependencies |
| **Apple Silicon Optimized** | ARM NEON/SIMD acceleration with Swift SIMD4 types |
| **Hardware Acceleration** | Apple Accelerate framework (vDSP) for batch operations & statistics |
| **Memory Optimized** | Buffer pooling, tile-based processing, and cache-friendly data layouts |
| **DICOM Compatible** | Full support for DICOM transfer syntaxes |
| **Multi-Component Support** | Full RGB and grayscale encoding with all interleaving modes |
| **Interleaving Modes** | None (separate scans), Line-interleaved, Sample-interleaved |
| **Near-Lossless Support** | Configurable error tolerance encoding with NEAR parameter (1-255) |
| **Command-Line Tool** | `jpegls` CLI for encoding, decoding, and validation (planned) |

### Architecture Overview

```
JPEGLS/
├── Core/                    # Core codec types and protocols
│   ├── JPEGLSMarker         # JPEG-LS marker segment types
│   ├── JPEGLSFrameHeader    # Frame header structures (ITU-T.87)
│   ├── JPEGLSScanHeader     # Scan header structures
│   ├── JPEGLSPresetParameters # Preset parameters (MAXVAL, T1-T3, RESET)
│   ├── JPEGLSContextModel   # Context state management (365 contexts)
│   ├── JPEGLSBitstreamReader/Writer # Bitstream I/O utilities
│   └── JPEGLSError          # Comprehensive error handling
├── Decoder/                 # Decoding implementation
│   ├── JPEGLSParser         # JPEG-LS file format parser
│   ├── RegularModeDecoder   # Gradient-based decoding (MED prediction)
│   ├── RunModeDecoder       # Run-length decoding for flat regions
│   └── MultiComponentDecoder # Multi-component deinterleaving & color transform
├── Encoder/                 # Encoding implementation
│   ├── RegularModeEncoder   # Gradient-based encoding (MED prediction)
│   ├── RunModeEncoder       # Run-length encoding for flat regions
│   ├── NearLosslessEncoder  # Near-lossless encoding with NEAR parameter
│   ├── MultiComponentEncoder # Multi-component & interleaving orchestration
│   └── PixelBuffer          # Component-aware pixel access with neighbors
├── Platform/                # Platform-specific optimizations
│   ├── Accelerate/          # Apple Accelerate framework (vDSP batch operations)
│   ├── ARM64/               # Apple Silicon / ARM NEON code
│   └── x86_64/              # x86-64 specific code (removable)
└── PlatformProtocols        # Protocol-based platform abstraction
```

### Memory Optimization Features

JLSwift includes comprehensive memory optimization features for handling large medical images:

#### Buffer Pooling (`JPEGLSBufferPool`)
- Thread-safe buffer reuse to reduce allocation overhead
- Supports multiple buffer types (context arrays, pixel data, bitstream)
- Automatic cleanup of expired buffers
- Shared global pool available via `sharedBufferPool`

#### Tile-Based Processing (`JPEGLSTileProcessor`)
- Divides large images into manageable tiles
- Configurable tile size and overlap for boundary handling
- Memory savings estimation for large images
- Enables processing of images larger than available memory

#### Cache-Friendly Data Layout (`JPEGLSCacheFriendlyBuffer`)
- Contiguous memory layout in row-major order
- Optimized neighbor access patterns for CPU cache efficiency
- Batch row access for vectorized operations
- Compatible with existing encoder/decoder interfaces

**Example Usage:**
```swift
// Create a tile processor for a large image
let processor = JPEGLSTileProcessor(
    imageWidth: 8192,
    imageHeight: 8192,
    configuration: TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 4)
)

// Calculate tiles with overlap for boundary handling
let tiles = processor.calculateTilesWithOverlap()

// Estimate memory savings
let savings = processor.estimateMemorySavings(bytesPerPixel: 2)
print("Memory reduction: \(savings * 100)%")

// Use buffer pooling for context arrays
let contextBuffer = sharedBufferPool.acquire(type: .contextArrays, size: 365)
defer { sharedBufferPool.release(contextBuffer, type: .contextArrays) }
```

### Design Principles

1. **Platform Abstraction**: All platform-specific code behind protocols for clean separation
2. **Testability**: Every component designed for unit testing with >95% coverage
3. **Performance First**: Optimized for Apple Silicon while maintaining correctness
4. **x86-64 Removability**: Clear compilation boundaries for future x86-64 deprecation
5. **Memory Efficiency**: Buffer pooling, tile-based processing, and cache-friendly layouts for large images
6. **Standards Compliance**: Strict adherence to ISO/IEC 14495-1:1999 / ITU-T.87

### Supported DICOM Transfer Syntaxes (Planned)

| Transfer Syntax UID | Description |
|--------------------|-------------|
| 1.2.840.10008.1.2.4.80 | JPEG-LS Lossless Image Compression |
| 1.2.840.10008.1.2.4.81 | JPEG-LS Lossy (Near-Lossless) Image Compression |

See [MILESTONES.md](MILESTONES.md) for the detailed development roadmap.

## Building & Testing

### Build Commands

```bash
# Build all targets
swift build

# Build in release mode
swift build -c release

# Build a specific target
swift build --target JPEGLS
swift build --target jpegls
```

### Test Commands

```bash
# Run all tests
swift test

# Run tests with code coverage
swift test --enable-code-coverage

# Run tests for a specific target
swift test --filter JPEGLSTests

# View coverage report JSON path
swift test --show-codecov-path
```

### Code Coverage Requirement

> **Important**: This project requires **>95% test code coverage**. The CI pipeline enforces this threshold on every push and pull request. PRs that drop coverage below 95% will fail the CI check.

## Project Structure

```
JLSwift/
├── Package.swift              # Swift Package Manager manifest (Swift 6.2+)
├── Sources/
│   ├── JPEGLS/                # JPEG-LS compression library
│   │   ├── Core/              # Core types and protocols
│   │   ├── Decoder/           # Decoding implementation
│   │   ├── Encoder/           # Encoding implementation
│   │   ├── Platform/          # Platform-specific code
│   │   └── JPEGLS.swift       # Module exports
│   └── jpegls/                # Command-line tool
├── Tests/
│   └── JPEGLSTests/           # JPEGLS unit tests
├── .github/
│   ├── copilot-instructions.md # Coding guidelines
│   └── workflows/
│       └── ci.yml             # CI pipeline configuration
├── README.md                  # This file
└── MILESTONES.md              # Project roadmap
```

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Project overview and usage guide (this file) |
| [MILESTONES.md](MILESTONES.md) | Project milestones and development roadmap |
| [Copilot Instructions](.github/copilot-instructions.md) | Coding guidelines for contributors |

### API Documentation

All public types and methods include documentation comments following Swift API Design Guidelines. Use Xcode's Quick Help or generate documentation using DocC:

```bash
# Generate documentation (requires Xcode)
swift package generate-documentation
```

## Contributing

When contributing to JLSwift, please follow these guidelines:

1. **Code Style**: Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
2. **Testing**: All public APIs must have corresponding unit tests with >95% coverage
3. **Documentation**: All public types and methods must have documentation comments
4. **Documentation Updates**: Update README.md and MILESTONES.md when features or APIs change

### Pull Request Checklist

- [ ] All tests pass (`swift test`)
- [ ] Test coverage is above 95%
- [ ] README.md is updated if features or APIs changed
- [ ] MILESTONES.md is updated if milestone progress changed
- [ ] All public APIs have documentation comments
- [ ] Code follows Swift 6.2+ best practices

## License

This project is available under the terms specified by the repository owner.