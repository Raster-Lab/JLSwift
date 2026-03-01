# x86-64 Removal Guide

This document provides a comprehensive guide for removing x86-64 support from JLSwift when Apple Silicon becomes the sole supported platform.

## Overview

The x86-64 implementation in JLSwift is designed for **clean removal**. All x86-64-specific code is:
- Isolated in dedicated modules with clear boundaries
- Conditionally compiled using `#if arch(x86_64)` directives
- Tested independently with cross-platform compatibility verification
- Documented for future deprecation

This guide outlines the exact steps required to remove x86-64 support while maintaining the ARM64/Apple Silicon implementation.

## x86-64 Code Inventory

### Files to Remove

The following files contain x86-64-specific code and should be removed entirely:

1. **`Sources/JPEGLS/Platform/x86_64/X86_64Accelerator.swift`**
   - Primary x86-64 SIMD accelerator implementation
   - Contains SSE/AVX-optimised gradient computation, MED prediction, quantisation,
     Golomb-Rice parameter computation, run-length detection, and byte stuffing scanning
   - **Action**: Delete entire file

2. **`Sources/JPEGLS/Platform/x86_64/IntelMemoryOptimizer.swift`**
   - Intel cache-hierarchy parameters, tile-size tuning, cache-aligned buffer allocation,
     `IntelBufferPool`, prefetch hints, memory-mapped I/O helpers, and tuning parameters
   - **Action**: Delete entire file and directory

### Files to Modify

The following files contain conditional compilation for x86-64 and require targeted modifications:

#### 1. `Sources/JPEGLS/Core/PlatformProtocols.swift`

**Lines to Remove**: 135-139

```swift
    #elseif arch(x86_64)
    // Check if x86-64 SIMD accelerator is available
    if X86_64Accelerator.isSupported {
        return X86_64Accelerator()
    }
```

**Before**:
```swift
public func selectPlatformAccelerator() -> any PlatformAccelerator {
    #if arch(arm64)
    // Check if ARM64 NEON accelerator is available
    if ARM64Accelerator.isSupported {
        return ARM64Accelerator()
    }
    #elseif arch(x86_64)
    // Check if x86-64 SIMD accelerator is available
    if X86_64Accelerator.isSupported {
        return X86_64Accelerator()
    }
    #endif
    
    // Fallback to scalar implementation
    return ScalarAccelerator()
}
```

**After**:
```swift
public func selectPlatformAccelerator() -> any PlatformAccelerator {
    #if arch(arm64)
    // Check if ARM64 NEON accelerator is available
    if ARM64Accelerator.isSupported {
        return ARM64Accelerator()
    }
    #endif
    
    // Fallback to scalar implementation
    return ScalarAccelerator()
}
```

#### 2. `Tests/JPEGLSTests/PlatformProtocolsTests.swift`

**Lines to Remove**: Test cases specific to x86-64 (search for `#if arch(x86_64)`)

**x86-64 Test Cases to Remove**:
- `x86_64PlatformName()` test
- `x86_64IsSupported()` test  
- `x86_64Results()` test
- Any `#elseif arch(x86_64)` branches in platform selection tests

**Example Before**:
```swift
    #elseif arch(x86_64)
    // On x86_64, should get X86_64Accelerator
```

**Example After**: Delete the entire `#elseif arch(x86_64)` branch

#### 3. `Tests/JPEGLSTests/PlatformBenchmarks.swift`

**Lines to Remove**: x86-64 benchmark branches

**Example Before**:
```swift
        #elseif arch(x86_64)
        // On x86_64, should get X86_64Accelerator
        print("Running on x86_64 with SSE/AVX acceleration")
```

**Example After**: Delete the entire `#elseif arch(x86_64)` branch

#### 4. `Tests/JPEGLSTests/X86_64AcceleratorPhase14Tests.swift`

**Action**: Delete entire file. Contains Phase 14.1 tests for Golomb-Rice, run-length, and byte stuffing on x86-64.

#### 5. `Tests/JPEGLSTests/IntelMemoryOptimizerTests.swift`

**Action**: Delete entire file. Contains Phase 14.2 tests for Intel cache parameters, tile sizing, buffer pooling, and memory-mapped I/O.

### Documentation Files to Update

After removal, update these documentation files:

1. **`README.md`**
   - Remove references to x86-64 support
   - Update "Hardware Targets" section to show ARM64 only
   - Remove x86-64 from architecture overview
   - Update platform requirements

2. **`MILESTONES.md`**
   - Mark Milestone 6 as "Deprecated/Removed"
   - Update summary table
   - Remove x86-64 from dependencies and hardware targets sections

3. **`.github/copilot-instructions.md`** (if applicable)
   - Remove x86-64 build instructions
   - Update platform requirements

## Step-by-Step Removal Process

Follow these steps in order to cleanly remove x86-64 support:

### Step 1: Verify Current State

Before making any changes, verify the current project state:

```bash
# Run all tests to establish baseline
swift test

# Verify code coverage
swift test --enable-code-coverage

# List all x86-64 files
find . -path "*/x86_64/*" -o -name "*x86_64*" -o -name "*X86_64*"

# Search for x86_64 references
grep -r "x86_64" --include="*.swift" Sources/ Tests/
grep -r "x86-64" --include="*.md" .
```

### Step 2: Remove x86-64 Implementation Files

```bash
# Delete x86-64 accelerator directory
rm -rf Sources/JPEGLS/Platform/x86_64/

# Verify removal
ls -la Sources/JPEGLS/Platform/
```

### Step 3: Update Platform Protocols

Edit `Sources/JPEGLS/Core/PlatformProtocols.swift`:

1. Open the file
2. Locate the `selectPlatformAccelerator()` function (around line 129)
3. Remove lines 135-139 (the `#elseif arch(x86_64)` block)
4. Verify the function now only contains ARM64 check and scalar fallback
5. Save the file

### Step 4: Update Test Files

#### Update PlatformProtocolsTests.swift

```bash
# Open the file
vim Tests/JPEGLSTests/PlatformProtocolsTests.swift
```

Remove:
- All `#if arch(x86_64)` test cases
- All `#elseif arch(x86_64)` branches in platform selection tests

#### Update PlatformBenchmarks.swift

```bash
# Open the file  
vim Tests/JPEGLSTests/PlatformBenchmarks.swift
```

Remove:
- All `#elseif arch(x86_64)` benchmark branches

### Step 5: Verify Compilation and Tests

After making code changes, verify everything still works:

```bash
# Clean build
swift package clean

# Build project
swift build

# Run tests
swift test

# Verify coverage is still >95%
swift test --enable-code-coverage
```

Expected result: All tests should pass with coverage remaining above 95%.

### Step 6: Update Documentation

Update the following documentation files to reflect x86-64 removal:

#### README.md

**Section: Requirements**
- Change "Platforms: Linux, macOS 12+ (Monterey), iOS 15+" to "Platforms: macOS 12+ (Monterey), iOS 15+ (Apple Silicon)"
- Remove any Linux x86-64 mentions

**Section: Architecture Overview**
- Remove `x86_64/` from the directory tree
- Update platform section

**Section: Hardware Targets** (if present)
- Remove "Secondary: x86-64 (Intel Macs, Linux)" line

#### MILESTONES.md

**Milestone 6 Section**:
- Change status from "Planned" or "Complete" to "Deprecated - Removed"
- Add removal date and version

**Summary Table**:
- Mark Milestone 6 as "Removed ❌" or update status appropriately

**Architecture Principles**:
- Remove "x86-64 Removability" principle (it's no longer needed)

**Hardware Targets**:
- Remove "Secondary: x86-64" line

### Step 7: Update Package.swift (If Needed)

Check if `Package.swift` has any x86-64-specific configurations:

```bash
grep -i "x86" Package.swift
```

If there are any x86-64-specific settings, remove them.

### Step 8: Final Verification

Perform a final comprehensive check:

```bash
# Search for any remaining x86-64 references
grep -r "x86_64\|x86-64\|X86_64" --include="*.swift" --include="*.md" .

# Verify no broken references
swift build

# Run full test suite
swift test

# Generate and review coverage report
swift test --enable-code-coverage
```

### Step 9: Commit Changes

Once everything is verified:

```bash
# Review changes
git status
git diff

# Stage changes
git add -A

# Commit with descriptive message
git commit -m "Remove x86-64 support - Apple Silicon only

- Removed Platform/x86_64/X86_64Accelerator.swift
- Updated PlatformProtocols.swift to remove x86-64 selection
- Removed x86-64 test cases from PlatformProtocolsTests
- Removed x86-64 benchmark cases from PlatformBenchmarks
- Updated documentation (README.md, MILESTONES.md)
- Maintained >95% test coverage
- All tests passing on ARM64 with scalar fallback

Project now targets Apple Silicon exclusively."

# Push changes
git push
```

## Impact Assessment

### What Remains After Removal

After x86-64 removal, the project will:
- ✅ Fully support Apple Silicon (ARM64) with NEON acceleration
- ✅ Maintain scalar fallback for any non-ARM64 platforms
- ✅ Retain >95% test coverage
- ✅ Keep all JPEG-LS encoding/decoding functionality
- ✅ Preserve Accelerate framework integration
- ✅ Maintain clean platform abstraction architecture

### What Is Lost

After removal:
- ❌ Native x86-64 SSE/AVX SIMD optimisations
- ❌ Intel Mac hardware acceleration
- ❌ Linux x86-64 performance optimisations
- ❌ Cross-platform benchmarking capabilities

On non-ARM64 platforms, the `ScalarAccelerator` will be used, which:
- Provides correct, reference implementation
- Has lower performance than SIMD-optimised versions
- Is fully tested and maintains correctness

### Performance Considerations

On Intel Macs after removal:
- The project will fall back to `ScalarAccelerator`
- Performance will be slower than with `X86_64Accelerator`
- Correctness is maintained (bit-exact results)
- Consider Rosetta 2 as an alternative for Intel Macs if ARM64 binary is used

## Verification Checklist

Before considering the removal complete, verify:

- [ ] `Sources/JPEGLS/Platform/x86_64/` directory deleted
- [ ] All `#elseif arch(x86_64)` conditionals removed from source
- [ ] All x86-64 test cases removed
- [ ] `swift build` succeeds with no warnings
- [ ] `swift test` passes all tests
- [ ] Code coverage remains >95%
- [ ] No references to "x86_64" or "x86-64" in code (except comments/docs noting removal)
- [ ] README.md updated
- [ ] MILESTONES.md updated
- [ ] This removal guide marked as completed
- [ ] Changes committed and pushed
- [ ] CI/CD pipeline passes

## Rollback Procedure

If removal needs to be reverted:

```bash
# Revert the commit
git revert <commit-hash>

# Or restore from git history
git checkout <commit-before-removal> -- Sources/JPEGLS/Platform/x86_64/
git checkout <commit-before-removal> -- Sources/JPEGLS/Core/PlatformProtocols.swift
git checkout <commit-before-removal> -- Tests/JPEGLSTests/PlatformProtocolsTests.swift
git checkout <commit-before-removal> -- Tests/JPEGLSTests/PlatformBenchmarks.swift

# Rebuild and test
swift build
swift test
```

## Alternative: Deprecation Without Removal

If complete removal is premature, consider deprecation instead:

1. Add deprecation warnings to `X86_64Accelerator`:
   ```swift
   @available(*, deprecated, message: "x86-64 support is deprecated and will be removed in a future version")
   public struct X86_64Accelerator: PlatformAccelerator {
       // ...
   }
   ```

2. Update documentation to note deprecation timeline

3. Continue maintaining x86-64 code until a specific version

4. Follow this guide for complete removal in the chosen future version

## Questions or Issues

If issues arise during removal:

1. Verify all tests pass before making changes
2. Make changes incrementally, testing after each step
3. Keep git history clean with atomic commits
4. Document any unexpected issues or deviations from this guide
5. Update this guide with lessons learned

## Completion

Once removal is complete, consider:
- Archiving this guide (move to `docs/archive/` or delete)
- Creating a tag for the "last x86-64 supported version"
- Updating release notes to inform users of the change
- Providing migration guidance for Intel Mac users

---

**Version**: 2.0  
**Last Updated**: 2026-03-01  
**Status**: Ready for use when x86-64 deprecation is scheduled
