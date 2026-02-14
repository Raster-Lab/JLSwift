# JLSwift

A Swift 6.2+ utility library providing core helpers for validation, string manipulation, and mathematical operations.

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

Then add `"JLSwift"` as a dependency of your target:

```swift
.target(name: "YourTarget", dependencies: ["JLSwift"])
```

## Modules

### Validator

Common validation utilities for strings.

```swift
import JLSwift

Validator.isValidEmail("user@example.com")   // true
Validator.isNonEmpty("hello")                // true
Validator.isLengthValid("abc", min: 1, max: 5) // true
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

### MathUtils

Mathematical utility functions.

```swift
import JLSwift

MathUtils.clamp(15, lower: 0, upper: 10) // 10
MathUtils.factorial(5)                    // 120
MathUtils.gcd(12, 8)                      // 4
MathUtils.isPrime(7)                      // true
```

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

## Documentation

- [MILESTONES.md](MILESTONES.md) — Project milestones and roadmap.
- [Copilot Instructions](.github/copilot-instructions.md) — Coding guidelines for contributors and Copilot.

When changes are made to the codebase, the README and MILESTONES.md **must** be updated to reflect new features, API changes, or milestone progress.

## License

This project is available under the terms specified by the repository owner.