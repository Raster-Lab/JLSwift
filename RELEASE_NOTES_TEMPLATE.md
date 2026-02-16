# Release Notes Template

Use this template when creating GitHub releases for JLSwift.

---

# JLSwift vX.Y.Z

**Release Date**: YYYY-MM-DD  
**Type**: [Major Release | Minor Release | Patch Release | Beta Release | Release Candidate]

## Overview

[Brief 2-3 sentence summary of this release. What's the main theme or focus?]

## Highlights

[List 3-5 key highlights that users will care about most]

- 🎉 **Feature Name**: Brief description of the feature and why it matters
- ⚡ **Performance**: Description of performance improvements
- 🐛 **Bug Fixes**: Summary of critical bug fixes
- 📚 **Documentation**: New guides or documentation improvements

## What's New

### Added

[List new features, APIs, capabilities]

- **Feature Name** ([#PR](link))
  - Detailed description of the feature
  - Usage example or link to documentation
  - Benefits to users

### Changed

[List breaking changes, deprecated features, or significant modifications]

- **API Change** ([#PR](link))
  - What changed and why
  - Migration guide or impact description
  - Link to migration documentation if needed

### Fixed

[List bug fixes]

- **Bug Description** ([#PR](link) / [#Issue](link))
  - What was fixed
  - Impact on users
  - Conditions that triggered the bug

### Deprecated

[List deprecated features that will be removed in future versions]

- **API Name** ([#PR](link))
  - What's deprecated and why
  - Recommended replacement
  - Timeline for removal (e.g., "Will be removed in v2.0.0")

### Removed

[List removed features - only for MAJOR releases]

- **Feature Name** ([#PR](link))
  - What was removed
  - Reason for removal
  - Alternative solution

## Performance

[Optional section for releases with significant performance improvements]

### Benchmarks

| Operation | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Encode 512x512 8-bit | X.XX MB/s | Y.YY MB/s | +Z% |
| Decode 512x512 8-bit | X.XX MB/s | Y.YY MB/s | +Z% |

### Memory Usage

- Reduced memory usage by X% for large images through [feature]
- Improved cache efficiency by Y% with [optimization]

## Breaking Changes

[Only for MAJOR releases or significant MINOR releases]

### Migration Guide

**If you're upgrading from vX.Y.Z:**

1. **Update dependencies**
   ```swift
   dependencies: [
       .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "X.Y.Z")
   ]
   ```

2. **Replace deprecated APIs**
   ```swift
   // Old API (deprecated)
   let result = oldFunction(param)
   
   // New API (recommended)
   let result = newFunction(param)
   ```

3. **Update function signatures**
   - List any changes to function signatures
   - Provide before/after examples

4. **Test your code**
   - Run your test suite to catch any issues
   - Pay special attention to [specific areas]

## Known Issues

[List known issues that users should be aware of]

- **Issue description** ([#Issue](link))
  - Workaround if available
  - Planned fix version

## Installation

### Swift Package Manager

Add JLSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "X.Y.Z")
]
```

### Command-Line Tool

Build the CLI tool:

```bash
git clone https://github.com/Raster-Lab/JLSwift.git
cd JLSwift
git checkout vX.Y.Z
swift build -c release
```

The binary will be at `.build/release/jpegls`.

## Requirements

- **Swift**: 6.2 or later
- **Platforms**: macOS 12+, iOS 15+, Linux
- **Primary**: Apple Silicon (M1/M2/M3) with ARM64 optimizations
- **Secondary**: x86-64 (Intel Macs, Linux) with SSE/AVX optimizations

## Documentation

- [Getting Started Guide](GETTING_STARTED.md)
- [Usage Examples](USAGE_EXAMPLES.md)
- [Performance Tuning](PERFORMANCE_TUNING.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [API Documentation](https://raster-lab.github.io/JLSwift/documentation/jpegls/) *(if available)*

## Contributors

[Acknowledge contributors to this release]

Thank you to everyone who contributed to this release:
- [@username](link) - Feature/fix description
- [@username](link) - Feature/fix description

## Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for the complete list of changes in this release.

**Full Changelog**: vX.Y.Z-1...vX.Y.Z

---

## Example Usage

[Provide 1-2 code examples showcasing new features]

### Example 1: New Feature

```swift
import JPEGLS

// Example demonstrating the new feature
let encoder = JPEGLSEncoder()
// ... code example
```

### Example 2: Performance Optimization

```swift
import JPEGLS

// Example showing how to use the performance optimization
let processor = JPEGLSTileProcessor(/* ... */)
// ... code example
```

---

## Support

- **Issues**: [GitHub Issues](https://github.com/Raster-Lab/JLSwift/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Raster-Lab/JLSwift/discussions)
- **Documentation**: [GitHub Pages](https://raster-lab.github.io/JLSwift/)

---

## Notes for Release Creators

### Checklist before publishing:

- [ ] Update version number throughout this document
- [ ] Fill in all sections with relevant content
- [ ] Remove sections that don't apply (e.g., "Breaking Changes" for patch releases)
- [ ] Update CHANGELOG.md with the same information
- [ ] Create Git tag: `git tag -a vX.Y.Z -m "Release version X.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Verify CI pipeline passes for the tagged release
- [ ] Test installation from the tag
- [ ] Publish release on GitHub with these notes
- [ ] Update README.md if installation instructions changed
- [ ] Announce release (if applicable)

### Tips:

- **Be specific**: Include issue/PR numbers for traceability
- **Be helpful**: Explain *why* changes were made, not just *what* changed
- **Be honest**: Document known issues and limitations
- **Be positive**: Highlight achievements and improvements
- **Be concise**: Keep descriptions brief but informative
- **Use emoji**: Make sections easy to scan (🎉 ⚡ 🐛 📚 ⚠️ 💥)

### Version-Specific Guidance:

**Patch Releases (0.0.X):**
- Focus on bug fixes and minor improvements
- Keep release notes brief
- No breaking changes
- Emphasize stability and reliability

**Minor Releases (0.X.0):**
- Highlight new features and enhancements
- Include usage examples for major features
- Document deprecations clearly
- Show performance improvements

**Major Releases (X.0.0):**
- Comprehensive migration guide is essential
- Document all breaking changes
- Explain rationale for breaking changes
- Provide before/after code examples
- Consider creating a dedicated migration guide document

**Pre-release Versions:**
- Clearly mark as alpha, beta, or RC
- Emphasize testing and feedback
- Document known limitations
- Set expectations appropriately
