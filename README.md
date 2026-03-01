# JLSwift

A native Swift implementation of **JPEG-LS** (ISO/IEC 14495-1:1999 / ITU-T.87) compression. Usable as a standalone general-purpose codec and optimised for Apple Silicon with hardware acceleration support. Fully compatible with DICOM medical imaging workflows.

[![CI](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml)

## Overview

JLSwift is a pure Swift JPEG-LS compression library with no DICOM dependencies. It can be used in any project that requires lossless or near-lossless image compression — no DICOM knowledge is needed. The library is also designed for seamless integration with DICOMkit and other medical-imaging frameworks. Key attributes:

- **Type Safety**: Leverages Swift 6.2+ concurrency and type system
- **Performance**: Optimised implementations with support for hardware acceleration
- **Reliability**: Comprehensive test coverage exceeding 95% for all modules
- **DICOM Aware, DICOM Independent**: Full support for DICOM transfer syntaxes; no DICOM runtime dependency

### Library Modules

| Module | Description |
|--------|-------------|
| **JPEGLS** | Native Swift JPEG-LS compression for medical imaging (DICOM compatible) |
| **jpegls** | Command-line tool for JPEG-LS encoding and decoding |

## Requirements

- **Swift 6.2** or later
- **Platforms**: Linux, macOS 12+ (Monterey), iOS 15+
- **Primary Target**: Apple Silicon (M1/M2/M3) with ARM64 optimisations
- **Secondary Target**: x86-64 (Intel Macs, Linux) with SSE/AVX optimisations

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

**JPEGLS** is a native Swift implementation of JPEG-LS (ISO/IEC 14495-1:1999 / ITU-T.87) compression, designed for the DICOMkit project and optimised for medical imaging workflows.

### What is JPEG-LS?

JPEG-LS is a lossless/near-lossless compression standard specifically designed for continuous-tone images. It's widely used in medical imaging (DICOM) due to its excellent compression ratio while maintaining image fidelity—critical for diagnostic accuracy.

### Current Implementation Status

| Phase | Component | Status | Coverage |
|-------|-----------|--------|----------|
| 2.2 | Core Types & Bitstream | ✅ Complete | 96.24% |
| 2.3 | Context Modelling | ✅ Complete | 96.91% |
| 3.1 | Regular Mode Encoding | ✅ Complete | 100.00% |
| 3.2 | Run Mode Encoding | ✅ Complete | 100.00% |
| 3.3 | Near-Lossless Encoding | ✅ Complete | 100.00% |
| 3.4 | Multi-Component Encoding | ✅ Complete | 100.00% |
| 4.1 | Bitstream Parsing | ✅ Complete | 100.00% |
| 4.2 | Regular Mode Decoding | ✅ Complete | 96.90% |
| 4.3 | Run Mode Decoding | ✅ Complete | 100.00% |
| 4.4 | Multi-Component Decoding | ✅ Complete | 92.10% |
| 5.1 | ARM NEON / SIMD Optimisation | ✅ Complete | 100.00% |
| 5.2 | Apple Accelerate Integration | ✅ Complete | 100.00% |
| 5.3 | Metal GPU Acceleration | ✅ Complete | 100.00% |
| 5.4 | Memory Optimisation | ✅ Complete | 100.00% |
| 7.3 | CLI Argument Parsing Tests | ✅ Complete | N/A* |
| 8.1 | CharLS Reference Integration | ⏳ In Progress | 100.00% |
| 8.4 | Edge Cases & Robustness | ✅ Complete | 100.00% |
| 11.2 | Mapping Table (Palette) Support | ✅ Complete | 100.00% |
| 11.3 | Extended Dimensions (LSE Type 4) | ✅ Complete | 100.00% |
| 11.4 | Additional Part 2 Colour Transforms | ✅ Complete | 100.00% |
| 11.5 | Part 2 Performance Regression Tests | ✅ Complete | 100.00% |
| 12.1 | CharLS Decode Interoperability | ⏳ In Progress | — |
| 12.2 | CharLS Encode Interoperability | ✅ Complete | 100.00% |
| 12.3 | Round-Trip Interoperability (JLSwift) | ⏳ In Progress | 100.00% |
| 13.1 | ARM Neon Optimisation Audit & Enhancement | ✅ Complete | 100.00% |
| 13.2 | Accelerate Framework Deep Integration | ✅ Complete | 100.00% |
| 13.3 | Apple Silicon Memory Architecture Optimisation | ✅ Complete | 100.00% |

**Overall Project Coverage: 95.80%** (exceeds 95% threshold)

**Recent conformance fixes** (PRs #74, #75, #76, and current): Gradient quantisation, context update/bias correction, error correction XOR, LIMIT computation, default thresholds, run interruption coding overhaul, encoder RUNindex reset, error mapping formula, near-lossless boundary condition, **run-interruption adjustedLimit mismatch** (encoder now uses J[finalRunIndex] matching the decoder), and **near-lossless reconstructed-value tracking** for line-interleaved and sample-interleaved modes — all aligned with ITU-T.87 and CharLS reference implementation.

*CLI executable target not included in coverage metrics (Swift Package Manager limitation), but validation logic thoroughly tested with 60 comprehensive tests.

**Note**: Coverage may vary slightly by platform due to conditional compilation of platform-specific optimisations (ARM64, Accelerate framework). The reported coverage is measured on Linux x86_64.

### Key Features

| Feature | Description |
|---------|-------------|
| **Native Swift** | Pure Swift implementation with no external C dependencies |
| **Swift 6.2 Concurrency** | Explicit `.swiftLanguageMode(.v6)` in Package.swift; all shared types are `Sendable`; batch processing uses `withTaskGroup` structured concurrency |
| **Apple Silicon Optimised** | ARM NEON/SIMD acceleration using Swift SIMD types: SIMD8 run-length detection, SIMD8 byte-stuffing scan, and CLZ-based Golomb-Rice parameter computation |
| **Intel x86-64 Optimised** | SSE/AVX SIMD acceleration: SIMD8 run-length detection, SIMD8 byte-stuffing scan, BSR/LZCNT-based Golomb-Rice parameter computation, Intel-tuned cache parameters, and tile-size optimisation |
| **Hardware Acceleration** | Apple Accelerate framework (vDSP) for batch gradient computation, absolute prediction-error accumulation, context-state updates, vImage planar↔interleaved conversion, and vectorised HP1/HP2/HP3 colour transforms |
| **Metal GPU Acceleration** | Optional GPU acceleration for large images (macOS 10.13+, iOS 11+) |
| **Memory Optimised** | Cache-line–aligned context arrays, L1-cache–tuned tile sizes, `UnifiedMemoryBufferPool` for Apple Silicon unified memory, memory-mapped I/O via `mmap`, and prefetch hints for sequential access patterns |
| **DICOM Compatible** | Full support for DICOM transfer syntaxes |
| **Multi-Component Support** | Full RGB and greyscale encoding with all interleaving modes |
| **Interleaving Modes** | None (separate scans), Line-interleaved, Sample-interleaved |
| **Near-Lossless Support** | Configurable error tolerance encoding with NEAR parameter (1-255), with correct error quantisation per §4.2.2 and reconstructed-value tracking |
| **ITU-T.87 Compliant** | Standard-conformant context index formula (365 contexts), A initialisation, sign-adjusted Golomb-Rice coding, bias correction per §4.3.3, run-mode RUNindex synchronisation, near-lossless quantisation/dequantisation, EOL terminator handling, gradient quantisation per Table A.7, error correction XOR per §A.4.1, dual-context run interruption coding per §A.7, and correct LIMIT/threshold computations |
| **Mapping Table (Palette) Support** | LSE type 2/3 mapping tables parsed and applied per ITU-T.87 §5.1.1.3; scan header `Tdi` field used to reference tables per component; encoder can emit mapping table LSE segments |
| **Extended Dimensions (LSE Type 4)** | Images with width or height > 65535 are fully supported via LSE type 4 per ITU-T.87 §5.1.1.4; encoder auto-emits the segment and writes 0 in SOF for extended fields; parser restores the true dimensions |
| **Part 2 Colour Transforms** | HP1, HP2, HP3 colour transforms with modular arithmetic; APP8 "mrfx" marker written by encoder and read by decoder; round-trip verified for all transforms and interleave modes |
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
│   ├── JPEGLSMappingTable   # Mapping table (palette) support per §5.1.1.3
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
│       ├── X86_64Accelerator       # SSE/AVX SIMD accelerator
│       └── IntelMemoryOptimizer    # Intel cache/memory optimisation
└── PlatformProtocols        # Protocol-based platform abstraction
```

### Memory Optimisation Features

JLSwift includes comprehensive memory optimisation features for handling large medical images:

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
- Optimised neighbour access patterns for CPU cache efficiency
- Batch row access for vectorised operations
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
3. **Performance First**: Optimised for Apple Silicon while maintaining correctness
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

#### `jpegls encode` - Encode Image Data

Encode raw pixel data, PGM/PPM, PNG, or TIFF images to JPEG-LS format:

```bash
# Encode a PGM file (dimensions/components auto-detected from header)
jpegls encode input.pgm output.jls

# Encode a PNG file (dimensions/bit depth auto-detected)
jpegls encode input.png output.jls

# Encode a TIFF file
jpegls encode input.tiff output.jls

# Encode a PPM file with sample interleaving
jpegls encode input.ppm output.jls --interleave sample

# Near-lossless encoding from a PGM file
jpegls encode input.pgm output.jls --near 3 --verbose

# Encode raw pixel data (width and height required for raw input)
jpegls encode input.raw output.jls --width 512 --height 512 --bits-per-sample 8

# Encode RGB raw data with line interleaving
jpegls encode input.raw output.jls \
  --width 512 --height 512 \
  --components 3 \
  --interleave line

# Quiet mode - suppress non-essential output
jpegls encode input.pgm output.jls --quiet
```

**Options:**
- `-w, --width`: Image width in pixels (required for raw input; auto-detected from PGM/PPM/PNG/TIFF)
- `-h, --height`: Image height in pixels (required for raw input; auto-detected from PGM/PPM/PNG/TIFF)
- `-b, --bits-per-sample`: Bits per sample, 2-16 (default: 8; auto-detected from PGM/PPM MAXVAL or PNG/TIFF bit depth)
- `-c, --components`: Number of components - 1 (greyscale) or 3 (RGB) (default: 1; auto-detected from PGM/PPM/PNG/TIFF)
- `--near`: NEAR parameter, 0=lossless, 1-255=lossy (default: 0)
- `--interleave`: Interleave mode - none, line, sample (default: none)
- `--color-transform` / `--colour-transform`: Colour transformation - none, hp1, hp2, hp3 (default: none)
- `--t1`, `--t2`, `--t3`, `--reset`: Custom preset parameters (T1, T2, T3, RESET); all four must be supplied together
- `--optimise` / `--optimize`: Embed computed default preset parameters explicitly in the bitstream (self-contained output)
- `--verbose`: Enable verbose output
- `--quiet`: Suppress non-essential output
- `--no-colour` / `--no-color`: Disable ANSI colour codes in terminal output

**Supported input formats:** raw pixel data, PGM (P5 binary), PPM (P6 binary), PNG (uncompressed stored-DEFLATE), TIFF (uncompressed baseline)

#### `jpegls decode` - Decode JPEG-LS File

Decode JPEG-LS file to raw pixel data or PGM/PPM image:

```bash
# Decode to raw format (default)
jpegls decode input.jls output.raw

# Decode to PGM (grayscale) or PPM (colour) format
jpegls decode input.jls output.pgm --format pgm
jpegls decode input.jls output.ppm --format ppm

# Decode with verbose output
jpegls decode input.jls output.pgm --format pgm --verbose

# Quiet mode - suppress non-essential output
jpegls decode input.jls output.pgm --format pgm --quiet
```

**Options:**
- `--format`: Output format - raw, pgm, ppm, png, tiff (default: raw)
- `--verbose`: Enable verbose output
- `--quiet`: Suppress non-essential output
- `--no-colour` / `--no-color`: Disable ANSI colour codes in terminal output

**Supported output formats:** raw pixel data, PGM (P5 binary), PPM (P6 binary), PNG (uncompressed stored-DEFLATE), TIFF (uncompressed baseline)

**Note:** All four commands (`encode`, `decode`, `info`, `verify`) are fully functional. Lossless decoding supports 8-bit and 16-bit images in all interleaving modes (none, line, sample). The `encode` command accepts PGM/PPM/PNG/TIFF files directly with auto-detected parameters, and the `decode` command can output PGM/PPM/PNG/TIFF files.

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
- `--summarise` / `--summarize`: Print a summary table after processing (even in quiet mode)
- `--no-colour` / `--no-color`: Disable ANSI colour codes in terminal output

#### `jpegls compare` - Compare Two Image Files

Compare two image files (JPEG-LS, PGM/PPM, PNG, or TIFF) pixel-by-pixel:

```bash
# Exact comparison of two JPEG-LS files (exit 0 = identical)
jpegls compare reference.jls output.jls

# Near-lossless comparison with NEAR=3 tolerance
jpegls compare original.jls encoded.jls --near 3

# Compare JPEG-LS against PGM reference image
jpegls compare reference.pgm decoded.jls --verbose

# Compare JPEG-LS against PNG or TIFF reference
jpegls compare reference.png decoded.jls
jpegls compare reference.tiff decoded.jls

# JSON output for scripted pipelines
jpegls compare a.jls b.jls --json

# Quiet mode — use exit code only
jpegls compare a.jls b.jls --quiet && echo "match"
```

**Options:**
- `--near N`: Maximum per-pixel error tolerance (default: 0 for exact match)
- `--json`: Output comparison statistics as JSON
- `--verbose` / `-v`: Show image dimensions before comparing
- `--quiet` / `-q`: Suppress output; use exit code only
- `--no-colour` / `--no-color`: Disable ANSI colour codes

**Exit codes:**
- `0`: All samples are within `--near` tolerance (images match)
- `1`: One or more samples exceed tolerance, or an error occurred

**Statistics reported:** max error, mean absolute error, mismatch sample count.

**Supported input formats:** JPEG-LS (`.jls`), PGM (`.pgm`), PPM (`.ppm`), PNG (`.png`), TIFF (`.tiff`/`.tif`)

#### `jpegls convert` - Convert Between Image Formats

Convert an image from one format to another:

```bash
# Convert JPEG-LS to PNG
jpegls convert image.jls image.png

# Convert JPEG-LS to TIFF
jpegls convert image.jls image.tiff

# Convert PNG to JPEG-LS (lossless)
jpegls convert image.png image.jls

# Convert TIFF to JPEG-LS with near-lossless encoding
jpegls convert image.tiff image.jls --near 3

# Convert PGM to PNG
jpegls convert image.pgm image.png

# Convert with colour transformation
jpegls convert rgb.png rgb.jls --colour-transform hp1

# Convert JPEG-LS to PGM/PPM
jpegls convert image.jls image.pgm
jpegls convert image.jls image.ppm
```

**Options:**
- `--near N`: NEAR parameter for JPEG-LS output (0=lossless, 1-255=lossy; default: 0)
- `--interleave`: Interleave mode for JPEG-LS output — none, line, sample (default: none)
- `--color-transform` / `--colour-transform`: Colour transformation for JPEG-LS output — none, hp1, hp2, hp3 (default: none)
- `--t1`, `--t2`, `--t3`, `--reset`: Custom preset parameters for JPEG-LS output (all four required together)
- `--optimise` / `--optimize`: Embed computed preset parameters in JPEG-LS output bitstream
- `--verbose`: Enable verbose output
- `--quiet`: Suppress non-essential output
- `--no-colour` / `--no-color`: Disable ANSI colour codes in terminal output

**Supported input formats:** JPEG-LS (`.jls`), PNG (`.png`), TIFF (`.tiff`/`.tif`), PGM (`.pgm`), PPM (`.ppm`)

**Supported output formats:** JPEG-LS (`.jls`), PNG (`.png`), TIFF (`.tiff`/`.tif`), PGM (`.pgm`), PPM (`.ppm`), raw (any other extension)

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

#### `jpegls` - Man Page Documentation

Complete documentation for the `jpegls` command-line tool is available as a Unix manual page. The man page provides detailed information about all commands, options, and usage examples.

**Installation:**

```bash
# System-wide installation (requires sudo)
sudo cp jpegls.1 /usr/local/share/man/man1/
sudo mandb  # Update man page database (on Linux)

# User installation (no sudo required)
mkdir -p ~/.local/share/man/man1
cp jpegls.1 ~/.local/share/man/man1/
# Add to ~/.bashrc or ~/.zshrc: export MANPATH="$HOME/.local/share/man:$MANPATH"
```

**View the man page:**

```bash
# After installation
man jpegls

# Or view directly without installation
man ./jpegls.1
```

The man page includes:
- Command synopsis and descriptions
- Detailed option documentation
- Usage examples for all commands
- DICOM compatibility information
- Performance optimisation details
- Standards compliance (ISO/IEC 14495-1:1999 / ITU-T.87)

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

# Run CharLS conformance tests
swift test --filter CharLSConformanceTests

# Run performance benchmarks
swift test --filter JPEGLSPerformanceBenchmarks

# View coverage report JSON path
swift test --show-codecov-path
```

### Performance Benchmarking

JLSwift includes comprehensive performance benchmarks to measure encoding and decoding speed across various configurations. The benchmark suite includes:

**Test Configurations:**
- Image sizes: 256x256, 512x512, 1024x1024, 2048x2048, 4096x4096
- Bit depths: 8-bit, 12-bit, 16-bit
- Component counts: greyscale (1), RGB (3)
- Encoding modes: lossless (NEAR=0), near-lossless (NEAR=3, NEAR=10)
- Interleaving modes: none, line, sample
- Content types: flat, gradient, checkerboard, medical-like

**Run Benchmarks:**
```bash
# Run all performance benchmarks (may take several minutes)
swift test --filter JPEGLSPerformanceBenchmarks

# Run a specific benchmark
swift test --filter "benchmarkEncode512x512Grayscale8bit"

# Run performance regression tests
swift test --filter JPEGLSPerformanceRegressionTests

# Run CharLS comparison benchmarks (currently disabled, requires CharLS integration)
swift test --filter JPEGLSCharLSComparisonBenchmarks
```

**Sample Results (x86_64 Linux, scalar implementation):**
```
Encode 512x512 8-bit grayscale (lossless):
  Image:          512x512, 8-bit, 1 component(s)
  Iterations:     10
  Average time:   97.51 ms
  Min time:       95.80 ms
  Max time:       104.91 ms
  Throughput:     2.56 MB/s
  Throughput:     2.69 Mpixels/s
```

Performance will vary significantly based on hardware (Apple Silicon with ARM NEON vs x86_64) and image content characteristics.

### Performance Regression Testing

JLSwift includes automated performance regression tests that detect catastrophic performance regressions in CI. The `JPEGLSPerformanceRegressionTests` suite verifies:

- **Encoding time** stays within baseline thresholds (256x256, 512x512 greyscale; 512x512 16-bit; 512x512 RGB)
- **Decoding time** stays within baseline thresholds (256x256, 512x512 greyscale; 512x512 RGB)
- **Round-trip time** (encode + decode) stays within baseline threshold
- **Throughput** remains above minimum Mpixels/s baseline
- **Compression ratio** doesn't degrade below minimum threshold
- **Linear scaling** is maintained (512x512 time < 8x of 256x256 time)

Baselines are established from x86_64 Linux CI with a 10x regression multiplier to avoid flaky failures while still catching algorithmic regressions. Precise regression detection (e.g., 1.2x threshold) requires dedicated benchmark hardware.

### CharLS Comparison Benchmarks

Head-to-head performance comparison with [CharLS](https://github.com/team-charls/charls) (the reference C++ JPEG-LS implementation) is available as a test suite with disabled tests. The `JPEGLSCharLSComparisonBenchmarks` suite includes stubs for:

- **Encoding speed**: greyscale, RGB, near-lossless comparison
- **Decoding speed**: greyscale, RGB, near-lossless comparison
- **Memory usage**: encoding and decoding memory comparison

These tests are currently disabled pending CharLS C library integration. JLSwift measurement infrastructure is in place; CharLS wrapper functions will be added when the C library is available as a Swift Package Manager dependency.

### CharLS Conformance Testing

JLSwift includes comprehensive conformance testing using reference files from the [CharLS](https://github.com/team-charls/charls) project. The test suite validates:

- **File Structure**: SOI/EOI markers and basic JPEG-LS file format
- **CharLS Byte Stuffing**: Extended support for CharLS escape sequences (`FF 60-7F`) and scan boundary detection
- **Reference Images**: 12 JPEG-LS files covering various configurations:
  - 8-bit and 16-bit samples
  - Greyscale and RGB colour images
  - Lossless and near-lossless (NEAR=3) encoding
  - Different colour transformation modes
  - Sub-sampling and interleaving modes
  - Non-default parameters
- **Image Loading**: PGM (greyscale) and PPM (colour) reference image parsing
- **Bit-Exact Comparison**: All 12 non-sub-sampled + 2 sub-sampled reference files validated for bit-exact decoding
  - 10 non-sub-sampled comparison test cases all passing (8-bit colour modes 0/1/2, 12-bit greyscale, non-default parameters)
  - 2 sub-sampled comparison test cases passing (t8sse0.jls lossless, t8sse3.jls near=3)
  - Pixel-by-pixel validation per component (lossless: exact match; near-lossless: error ≤ NEAR)
  - Non-default parameter tests validated against test8bs2.pgm reference
  - Sub-sampled tests compare each component against its reference PGM (R 256×256, G 256×64, B 128×128)
  - Flat-region (run mode) and near-lossless round-trip encoding/decoding verified correct
- **Round-Trip Interoperability**: 33 JLSwift encode → decode → compare regression tests
  - All bit depths (8/12/16-bit), greyscale and RGB, all interleave modes
  - Colour transforms (HP1, HP2, HP3)
  - Medical imaging patterns (CT, MR, CR/DX, US, NM simulations)
  - Edge cases (1×1, boundary values, single-row/column, checkerboard)
- **Colour Transform Interoperability**: 14 encode → decode tests on 256×256 CharLS reference image
  - HP1, HP2, HP3 with all interleave modes (none, line, sample) — 9 lossless tests
  - HP1 (3 modes), HP2, HP3 near-lossless with NEAR=3 — 5 near-lossless tests
  - Near-lossless error verified in transformed domain per ITU-T T.870

The conformance tests are located in `Tests/JPEGLSTests/CharLSConformanceTests.swift` with reference fixtures in `Tests/JPEGLSTests/TestFixtures/`. These tests ensure compatibility with the JPEG-LS standard (ISO/IEC 14495-1:1999 / ITU-T.87) and provide a foundation for bit-exact comparison with CharLS output.

A full standards conformance matrix (`CONFORMANCE_MATRIX.md`) documents the mapping between every normative section of ITU-T.87 and its implementation in JLSwift, including all deviations found and fixed during Milestone 10 (Phases 10.1–10.4).

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
│       └── ci.yml             # CI pipeline (build → test with caching & concurrency)
├── README.md                  # This file
└── MILESTONES.md              # Project roadmap
```

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Project overview and usage guide (this file) |
| [GETTING_STARTED.md](GETTING_STARTED.md) | Quick start guide with examples and common patterns |
| [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) | Comprehensive real-world usage examples |
| [SWIFTUI_EXAMPLES.md](SWIFTUI_EXAMPLES.md) | SwiftUI integration guide with image loading examples |
| [APPKIT_EXAMPLES.md](APPKIT_EXAMPLES.md) | AppKit integration guide for macOS applications |
| [SERVER_SIDE_EXAMPLES.md](SERVER_SIDE_EXAMPLES.md) | Server-side Swift integration guide (Vapor, Hummingbird, NIO) |
| [DICOMKIT_INTEGRATION.md](DICOMKIT_INTEGRATION.md) | DICOMkit integration guide for DICOM imaging workflows |
| [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) | Performance optimisation and benchmarking guide |
| [METAL_GPU_ACCELERATION.md](METAL_GPU_ACCELERATION.md) | Metal GPU acceleration guide for large images |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and solutions |
| [VERSIONING.md](VERSIONING.md) | Semantic versioning strategy and release guidelines |
| [CHANGELOG.md](CHANGELOG.md) | Complete history of changes and releases |
| [MILESTONES.md](MILESTONES.md) | Project milestones and development roadmap |
| [X86_64_REMOVAL_GUIDE.md](X86_64_REMOVAL_GUIDE.md) | Step-by-step guide for removing x86-64 support |
| [Copilot Instructions](.github/copilot-instructions.md) | Coding guidelines for contributors |

### API Documentation

All public types and methods include comprehensive documentation comments following Swift API Design Guidelines. Use Xcode's Quick Help or generate documentation using DocC:

```bash
# Generate documentation (requires Xcode)
swift package generate-documentation
```

### User Guides

- **[Getting Started](GETTING_STARTED.md)**: Installation, quick start, and basic usage examples
- **[Performance Tuning](PERFORMANCE_TUNING.md)**: Hardware acceleration, memory optimisation, and profiling
- **[Troubleshooting](TROUBLESHOOTING.md)**: Solutions to common problems and debugging tips

## Contributing

When contributing to JLSwift, please follow these guidelines:

1. **Code Style**: Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
2. **Testing**: All public APIs must have corresponding unit tests with >95% coverage
3. **Documentation**: All public types and methods must have documentation comments
4. **Documentation Updates**: Update README.md and MILESTONES.md when features or APIs change
5. **British English**: All comments, documentation, help text, and error messages must use British English (e.g., colour, optimise, initialise, behaviour, organisation). Public API identifiers (type names, method names, property names) retain their original American spelling.

### Pull Request Checklist

- [ ] All tests pass (`swift test`)
- [ ] Test coverage is above 95%
- [ ] README.md is updated if features or APIs changed
- [ ] MILESTONES.md is updated if milestone progress changed
- [ ] All public APIs have documentation comments
- [ ] Code follows Swift 6.2+ best practices

## License

This project is available under the terms specified by the repository owner.