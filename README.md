# JLSwift

A Swift 6.2+ utility library providing core helpers for validation, string manipulation, and mathematical operations. Also home to the **JPEGLS** native Swift implementation of JPEG-LS compression for DICOM medical imaging.

[![CI](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/JLSwift/actions/workflows/ci.yml)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-See%20Repository-lightgrey.svg)](LICENSE)

## Overview

JLSwift is designed for developers who need reliable, well-tested utility functions in their Swift projects. The library emphasizes:

- **Type Safety**: Leverages Swift 6.2+ strict concurrency and type system
- **Performance**: Optimized implementations with support for hardware acceleration
- **Reliability**: Comprehensive test coverage exceeding 95% for all modules
- **Modularity**: Clean separation of concerns with distinct modules for different functionality

### Library Modules

| Module | Description |
|--------|-------------|
| **JLSwift** | Core utilities including validation, string extensions, and math functions |
| **JPEGLS** | Native Swift JPEG-LS compression for medical imaging (DICOM compatible) |

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

Then add the desired module(s) as a dependency of your target:

```swift
// For core utilities
.target(name: "YourTarget", dependencies: ["JLSwift"])

// For JPEG-LS compression functionality
.target(name: "YourTarget", dependencies: ["JPEGLS"])

// For both modules
.target(name: "YourTarget", dependencies: ["JLSwift", "JPEGLS"])
```

## JLSwift Module

The JLSwift module provides essential utility functions organized into three main categories:

### JLSValidator

Common validation utilities for strings with a clean, functional API.

| Method | Description |
|--------|-------------|
| `isValidEmail(_:)` | Validates email format (checks for `@`, domain with `.`) |
| `isNonEmpty(_:)` | Checks if string contains non-whitespace characters |
| `isLengthValid(_:min:max:)` | Validates string length is within bounds |

```swift
import JLSwift

// Email validation
JLSValidator.isValidEmail("user@example.com")     // true
JLSValidator.isValidEmail("invalid-email")        // false
JLSValidator.isValidEmail("user@domain")          // false (no TLD)

// Non-empty validation  
JLSValidator.isNonEmpty("hello")                  // true
JLSValidator.isNonEmpty("   ")                    // false

// Length validation
JLSValidator.isLengthValid("abc", min: 1, max: 5) // true
JLSValidator.isLengthValid("toolong", min: 1, max: 5) // false
```

### String Extensions

Handy extensions on `String` for common text manipulation tasks.

| Extension | Description |
|-----------|-------------|
| `trimmed()` | Returns string with leading/trailing whitespace removed |
| `capitalizedFirst()` | Capitalizes only the first letter |
| `isAlphanumeric` | Property checking if all characters are letters/digits |
| `repeated(_:)` | Returns string repeated n times |
| `wordCount` | Property returning the number of words |

```swift
import JLSwift

// Trimming whitespace
"  hello world  ".trimmed()       // "hello world"
"\n\ttabbed\n".trimmed()          // "tabbed"

// First letter capitalization (preserves rest)
"hello world".capitalizedFirst()  // "Hello world"
"HELLO".capitalizedFirst()        // "HELLO"

// Alphanumeric check
"abc123".isAlphanumeric           // true
"hello world".isAlphanumeric      // false (contains space)
"".isAlphanumeric                 // false

// String repetition
"ab".repeated(3)                  // "ababab"
"hi".repeated(0)                  // ""

// Word counting
"hello world".wordCount           // 2
"one".wordCount                   // 1
"  spaced   out  ".wordCount      // 2
```

### JLSMathUtils

Mathematical utility functions with safe handling of edge cases.

| Method | Description |
|--------|-------------|
| `clamp(_:lower:upper:)` | Constrains value to specified range |
| `factorial(_:)` | Computes factorial (returns `nil` for negative input) |
| `gcd(_:_:)` | Greatest common divisor using Euclidean algorithm |
| `isPrime(_:)` | Checks if number is prime |

```swift
import JLSwift

// Value clamping
JLSMathUtils.clamp(15, lower: 0, upper: 10)  // 10
JLSMathUtils.clamp(-5, lower: 0, upper: 10)  // 0
JLSMathUtils.clamp(5, lower: 0, upper: 10)   // 5

// Factorial (safe for negative numbers)
JLSMathUtils.factorial(5)                     // 120
JLSMathUtils.factorial(0)                     // 1
JLSMathUtils.factorial(-1)                    // nil

// Greatest common divisor
JLSMathUtils.gcd(12, 8)                       // 4
JLSMathUtils.gcd(17, 13)                      // 1
JLSMathUtils.gcd(-12, 8)                      // 4 (handles negatives)

// Prime checking
JLSMathUtils.isPrime(7)                       // true
JLSMathUtils.isPrime(4)                       // false
JLSMathUtils.isPrime(1)                       // false
JLSMathUtils.isPrime(2)                       // true
```

## JPEGLS Module

**JPEGLS** is a native Swift implementation of JPEG-LS (ISO/IEC 14495-1:1999 / ITU-T.87) compression, designed for the DICOMkit project and optimized for medical imaging workflows.

### What is JPEG-LS?

JPEG-LS is a lossless/near-lossless compression standard specifically designed for continuous-tone images. It's widely used in medical imaging (DICOM) due to its excellent compression ratio while maintaining image fidelity—critical for diagnostic accuracy.

### Current Implementation Status

| Phase | Component | Status | Coverage |
|-------|-----------|--------|----------|
| 4.2 | Core Types & Bitstream | ✅ Complete | 96.24% |
| 4.3 | Context Modeling | ✅ Complete | 96.88% |
| 5.1 | Regular Mode Encoding | ✅ Complete | 96.97% |
| 5.2 | Run Mode Encoding | ✅ Complete | 100.00% |
| 5.3 | Near-Lossless Encoding | 🔄 In Progress | - |
| 6.x | Decoder | 📋 Planned | - |
| 7.x | Apple Silicon Optimization | 📋 Planned | - |

**Overall Project Coverage: 97.30%**

### Key Features

| Feature | Description |
|---------|-------------|
| **Native Swift** | Pure Swift implementation with no external C dependencies |
| **Apple Silicon Optimized** | Primary target with ARM NEON/SIMD acceleration (planned) |
| **Hardware Acceleration** | Support for Apple Accelerate framework and Metal GPU (planned) |
| **DICOM Compatible** | Full support for DICOM transfer syntaxes |
| **Near-Lossless Support** | Configurable error tolerance encoding (in development) |

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
├── Encoder/                 # Encoding implementation
│   ├── RegularModeEncoder   # Gradient-based encoding (MED prediction)
│   └── RunModeEncoder       # Run-length encoding for flat regions
├── Platform/                # Platform-specific optimizations
│   ├── ARM64/               # Apple Silicon / ARM NEON code
│   └── x86_64/              # x86-64 specific code (removable)
└── PlatformProtocols        # Protocol-based platform abstraction
```

### Design Principles

1. **Platform Abstraction**: All platform-specific code behind protocols for clean separation
2. **Testability**: Every component designed for unit testing with >95% coverage
3. **Performance First**: Optimized for Apple Silicon while maintaining correctness
4. **x86-64 Removability**: Clear compilation boundaries for future x86-64 deprecation
5. **Memory Efficiency**: Streaming support for large medical images (planned)
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
swift build --target JLSwift
swift build --target JPEGLS
```

### Test Commands

```bash
# Run all tests
swift test

# Run tests with code coverage
swift test --enable-code-coverage

# Run tests for a specific target
swift test --filter JLSwiftTests
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
│   ├── JLSwift/               # Core utility library
│   │   ├── JLSCore.swift      # Version and core exports
│   │   ├── JLSValidator.swift # Validation utilities
│   │   ├── JLSMathUtils.swift # Mathematical functions
│   │   └── JLSStringExtensions.swift # String extensions
│   └── JPEGLS/                # JPEG-LS compression library
│       ├── Core/              # Core types and protocols
│       ├── Encoder/           # Encoding implementation
│       ├── Platform/          # Platform-specific code
│       └── JPEGLS.swift       # Module exports
├── Tests/
│   ├── JLSwiftTests/          # JLSwift unit tests
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