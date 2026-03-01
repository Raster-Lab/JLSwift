# Changelog

All notable changes to JLSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### DICOM Independence & Final Integration (Milestone 20)
- Non-DICOM usage examples in USAGE_EXAMPLES.md (general-purpose compression, web assets, archival storage)
- DICOM-aware/DICOM-independent architecture documented in README.md

### Fixed

#### DICOM Independence & Final Integration (Milestone 20)
- Fixed incorrect threshold values in `JPEGLSPresetParametersTests` for 8-bit and 12-bit images; test expectations now match the ITU-T.87 Table C.2 formula (8-bit: T1=3, T2=7, T3=21; 12-bit: T1=18, T2=67, T3=276)
- Fixed incorrect expected values in `JPEGLSNearLosslessTests` for reconstructed-value boundary tests; test inputs now avoid the ITU-T.87 modular-wrap threshold, correctly exercising the clamp-to-MAXVAL and clamp-to-zero paths

## [0.8.0] - In Progress

### Added

#### Validation & Conformance (Milestone 8)
- CharLS reference test fixtures (12 JPEG-LS files, 7 reference images)
- CharLS conformance test suite with 589 tests
- CharLS extension marker support (0xFF60-0xFF7F) in parser
- TestFixtureLoader utility for PGM/PPM format parsing
- Comprehensive performance benchmark suite (18 benchmarks)
- Performance timing framework with throughput calculation (MB/s, Mpixels/s)
- Cross-platform memory tracking (macOS/iOS)
- Benchmarks for various image sizes (256x256 to 4096x4096)
- Benchmarks for various bit depths (8-bit, 12-bit, 16-bit)
- Benchmarks for various component counts (greyscale, RGB)
- Near-lossless benchmarks (NEAR=3, NEAR=10)
- Interleaving mode benchmarks (none, line, sample)
- Content-type-specific benchmarks (flat, gradient, medical-like)
- Comprehensive edge case test suite (EdgeCasesTests.swift) with 38 tests
- Boundary condition tests (MAXVAL, NEAR, dimensions)
- Invalid parameter combination tests
- Memory pressure scenario tests

#### Documentation (Milestone 9)
- Comprehensive DocC documentation for all public APIs
- GETTING_STARTED.md guide with installation and quick start examples
- PERFORMANCE_TUNING.md guide covering hardware acceleration and optimisation
- TROUBLESHOOTING.md guide with solutions for common issues
- USAGE_EXAMPLES.md with 25+ real-world standalone examples
- SWIFTUI_EXAMPLES.md with SwiftUI integration patterns for iOS/macOS
- APPKIT_EXAMPLES.md with AppKit integration patterns for macOS
- Man page documentation (jpegls.1) in groff format
- Man page installation instructions in README

### Changed
- Overall project test coverage measured at 95.80% on Linux x86_64 (exceeds 95% threshold)
- Coverage varies by platform due to conditional compilation of platform-specific optimisations
- README.md updated with accurate coverage measurements and platform notes
- README.md updated with links to new documentation guides
- MILESTONES.md updated to reflect progress on Milestone 8 and 9

### Fixed
- Parser now handles CharLS-encoded files with extension markers
- All 12 CharLS reference files can be parsed without errors

## [0.7.0] - Completed

### Added

#### Command-Line Interface (Milestone 7)
- `jpegls info` command for displaying file information
  - Human-readable output format
  - JSON output format with `--json` flag
  - Quiet mode with `--quiet` flag (single line output)
  - Displays frame header (dimensions, bits per sample, components)
  - Displays scan headers (interleave mode, NEAR parameter)
  - Displays preset parameters if present
  - Calculates compression statistics
- `jpegls verify` command for file integrity validation
  - Validates file structure (SOI, SOF, SOS, EOI markers)
  - Validates frame header parameters
  - Validates scan header consistency
  - Validates preset parameters
  - Verbose mode with `--verbose` flag
  - Quiet mode with `--quiet` flag (no output on success)
- `jpegls encode` command (argument parsing complete, bitstream I/O pending)
  - Input/output file path specification
  - `--width`, `--height` dimension parameters
  - `--bits-per-sample` parameter (2-16 bits)
  - `--components` parameter (1 or 3)
  - `--near` parameter for near-lossless encoding (0-255)
  - `--interleave` mode selection (none, line, sample)
  - `--color-transform` selection (none, hp1, hp2, hp3)
  - `--preset` parameter parsing (T1, T2, T3, RESET)
  - `--verbose` and `--quiet` output modes
- `jpegls decode` command (argument parsing complete, bitstream I/O pending)
  - Input/output file path specification
  - `--format` output format selection (raw, png, tiff)
  - `--verbose` and `--quiet` output modes
- `jpegls batch` command for batch processing
  - Support for glob patterns (`*.jls`, `images/*.raw`)
  - Directory scanning for batch operations
  - Parallel processing with configurable `--parallelism`
  - Progress reporting with `--verbose` mode
  - Error handling with optional `--fail-fast` mode
  - Support for info, verify, encode, and decode operations
- `jpegls completion` command for shell completions
  - Bash completion script generation
  - Zsh completion script generation
  - Fish completion script generation
  - Installation instructions in help text
- Comprehensive help messages for all commands with examples
- Mutual exclusivity validation for `--verbose`/`--quiet` and `--json`/`--quiet`
- ValidationError type for consistent CLI argument validation
- Comprehensive CLI argument parsing test suite (CLIArgumentParsingTests.swift)
  - 60 tests organised into 11 test suites
  - Tests for all commands (encode, decode, info, verify, batch, completion)
  - Tests for flag combinations and mutual exclusivity
  - Parameter validation tests (width, height, bits-per-sample, NEAR, etc.)
  - Edge case testing for boundary values
  - Overall project coverage maintained at 96.08%

## [0.6.0] - Completed

### Added

#### Memory Optimisation (Milestone 5.4)
- `JPEGLSBufferPool` for reusable buffer management
  - Thread-safe buffer acquisition and release
  - Support for multiple buffer types (context arrays, pixel data, bitstream)
  - Automatic cleanup of expired buffers
  - Shared global pool via `sharedBufferPool`
  - 11 comprehensive tests
- `JPEGLSTileProcessor` for tile-based processing of large images
  - Configurable tile size and overlap
  - Memory savings estimation
  - Support for images larger than available memory
  - 16 comprehensive tests
- `JPEGLSCacheFriendlyBuffer` with contiguous memory layout
  - Row-major order for cache efficiency
  - Optimised neighbour access patterns
  - Batch row access for vectorised operations
  - 22 comprehensive tests

## [0.5.0] - Completed

### Added

#### Apple Silicon Optimisation (Milestone 5)
- `ARM64Accelerator` with NEON/SIMD optimisations
  - NEON-optimised gradient computation
  - NEON-optimised MED prediction
  - NEON-optimised context quantisation
  - Uses Swift SIMD4 types for vectorised operations
  - Compiles to native NEON instructions on Apple Silicon
  - Bit-exact results verified by comprehensive tests
- `X86_64Accelerator` with SSE/AVX optimisations
  - SSE/AVX-optimised gradient computation
  - SSE/AVX-optimised MED prediction
  - SSE/AVX-optimised context quantisation
  - Uses Swift SIMD4 types for vectorised operations
  - Compiles to SSE/AVX instructions on Intel processors
  - Bit-exact results verified by comprehensive tests
- `AccelerateFrameworkAccelerator` using Apple's vDSP library
  - Batch gradient computation for multiple pixels
  - Statistical analysis (mean, variance, standard deviation, min/max)
  - Histogram computation for image analysis
  - Batch vector operations (addition, subtraction, scalar multiplication)
  - 50+ comprehensive tests
  - Performance benchmarks comparing Accelerate vs scalar
- Platform abstraction protocols for clean separation
  - `PlatformAccelerator` protocol
  - Conditional compilation for architecture-specific code
  - Benchmarks for platform performance comparison
- Comprehensive test suite with 100% coverage for platform code

#### x86-64 Implementation (Milestone 6)
- Separate x86-64 module with clear boundaries
- All x86-64 code conditionally compiled with `#if arch(x86_64)`
- X86_64_REMOVAL_GUIDE.md with step-by-step removal instructions
- Documentation of all x86-64 files and dependencies
- Cross-platform compatibility tests
- Bit-exact output verification between ARM64 and x86-64
- 100% test coverage for x86-64 code paths (78/78 lines)

## [0.4.0] - Completed

### Added

#### Multi-Component & Interleaved Encoding (Milestone 3.4)
- Component interleaving modes (None, Line, Sample)
- Multi-component frame handling
- `PixelBuffer` abstraction for multi-component pixel access
- Line-interleaved encoding implementation
- Sample-interleaved encoding implementation
- 14 comprehensive tests covering all interleaving modes
- 100% test coverage for interleaved encoding

#### Multi-Component Decoding (Milestone 4.4)
- Deinterleaving for all modes (None, Line, Sample)
- Component reconstruction from interleaved data
- Colour transformation inverse operations
- 92.10% test coverage for multi-component decoding

## [0.3.0] - Completed

### Added

#### JPEG-LS Decoder (Milestone 4)
- `JPEGLSParser` for JPEG-LS file format parsing
  - Marker segment parsing and validation
  - Frame header decoding
  - Scan header decoding
  - Preset parameter table decoding
  - Extension marker handling
  - 100% test coverage for parsing
- Regular mode decoding
  - Prediction reconstruction using MED
  - Golomb-Rice decoding
  - Prediction error recovery with bias correction
  - Context state reconstruction
  - Sample value computation with clamping
  - 96.90% test coverage
- Run mode decoding
  - Run-length decoding logic
  - Run interruption sample decoding
  - Run mode context reconstruction
  - 100% test coverage

## [0.2.0] - Completed

### Added

#### JPEG-LS Encoder (Milestone 3)
- Regular mode encoding
  - Gradient computation for mode detection
  - MED (Median Edge Detector) prediction
  - Prediction error computation with modular reduction
  - Golomb-Rice parameter estimation (k calculation)
  - Golomb-Rice encoding of prediction errors
  - Context-based bias correction
  - 100% test coverage
- Run mode encoding
  - Run-length detection logic
  - Run-length encoding with interruption samples
  - J[RUNindex] mapping table
  - Run mode context updates
  - Run-length limit handling
  - 100% test coverage
- Near-lossless encoding
  - NEAR parameter handling (error tolerance 1-255)
  - Quantised prediction error calculation
  - Reconstructed value computation for decoder tracking
  - Modified threshold parameters for near-lossless
  - Error bounds compliance validation
  - 98.14% test coverage

## [0.1.0] - Completed

### Added

#### Project Foundation (Milestone 1 & 2)
- Swift Package Manager manifest (Swift 6.2+)
- Project structure: `Sources/`, `Tests/`
- GitHub Copilot instructions (`.github/copilot-instructions.md`)
- CI pipeline with GitHub Actions
- >95% test code coverage enforcement in CI
- Initial documentation (README.md, MILESTONES.md)

#### JPEG-LS Foundation (Milestone 2.1 & 2.2)
- Project architecture with separate targets
  - `JPEGLS` library target
  - `jpegls` command-line tool target
- Directory structure:
  - `Sources/JPEGLS/Core/` — Core codec types and protocols
  - `Sources/JPEGLS/Encoder/` — Encoding implementation
  - `Sources/JPEGLS/Decoder/` — Decoding implementation
  - `Sources/JPEGLS/Platform/` — Platform-specific optimisations
  - `Sources/JPEGLS/Platform/ARM64/` — Apple Silicon / ARM NEON code
  - `Sources/JPEGLS/Platform/x86_64/` — x86-64 specific code
  - `Sources/jpegls/` — CLI tool source
- JPEG-LS marker segment types (SOI, EOI, SOF, SOS, LSE, etc.)
- `JPEGLSFrameHeader` structures per ITU-T.87
- `JPEGLSScanHeader` structures
- `JPEGLSPresetParameters` (MAXVAL, T1, T2, T3, RESET)
- Colour transformation types (None, HP1, HP2, HP3)
- `JPEGLSError` type with comprehensive error codes
- `JPEGLSBitstreamReader` and `JPEGLSBitstreamWriter` utilities
- 96.24% test coverage for core types

#### Context Modelling (Milestone 2.3)
- Context quantisation (Q1, Q2, Q3 gradient calculations)
- Context index computation (365 regular contexts)
- Run-length context handling
- Context state management (A, B, C, N arrays)
- Context initialization with default parameters
- Context update and adaptation logic
- 96.88% test coverage for context modelling

## Release Notes Format

See [RELEASE_NOTES_TEMPLATE.md](RELEASE_NOTES_TEMPLATE.md) for the release notes template used for GitHub releases.

## Version History

- **0.1.0** - Project foundation and JPEG-LS core types
- **0.2.0** - JPEG-LS encoder (regular mode, run mode, near-lossless)
- **0.3.0** - JPEG-LS decoder (parsing, regular mode, run mode)
- **0.4.0** - Multi-component support (RGB, interleaving)
- **0.5.0** - Platform optimisation (ARM64, x86_64, Accelerate)
- **0.6.0** - Memory optimisation (buffer pooling, tile processing)
- **0.7.0** - CLI tool (info, verify, encode, decode, batch, completion)
- **0.8.0** - Validation & conformance (CharLS, benchmarks, edge cases)
- **1.0.0** - Planned stable release

<!-- Note: Comparison links will be added after the first release is tagged -->
[Unreleased]: https://github.com/Raster-Lab/JLSwift/commits/main
