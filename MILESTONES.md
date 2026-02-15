# MILESTONES.md

## JLSwift Project Milestones

### Milestone 1: Project Setup ✅
**Target**: Initial release foundation  
**Status**: Complete

- [x] Initialize Swift Package (Swift 6.2+)
- [x] Set up project structure (`Sources/`, `Tests/`)
- [x] Create GitHub Copilot instructions (`.github/copilot-instructions.md`)
- [x] Set up CI pipeline with GitHub Actions
- [x] Enforce >95% test code coverage in CI
- [x] Create initial documentation (`README.md`, `MILESTONES.md`)

### Milestone 2: Core Utilities ✅
**Target**: Core utility modules  
**Status**: Complete

- [x] Implement `JLSValidator` module (email, non-empty, length validation)
- [x] Implement `StringExtensions` (trimmed, capitalizedFirst, isAlphanumeric, repeated, wordCount)
- [x] Implement `JLSMathUtils` (clamp, factorial, gcd, isPrime)
- [x] Achieve >95% test coverage for all modules
- [x] Update file naming pattern to use JLS prefix (JLSCore, JLSValidator, JLSMathUtils, JLSStringExtensions)

### Milestone 3: Future Enhancements 🔮
**Target**: Expanded functionality  
**Status**: Planned

- [ ] Add networking utilities
- [ ] Add date/time helpers
- [ ] Add collection extensions
- [ ] Add async/await utilities leveraging Swift 6.2+ concurrency
- [ ] Add documentation generation (DocC)

---

## JPEG-LS Implementation (DICOMkit Project)

Native Swift implementation of JPEG-LS (ISO/IEC 14495-1:1999 / ITU-T.87) compression for DICOM medical imaging. Optimized for Apple Silicon with hardware acceleration support.

### Milestone 4: JPEG-LS Foundation 📋
**Target**: Core architecture and basic implementation  
**Status**: In Progress

#### Phase 4.1: Project Architecture Setup ✅
- [x] Create `JPEGLS` library target in Package.swift
- [x] Create `jpegls` command-line tool target in Package.swift
- [x] Set up directory structure:
  - [x] `Sources/JPEGLS/Core/` — Core codec types and protocols
  - [x] `Sources/JPEGLS/Encoder/` — Encoding implementation
  - [x] `Sources/JPEGLS/Decoder/` — Decoding implementation
  - [x] `Sources/JPEGLS/Platform/` — Platform-specific optimizations
  - [x] `Sources/JPEGLS/Platform/ARM64/` — Apple Silicon / ARM NEON code
  - [x] `Sources/JPEGLS/Platform/x86_64/` — x86-64 specific code (removable)
  - [x] `Sources/jpegls/` — CLI tool source
- [x] Define architecture boundary protocols for platform abstraction
- [x] Create conditional compilation structure for architecture separation

#### Phase 4.2: JPEG-LS Standard Core Types ✅
- [x] Implement JPEG-LS marker segment types (SOI, EOI, SOF, SOS, LSE, etc.)
- [x] Implement frame header structures per ITU-T.87
- [x] Implement scan header structures
- [x] Implement preset parameters structure (MAXVAL, T1, T2, T3, RESET)
- [x] Implement color transformation types (None, HP1, HP2, HP3)
- [x] Create `JPEGLSError` type with comprehensive error codes
- [x] Implement bitstream reader/writer utilities
- [x] Achieve >95% test coverage for core types (96.24%)

#### Phase 4.3: Context Modeling Implementation ✅
- [x] Implement context quantization (Q1, Q2, Q3 gradient calculations)
- [x] Implement context index computation (365 regular contexts)
- [x] Implement run-length context handling
- [x] Implement context state management (A, B, C, N arrays)
- [x] Implement context initialization with default parameters
- [x] Implement context update and adaptation logic
- [x] Achieve >95% test coverage for context modeling (96.88%)

### Milestone 5: JPEG-LS Encoder 📋
**Target**: Complete encoding pipeline  
**Status**: In Progress

#### Phase 5.1: Regular Mode Encoding ✅
- [x] Implement gradient computation for regular mode detection
- [x] Implement prediction using MED (Median Edge Detector)
- [x] Implement prediction error computation and modular reduction
- [x] Implement Golomb-Rice parameter estimation (k calculation)
- [x] Implement Golomb-Rice encoding of prediction errors
- [x] Implement context-based bias correction
- [x] Achieve >95% test coverage for regular mode (96.97%)

#### Phase 5.2: Run Mode Encoding ✅
- [x] Implement run-length detection logic
- [x] Implement run-length encoding with run interruption samples
- [x] Implement J[RUNindex] mapping table
- [x] Implement run mode context updates
- [x] Implement run-length limit handling
- [x] Achieve >95% test coverage for run mode (100.00%)

#### Phase 5.3: Near-Lossless Encoding
- [ ] Implement NEAR parameter handling (error tolerance)
- [ ] Implement quantized prediction error calculation
- [ ] Implement reconstructed value computation for decoder tracking
- [ ] Implement modified threshold parameters for near-lossless
- [ ] Validate error bounds compliance
- [ ] Achieve >95% test coverage for near-lossless mode

#### Phase 5.4: Multi-Component & Interleaved Encoding
- [ ] Implement component interleaving modes (None, Line, Sample)
- [ ] Implement multi-component frame handling
- [ ] Implement restart marker support
- [ ] Implement line-interleaved encoding
- [ ] Implement sample-interleaved encoding
- [ ] Achieve >95% test coverage for interleaved modes

### Milestone 6: JPEG-LS Decoder 📋
**Target**: Complete decoding pipeline  
**Status**: Planned

#### Phase 6.1: Bitstream Parsing
- [ ] Implement JPEG-LS file format parser
- [ ] Implement marker segment parsing and validation
- [ ] Implement frame header decoding
- [ ] Implement scan header decoding
- [ ] Implement preset parameter table decoding
- [ ] Implement extension marker handling
- [ ] Achieve >95% test coverage for parsing

#### Phase 6.2: Regular Mode Decoding
- [ ] Implement prediction reconstruction
- [ ] Implement Golomb-Rice decoding
- [ ] Implement prediction error recovery with bias correction
- [ ] Implement context state reconstruction
- [ ] Implement sample value computation with clamping
- [ ] Achieve >95% test coverage for regular mode decoding

#### Phase 6.3: Run Mode Decoding
- [ ] Implement run-length decoding logic
- [ ] Implement run interruption sample decoding
- [ ] Implement run mode context reconstruction
- [ ] Achieve >95% test coverage for run mode decoding

#### Phase 6.4: Multi-Component Decoding
- [ ] Implement deinterleaving for all modes
- [ ] Implement component reconstruction
- [ ] Implement color transformation inverse operations
- [ ] Achieve >95% test coverage for multi-component decoding

### Milestone 7: Apple Silicon Optimization (ARM64) 📋
**Target**: Hardware-accelerated performance on Apple Silicon  
**Status**: Planned

#### Phase 7.1: ARM NEON / SIMD Optimization
- [ ] Implement NEON-optimized gradient computation
- [ ] Implement NEON-optimized prediction (vectorized MED)
- [ ] Implement NEON-optimized context quantization
- [ ] Implement NEON-optimized Golomb parameter calculation
- [ ] Implement NEON-optimized run detection
- [ ] Create benchmarks comparing scalar vs SIMD implementations
- [ ] Achieve >95% test coverage with SIMD parity verification

#### Phase 7.2: Apple Accelerate Framework Integration
- [ ] Evaluate vDSP functions for applicable operations
- [ ] Implement Accelerate-based batch gradient computation
- [ ] Implement Accelerate-based histogram operations
- [ ] Implement Accelerate-based statistical analysis
- [ ] Benchmark Accelerate vs manual SIMD implementations
- [ ] Select optimal implementation paths based on benchmarks

#### Phase 7.3: Metal GPU Acceleration (Optional/Experimental)
- [ ] Design GPU-friendly encoding pipeline
- [ ] Implement Metal compute shaders for prediction
- [ ] Implement Metal-based parallel context computation
- [ ] Implement GPU-CPU data transfer optimization
- [ ] Evaluate GPU acceleration cost/benefit for various image sizes
- [ ] Implement fallback for non-Metal environments

#### Phase 7.4: Memory Optimization
- [ ] Implement tile-based processing for large images
- [ ] Implement streaming encoder/decoder for memory-constrained environments
- [ ] Implement buffer pooling and reuse strategies
- [ ] Implement cache-friendly data layout
- [ ] Profile memory usage and optimize allocations

### Milestone 8: x86-64 Implementation (Removable) 📋
**Target**: x86-64 support with clear separation for future removal  
**Status**: Planned

#### Phase 8.1: x86-64 Baseline Implementation
- [ ] Create separate x86-64 module with clear boundaries
- [ ] Implement x86-64 specific optimizations using SSE/AVX intrinsics
- [ ] Ensure all x86-64 code is conditionally compiled (`#if arch(x86_64)`)
- [ ] Document all x86-64 specific files and dependencies
- [ ] Create removal guide for future x86-64 deprecation

#### Phase 8.2: x86-64 Testing
- [ ] Create x86-64 specific test targets
- [ ] Implement cross-platform compatibility tests
- [ ] Verify bit-exact output between ARM64 and x86-64 implementations
- [ ] Achieve >95% test coverage for x86-64 code paths

### Milestone 9: Command-Line Interface 📋
**Target**: Full-featured CLI tool  
**Status**: Planned

#### Phase 9.1: Core CLI Commands
- [ ] Implement `jpegls encode` command
  - [ ] Input file path (raw, PNG, TIFF, DICOM support)
  - [ ] Output file path
  - [ ] `--near` parameter for near-lossless encoding
  - [ ] `--interleave` mode selection (none, line, sample)
  - [ ] `--color-transform` selection
  - [ ] `--bits-per-sample` specification
  - [ ] `--preset` for custom T1, T2, T3, RESET parameters
- [ ] Implement `jpegls decode` command
  - [ ] Input JPEG-LS file path
  - [ ] Output file path
  - [ ] `--format` output format selection
- [ ] Implement `jpegls info` command for file analysis
- [ ] Implement `jpegls verify` for round-trip validation

#### Phase 9.2: CLI Utilities
- [ ] Implement `--verbose` output with progress indication
- [ ] Implement `--quiet` mode for scripting
- [ ] Implement `--json` output format for programmatic use
- [ ] Implement batch processing with glob patterns
- [ ] Implement parallel processing for batch operations
- [ ] Add shell completion scripts (bash, zsh, fish)

#### Phase 9.3: CLI Help & Documentation
- [ ] Implement comprehensive `--help` for all commands
- [ ] Create man page documentation
- [ ] Create usage examples in README
- [ ] Achieve >95% test coverage for CLI argument parsing

### Milestone 10: Validation & Conformance Testing 📋
**Target**: CharLS compatibility and standards compliance  
**Status**: Planned

#### Phase 10.1: CharLS Reference Integration
- [ ] Set up CharLS as test reference (via C interop or test fixtures)
- [ ] Create test image corpus (various sizes, bit depths, component counts)
- [ ] Implement bit-exact comparison with CharLS output
- [ ] Create automated conformance test suite
- [ ] Document any intentional deviations from CharLS behavior

#### Phase 10.2: Performance Benchmarking
- [ ] Create comprehensive benchmark suite
- [ ] Benchmark encoding speed vs CharLS
- [ ] Benchmark decoding speed vs CharLS
- [ ] Benchmark memory usage vs CharLS
- [ ] Create performance regression tests
- [ ] Generate benchmark reports for various:
  - [ ] Image sizes (small, medium, large, very large)
  - [ ] Bit depths (8-bit, 12-bit, 16-bit)
  - [ ] Component counts (grayscale, RGB, RGBA)
  - [ ] Near-lossless parameters
  - [ ] Hardware configurations (M1, M2, M3, Intel)

#### Phase 10.3: DICOM Integration Testing
- [ ] Test with real-world DICOM files
- [ ] Validate transfer syntax compliance (1.2.840.10008.1.2.4.80, 1.2.840.10008.1.2.4.81)
- [ ] Test with various DICOM modalities (CT, MR, CR, US, etc.)
- [ ] Create DICOM-specific test fixtures
- [ ] Document DICOM integration guidelines

#### Phase 10.4: Edge Cases & Robustness
- [ ] Test with malformed input handling
- [ ] Test boundary conditions (MAXVAL limits, extreme dimensions)
- [ ] Test memory pressure scenarios
- [ ] Implement fuzz testing for decoder robustness
- [ ] Achieve >95% overall test coverage

### Milestone 11: Documentation & Release 📋
**Target**: Production-ready release  
**Status**: Planned

#### Phase 11.1: API Documentation
- [ ] Complete DocC documentation for all public APIs
- [ ] Create getting started guide
- [ ] Create migration guide for CharLS users
- [ ] Create performance tuning guide
- [ ] Create troubleshooting guide

#### Phase 11.2: Integration Guides
- [ ] Create DICOMkit integration guide
- [ ] Create standalone usage examples
- [ ] Create SwiftUI/AppKit image loading examples
- [ ] Create server-side Swift usage examples

#### Phase 11.3: Release Preparation
- [ ] Create semantic versioning strategy
- [ ] Create CHANGELOG.md
- [ ] Create release notes template
- [ ] Set up automated release workflow
- [ ] Create binary distribution (xcframework) for Apple platforms
- [ ] Create Linux distribution packages

---

## Summary: JPEG-LS Development Phases

| Milestone | Description | Key Deliverables |
|-----------|-------------|------------------|
| **4** | Foundation | Architecture, core types, context modeling |
| **5** | Encoder | Regular mode, run mode, near-lossless, interleaving |
| **6** | Decoder | Parsing, regular mode, run mode, multi-component |
| **7** | Apple Silicon | NEON/SIMD, Accelerate, Metal, memory optimization |
| **8** | x86-64 | Removable x86-64 support with clear boundaries |
| **9** | CLI | Encode/decode commands, batch processing, utilities |
| **10** | Validation | CharLS conformance, benchmarks, DICOM testing |
| **11** | Release | Documentation, integration guides, distribution |

### Architecture Principles

1. **Platform Abstraction**: All platform-specific code behind protocols for clean separation
2. **Testability**: Every component designed for unit testing with >95% coverage
3. **Performance First**: Optimize for Apple Silicon while maintaining correctness
4. **x86-64 Removability**: Clear compilation boundaries for future deprecation
5. **Memory Efficiency**: Streaming support for large images, buffer pooling
6. **Standards Compliance**: Strict adherence to ISO/IEC 14495-1:1999 / ITU-T.87

### Dependencies

- **Swift 6.2+**: Required for modern concurrency and language features
- **Apple Accelerate**: Optional, for vectorized math operations
- **Metal**: Optional, for GPU acceleration
- **CharLS**: Test reference only (not runtime dependency)

### Hardware Targets

- **Primary**: Apple Silicon (M1, M2, M3 series) with ARM64
- **Secondary**: x86-64 (Intel Macs, Linux) — designed for removal
- **Minimum iOS**: iOS 15+ (for Metal 3 features if used)
- **Minimum macOS**: macOS 12+ (Monterey)

---

> **Note**: When updates are made to the codebase, this document and the README must be updated
> to reflect any changes in milestone progress, new features, or API modifications.
