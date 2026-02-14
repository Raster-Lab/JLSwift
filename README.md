# JLSwift

A Swift 6.2+ utility library providing core helpers for validation, string manipulation, and mathematical operations. Also home to the **JPEGLS** native Swift implementation of JPEG-LS compression for DICOM medical imaging.

[![CI](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml)

## Requirements

- Swift 6.2 or later
- Linux or macOS

## Installation

Add JLSwift as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
]
```

Then add `"JLSwift"` or `"JPEGLS"` as a dependency of your target:

```swift
.target(name: "YourTarget", dependencies: ["JLSwift"])
// or for JPEG-LS functionality:
.target(name: "YourTarget", dependencies: ["JPEGLS"])
```

## Modules

### JLSValidator

Common validation utilities for strings.

```swift
import JLSwift

JLSValidator.isValidEmail("user@example.com")   // true
JLSValidator.isNonEmpty("hello")                // true
JLSValidator.isLengthValid("abc", min: 1, max: 5) // true
```

### String Extensions

Handy extensions on `String`.

```swift
import JLSwift

"  hello  ".trimmed()         // "hello"
"hello world".capitalizedFirst() // "Hello world"
"abc123".isAlphanumeric       // true
"ab".repeated(3)              // "ababab"
"hello world".wordCount       // 2
```

### JLSMathUtils

Mathematical utility functions.

```swift
import JLSwift

JLSMathUtils.clamp(15, lower: 0, upper: 10) // 10
JLSMathUtils.factorial(5)                    // 120
JLSMathUtils.gcd(12, 8)                      // 4
JLSMathUtils.isPrime(7)                      // true
```

## JPEG-LS Compression (In Development)

**JPEGLS** is a native Swift implementation of JPEG-LS (ISO/IEC 14495-1:1999 / ITU-T.87) compression, designed for the DICOMkit project.

### Current Status

**Phase 4.3: Context Modeling - Completed ✅**
- Context state management with 365 regular contexts
- Gradient quantization and context index computation
- Run-length context handling
- Adaptive statistics (A, B, C, N arrays) with reset mechanism
- Comprehensive error handling
- **Test Coverage: 96.88%**

**Phase 5.1: Regular Mode Encoding - Completed ✅**
- Gradient computation for regular mode detection (D1, D2, D3)
- MED (Median Edge Detector) prediction algorithm
- Prediction error computation with modular reduction
- Golomb-Rice parameter estimation leveraging context model
- Golomb-Rice encoding of prediction errors
- Context-based bias correction
- **Test Coverage: 96.97%**
- **Overall Project Coverage: 96.97%**

**Next: Phase 5.2** - Run mode encoding implementation (run-length detection, encoding, context updates)

### Key Features (Planned)

- **Native Swift**: Pure Swift implementation with no external C dependencies
- **Apple Silicon Optimized**: Primary target with ARM NEON/SIMD acceleration
- **Hardware Acceleration**: Support for Apple Accelerate framework and Metal GPU
- **DICOM Compatible**: Full support for DICOM transfer syntaxes
- **Near-Lossless Support**: Configurable error tolerance encoding
- **Command-Line Tool**: `jpegls` CLI for encoding, decoding, and validation

### Architecture

- **Platform Abstraction**: Protocol-based design with `PlatformAccelerator` for clean separation of architecture-specific code
- **Conditional Compilation**: ARM64 and x86-64 code isolated with compile-time selection
- **Scalar Fallback**: Reference implementation available on all platforms
- **x86-64 Removability**: x86-64 code kept separate for future removal
- **CharLS Compatible**: Validated against CharLS reference implementation (planned)
- **Streaming Support**: Memory-efficient processing for large medical images (planned)

See [MILESTONES.md](MILESTONES.md) for the detailed development roadmap.

## Building

```bash
swift build
```

## Testing

```bash
# Run tests
swift test

# Run tests with code coverage
swift test --enable-code-coverage
```

> **Test coverage requirement**: This project requires >95% test code coverage. The CI pipeline enforces this threshold on every push and pull request.

## Documentation

- [MILESTONES.md](MILESTONES.md) — Project milestones and roadmap.
- [Copilot Instructions](.github/copilot-instructions.md) — Coding guidelines for contributors and Copilot.

When changes are made to the codebase, the README and MILESTONES.md **must** be updated to reflect new features, API changes, or milestone progress.

## License

This project is available under the terms specified by the repository owner.