# Versioning Strategy

## Overview

JLSwift follows [Semantic Versioning 2.0.0](https://semver.org/) for all releases. This document defines how version numbers are assigned and what changes warrant version increments.

## Version Format

Version numbers follow the format: **MAJOR.MINOR.PATCH** (e.g., `1.0.0`)

### Pre-release Versions

Pre-release versions append a hyphen and pre-release identifier:
- **Alpha**: `0.1.0-alpha.1` - Early development, may have incomplete features
- **Beta**: `0.9.0-beta.1` - Feature complete, undergoing testing
- **Release Candidate**: `1.0.0-rc.1` - Final testing before stable release

## Version Increment Rules

### MAJOR Version (X.0.0)

Increment the MAJOR version when making **incompatible API changes**:
- Removing public APIs, types, or functions
- Changing function signatures (parameter types, return types)
- Changing public protocol requirements
- Removing or renaming public properties
- Breaking changes to encoding/decoding formats
- Changing behavior that breaks existing client code

**Example**: `1.0.0` → `2.0.0`

### MINOR Version (0.X.0)

Increment the MINOR version when adding **backward-compatible functionality**:
- Adding new public APIs, types, or functions
- Adding new features or capabilities
- Adding optional protocol methods with default implementations
- Deprecating APIs (without removal)
- Internal improvements that don't affect public API
- Performance optimizations
- New platform support (e.g., watchOS, tvOS)

**Example**: `1.0.0` → `1.1.0`

### PATCH Version (0.0.X)

Increment the PATCH version for **backward-compatible bug fixes**:
- Fixing bugs without changing API
- Correcting documentation errors
- Security patches
- Performance bug fixes
- Build system improvements
- Test improvements
- Internal refactoring with no API impact

**Example**: `1.0.0` → `1.0.1`

## Version 0.x.x - Initial Development

During initial development (version 0.x.x), the API is not considered stable:
- **0.x.0**: Breaking changes are allowed in MINOR versions
- **0.0.x**: Any changes are allowed in PATCH versions
- Backward compatibility is not guaranteed
- Public API may change without notice

Once the API is stable and production-ready, release version **1.0.0**.

## Version 1.0.0 and Beyond

Version 1.0.0 marks the first **stable, production-ready release**:
- Public API is stable and backward-compatible
- Breaking changes only in MAJOR version increments
- Semantic versioning strictly enforced
- Deprecation warnings before API removal

### API Deprecation Process

When deprecating APIs:
1. Mark as `@available(*, deprecated, message: "Use XYZ instead")`
2. Include deprecation in CHANGELOG with migration guide
3. Keep deprecated API for at least one MINOR version
4. Remove in next MAJOR version

**Example Timeline**:
- `1.0.0`: Introduce `newAPI()`
- `1.1.0`: Deprecate `oldAPI()`, recommend `newAPI()`
- `1.2.0`: Keep `oldAPI()` deprecated
- `2.0.0`: Remove `oldAPI()`, keep only `newAPI()`

## Release Cadence

### Regular Releases

- **PATCH releases**: As needed for bug fixes (weekly or bi-weekly)
- **MINOR releases**: Monthly or when significant features are ready
- **MAJOR releases**: Annually or when breaking changes are necessary

### Emergency Releases

Security vulnerabilities warrant immediate PATCH releases regardless of regular schedule.

## Git Tagging

All releases are tagged in Git with the format `vX.Y.Z`:
- Tag format: `v1.0.0`, `v1.1.0-beta.1`, `v2.0.0-rc.1`
- Tags are annotated with release notes
- Tags trigger automated CI/CD release pipeline

### Tagging Process

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0"

# Push tag to remote
git push origin v1.0.0
```

## Branch Strategy

- **main**: Stable release branch (only release commits)
- **develop**: Active development branch
- **feature/**: Feature branches (merge to develop)
- **release/vX.Y.Z**: Release preparation branches
- **hotfix/**: Emergency bug fix branches (merge to main and develop)

## Swift Version Compatibility

| JLSwift Version | Minimum Swift Version | Platforms |
|-----------------|----------------------|-----------|
| 0.1.0 - 0.x.x   | Swift 6.2           | macOS 12+, iOS 15+, Linux |
| 1.0.0+          | Swift 6.2           | macOS 12+, iOS 15+, Linux |

Breaking Swift version compatibility (e.g., moving to Swift 7.0) requires a **MAJOR version increment**.

## Package Dependencies

- **Swift Argument Parser**: Follow conservative update strategy
  - Lock to compatible MINOR version range (e.g., `from: "1.5.0"`)
  - Test thoroughly before updating MAJOR version
  - Document dependency version requirements in CHANGELOG

## Platform Support

### Primary Platforms
- **Apple Silicon** (ARM64): Fully supported with hardware acceleration
- **macOS 12+**: Full framework support including Accelerate
- **iOS 15+**: Full framework support including Accelerate

### Secondary Platforms
- **Linux** (x86_64, ARM64): Command-line and library support
- **Intel Macs** (x86_64): Supported but may be deprecated in future MAJOR version

### Platform Deprecation
When deprecating platform support:
1. Announce deprecation in CHANGELOG and README
2. Keep support for at least one MINOR version cycle
3. Remove in next MAJOR version
4. Document migration path for affected users

## Pre-1.0 Roadmap

Current development phase leading to 1.0.0:

- **0.1.0**: Foundation (project setup, core types, context modeling)
- **0.2.0**: Basic encoder (regular mode, run mode)
- **0.3.0**: Basic decoder (parsing, regular mode, run mode)
- **0.4.0**: Multi-component support (RGB, interleaving)
- **0.5.0**: Platform optimization (ARM64, x86_64, Accelerate)
- **0.6.0**: Memory optimization (buffer pooling, tile processing)
- **0.7.0**: CLI tool (encode, decode, info, verify, batch)
- **0.8.0**: Validation & conformance (CharLS compatibility, benchmarks)
- **0.9.0-beta**: Beta testing with real-world usage
- **1.0.0**: Stable production release

## Version Lifecycle

### Support Policy

- **Current**: Latest MAJOR.MINOR version receives all updates
- **Previous MINOR**: Security patches only for 6 months
- **Previous MAJOR**: Security patches only for 1 year
- **Older versions**: No support

### End-of-Life (EOL)

When a version reaches EOL:
1. Announce EOL date 6 months in advance
2. Document migration path to supported version
3. Update README to reflect supported versions
4. Archive release branches

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [Swift Evolution Process](https://github.com/apple/swift-evolution)
