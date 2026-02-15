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
- **Secondary Target**: x86-64 (Intel Macs, Linux) with SSE/AVX optimizations

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
| 7.3 | CLI Argument Parsing Tests | ✅ Complete | N/A* |

**Overall Project Coverage: 96.08%** (exceeds 95% threshold)

*CLI executable target not included in coverage metrics (Swift Package Manager limitation), but validation logic thoroughly tested with 60 comprehensive tests.

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
| **Command-Line Tool** | `jpegls` CLI with info, verify, encode, and decode commands |

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

## Command-Line Tool

The `jpegls` command-line tool provides easy access to JPEG-LS encoding, decoding, and file inspection.

### Installation

Build the CLI tool with:
```bash
swift build -c release
```

The binary will be available at `.build/release/jpegls`.

### Commands

#### `jpegls info` - Display File Information

Display detailed information about a JPEG-LS file:

```bash
# Human-readable output
jpegls info image.jls

# JSON output for programmatic use
jpegls info image.jls --json

# Quiet mode - minimal output (single line)
jpegls info image.jls --quiet
```

**Example output:**
```
JPEG-LS File Information
========================

File size: 30 bytes

Frame Header:
  Width: 256 pixels
  Height: 256 pixels
  Bits per sample: 8
  Component count: 1

Scan Headers: 1
  Scan 1:
    Component count: 1
    Component IDs: 1
    Interleave mode: none
    NEAR: 0 (lossless)
    Point transform: 0

Compression:
  Uncompressed size: 65536 bytes
  Compressed size: 30 bytes
  Compression ratio: 2184.53:1
  Space savings: 100.0%
```

**Quiet mode output:**
```
256x256 8-bit 1-component lossless
```

#### `jpegls verify` - Verify File Integrity

Validate JPEG-LS file structure and parameters:

```bash
# Basic verification
jpegls verify image.jls

# Verbose output with detailed validation
jpegls verify image.jls --verbose

# Quiet mode - no output on success (exit code 0)
jpegls verify image.jls --quiet
```

The verify command checks:
- File structure validity (SOI, SOF, SOS, EOI markers)
- Frame header parameters (dimensions, bits per sample, component count)
- Scan header consistency with frame header
- Preset parameter validity and threshold ordering
- Component ID consistency

#### `jpegls encode` - Encode Raw Image Data (Planned)

Encode raw pixel data to JPEG-LS format:

```bash
# Encode grayscale image (lossless)
jpegls encode input.raw output.jls --width 512 --height 512 --bits-per-sample 8

# Encode RGB image with line interleaving
jpegls encode input.raw output.jls \
  --width 512 --height 512 \
  --components 3 \
  --interleave line

# Near-lossless encoding (NEAR=3)
jpegls encode input.raw output.jls \
  --width 512 --height 512 \
  --near 3 \
  --verbose

# Quiet mode - suppress non-essential output
jpegls encode input.raw output.jls \
  --width 512 --height 512 \
  --quiet
```

**Options:**
- `-w, --width`: Image width in pixels (required)
- `-h, --height`: Image height in pixels (required)
- `-b, --bits-per-sample`: Bits per sample, 2-16 (default: 8)
- `-c, --components`: Number of components - 1 (grayscale) or 3 (RGB) (default: 1)
- `--near`: NEAR parameter, 0=lossless, 1-255=lossy (default: 0)
- `--interleave`: Interleave mode - none, line, sample (default: none)
- `--color-transform`: Color transformation - none, hp1, hp2, hp3 (default: none)
- `--verbose`: Enable verbose output
- `--quiet`: Suppress non-essential output

#### `jpegls decode` - Decode JPEG-LS File (Planned)

Decode JPEG-LS file to raw pixel data:

```bash
# Decode to raw format
jpegls decode input.jls output.raw

# Decode with verbose output
jpegls decode input.jls output.raw --verbose

# Quiet mode - suppress non-essential output
jpegls decode input.jls output.raw --quiet
```

**Options:**
- `--format`: Output format - raw, png, tiff (default: raw) *(PNG/TIFF support planned)*
- `--verbose`: Enable verbose output
- `--quiet`: Suppress non-essential output

**Note:** Full encode and decode functionality requires bitstream I/O integration, which is currently in development. The `info` and `verify` commands are fully functional.

#### `jpegls batch` - Batch Process Multiple Files

Process multiple JPEG-LS files in parallel with encode, decode, info, or verify operations:

```bash
# Get info for all .jls files in a directory
jpegls batch info "images/*.jls"

# Verify all JPEG-LS files in a directory with verbose output
jpegls batch verify "/path/to/images/*.jls" --verbose

# Get info for all files with quiet mode (no output, exit code indicates success)
jpegls batch info "*.jls" --quiet

# Process with custom parallelism (default is CPU count)
jpegls batch verify "*.jls" --parallelism 2

# Batch encode (when encode is fully implemented)
jpegls batch encode "*.raw" \
  --output-dir encoded/ \
  --width 512 --height 512 \
  --verbose

# Stop on first error instead of continuing
jpegls batch info "*.jls" --fail-fast
```

**Features:**
- **Glob patterns**: Match files with wildcards (`*.jls`, `images/*.raw`)
- **Directory scanning**: Process all files in a directory
- **Parallel processing**: Concurrent processing with configurable parallelism
- **Progress reporting**: Real-time progress with verbose mode
- **Error handling**: Continue on errors or stop with `--fail-fast`
- **Operations**: Supports info, verify, encode, and decode

**Options:**
- `<operation>`: Operation to perform (encode, decode, info, verify)
- `<input-pattern>`: Glob pattern or directory path
- `-o, --output-dir`: Output directory (required for encode/decode)
- `-p, --parallelism`: Max parallel operations (default: CPU count)
- `-v, --verbose`: Show detailed progress for each file
- `-q, --quiet`: Suppress all output except errors
- `--fail-fast`: Stop on first error

#### `jpegls completion` - Generate Shell Completions

Generate shell completion scripts for bash, zsh, or fish:

```bash
# Generate bash completion
jpegls completion bash > jpegls-completion.bash

# Generate zsh completion
jpegls completion zsh > _jpegls

# Generate fish completion
jpegls completion fish > jpegls.fish
```

**Installation:**

**Bash:**
```bash
# System-wide installation
sudo jpegls completion bash > /etc/bash_completion.d/jpegls

# User installation
jpegls completion bash > ~/.local/share/bash-completion/completions/jpegls
```

**Zsh:**
```bash
# System-wide installation
sudo jpegls completion zsh > /usr/local/share/zsh/site-functions/_jpegls

# User installation
mkdir -p ~/.zfunc
jpegls completion zsh > ~/.zfunc/_jpegls
# Add to ~/.zshrc: fpath=(~/.zfunc $fpath)
```

**Fish:**
```bash
# User installation
mkdir -p ~/.config/fish/completions
jpegls completion fish > ~/.config/fish/completions/jpegls.fish
```

After installation, restart your shell or source the completion file to enable tab completion for all jpegls commands and options.

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
| [X86_64_REMOVAL_GUIDE.md](X86_64_REMOVAL_GUIDE.md) | Step-by-step guide for removing x86-64 support |
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