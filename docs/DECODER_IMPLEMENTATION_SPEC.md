# JPEG-LS Decoder Implementation Specification

## Executive Summary

This document provides a comprehensive specification for implementing the high-level `JPEGLSDecoder` API to complete Phase 7.1 of the JLSwift project. The decoder will enable end-to-end decoding of JPEG-LS encoded data to raw pixel arrays, complementing the existing `JPEGLSEncoder`.

## Current State

### ✅ Completed Components

| Component | File | Functionality |
|-----------|------|---------------|
| **JPEGLSParser** | `Decoder/JPEGLSParser.swift` | Parses JPEG-LS file structure (SOI, SOF, SOS, LSE, EOI markers) |
| **JPEGLSRegularModeDecoder** | `Decoder/JPEGLSRegularModeDecoder.swift` | Mathematical operations for regular mode pixel reconstruction |
| **JPEGLSRunModeDecoder** | `Decoder/JPEGLSRunModeDecoder.swift` | Run-length decoding for flat regions |
| **JPEGLSBitstreamReader** | `Core/JPEGLSBitstreamReader.swift` | Bit-level reading with byte stuffing handling |
| **JPEGLSContextModel** | `Core/JPEGLSContextModel.swift` | Adaptive context statistics |
| **JPEGLSEncoder** | `JPEGLSEncoder.swift` | Complete high-level encoding API (reference implementation) |

### ⚠️ Incomplete/Missing Components

1. **High-Level Decoder API**: No `JPEGLSDecoder` struct analogous to `JPEGLSEncoder`
2. **Scan Data Extraction**: Parser skips over actual encoded bitstream
3. **Pixel Decoding Loop**: No orchestration of decoder components with bitstream
4. **Golomb-Rice Reading**: No integration between bitstream reader and decoder math
5. **Neighbour Management**: No tracking of reconstructed pixels during decoding
6. **Interleaving Support**: MultiComponentDecoder only validates, doesn't decode

## Implementation Requirements

### 1. High-Level JPEGLSDecoder API

**File**: `Sources/JPEGLS/JPEGLSDecoder.swift`

```swift
/// High-level JPEG-LS decoder
///
/// Decodes JPEG-LS encoded data to multi-component image data per ITU-T.87.
/// Supports all decoding modes (lossless, near-lossless) and interleaving modes.
///
/// **Example usage:**
/// ```swift
/// let decoder = JPEGLSDecoder()
/// let imageData = try decoder.decode(jpegLSData)
/// let pixels = imageData.components[0].pixels
/// ```
public struct JPEGLSDecoder: Sendable {
    public init() {}
    
    /// Decode JPEG-LS data to pixel data
    ///
    /// - Parameter data: JPEG-LS encoded data
    /// - Returns: Decoded multi-component image data
    /// - Throws: `JPEGLSError` if decoding fails
    public func decode(_ data: Data) throws -> MultiComponentImageData
}
```

**Key Responsibilities:**
- Parse JPEG-LS structure using `JPEGLSParser`
- Extract scan data from bitstream
- Orchestrate pixel-by-pixel decoding
- Manage component interleaving
- Apply inverse colour transformations
- Return reconstructed pixel data

### 2. Scan Data Extraction

The parser currently skips over scan data (lines 167-192 in `JPEGLSParser.swift`). Need to:

**Option A: Modify Parser**
- Add `scanData: [Data]` field to `JPEGLSParseResult`
- Capture bytes between SOS marker and next marker for each scan

**Option B: Separate Extractor**
- Create `JPEGLSScanDataExtractor` class
- Takes parsed result + raw data
- Returns array of scan data buffers

**Recommended**: Option B (cleaner separation of concerns)

### 3. Golomb-Rice Code Reading

**Requirements:**
- Read unary prefix (count zeros until 1)
- Read k remainder bits
- Decode to mapped error value

**Implementation**:

```swift
private func readGolombCode(reader: JPEGLSBitstreamReader, k: Int) throws -> Int {
    // Read unary prefix (number of zeros before 1)
    var unaryCount = 0
    while try reader.readBits(1) == 0 {
        unaryCount += 1
        // Limit check to prevent infinite loop on corrupted data
        guard unaryCount < 1000 else {
            throw JPEGLSError.decodingFailed(reason: "Excessive unary prefix")
        }
    }
    
    // Read k remainder bits
    let remainder = k > 0 ? Int(try reader.readBits(k)) : 0
    
    // Compute mapped error: quotient * (1 << k) + remainder
    return (unaryCount << k) | remainder
}
```

### 4. Pixel Decoding Loop

**For Non-Interleaved Mode (one component per scan):**

```swift
private func decodeNoneInterleaved(
    scanData: Data,
    componentId: UInt8,
    width: Int,
    height: Int,
    scanHeader: JPEGLSScanHeader,
    parameters: JPEGLSPresetParameters
) throws -> [[Int]] {
    let reader = JPEGLSBitstreamReader(data: scanData)
    let decoder = try JPEGLSRegularModeDecoder(parameters: parameters, near: scanHeader.near)
    let runDecoder = try JPEGLSRunModeDecoder(parameters: parameters, near: scanHeader.near)
    var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
    
    // Initialize pixel buffer
    var pixels = Array(repeating: Array(repeating: 0, count: width), count: height)
    
    // Decode pixels in raster order
    for row in 0..<height {
        for col in 0..<width {
            // Get neighbor pixels (handle boundaries)
            let (a, b, c) = getNeighbors(pixels: pixels, row: row, col: col)
            
            // Compute gradients
            let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c)
            
            // Check for run mode
            if d1 == 0 && d2 == 0 && d3 == 0 {
                // Run mode decoding
                let runLength = try readRunLength(reader: reader, runDecoder: runDecoder, context: &context)
                let runValue = a  // Run continues with value 'a'
                
                // Fill run pixels
                for i in 0..<runLength {
                    if col + i < width {
                        pixels[row][col + i] = runValue
                    }
                }
                
                // Handle run interruption if needed
                if col + runLength < width {
                    let interruptionSample = try runDecoder.decodeRunInterruption(...)
                    pixels[row][col + runLength] = interruptionSample
                }
                
                col += runLength  // Skip ahead
                
            } else {
                // Regular mode decoding
                let (q1, q2, q3) = quantizeGradients(d1, d2, d3, decoder: decoder)
                let contextIndex = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
                let k = context.computeGolombParameter(contextIndex: contextIndex)
                
                // Read Golomb-Rice encoded error
                let mappedError = try readGolombCode(reader: reader, k: k)
                
                // Decode pixel
                let decodedPixel = decoder.decodePixel(
                    mappedError: mappedError,
                    a: a, b: b, c: c,
                    context: context
                )
                
                // Store reconstructed sample
                pixels[row][col] = decodedPixel.sample
                
                // Update context
                context.updateContext(
                    contextIndex: contextIndex,
                    error: decodedPixel.error,
                    sign: decodedPixel.sign
                )
            }
        }
    }
    
    return pixels
}
```

### 5. Neighbour Pixel Management

```swift
private func getNeighbors(
    pixels: [[Int]],
    row: Int,
    col: Int
) -> (a: Int, b: Int, c: Int) {
    // Handle boundary conditions per ITU-T.87 Section 3.2
    
    if row == 0 && col == 0 {
        // First pixel: all neighbors are 0
        return (0, 0, 0)
    } else if row == 0 {
        // First row: use left pixel for all
        let left = pixels[row][col - 1]
        return (left, left, left)
    } else if col == 0 {
        // First column: use top pixel for all
        let top = pixels[row - 1][col]
        return (top, top, top)
    } else {
        // General case
        let a = pixels[row][col - 1]      // Left
        let b = pixels[row - 1][col]      // Top
        let c = pixels[row - 1][col - 1]  // Top-left
        return (a, b, c)
    }
}
```

### 6. Interleaving Support

**Line-Interleaved:**
- Decode all components of row 0, then row 1, etc.
- For each row: iterate through components, then columns

**Sample-Interleaved:**
- Decode pixels in order: comp0[0,0], comp1[0,0], comp2[0,0], comp0[0,1], ...
- Neighbours must be from the same component

### 7. Run Mode Decoding

**Key Challenges:**
- Detect run sequences (d1=d2=d3=0)
- Read run-length limit encoded value
- Handle run interruption samples
- Update run index adaptation

**Reference**: `JPEGLSRunModeDecoder` has all math; just needs bitstream integration.

### 8. Colour Transformation

After decoding, apply inverse colour transformation if specified:
- HP1: Y → RGB
- HP2: Ls-Rs → RGB
- HP3: YCbCr → RGB

Code already exists in `JPEGLSMultiComponentDecoder` (lines 219-326).

## Testing Strategy

### Unit Tests

1. **Scan Data Extraction**
   - Test extraction of single scan
   - Test extraction of multiple scans
   - Test handling of application markers between scans

2. **Golomb-Rice Reading**
   - Test reading codes with k=0, k=1, k=5
   - Test various unary lengths
   - Test boundary conditions

3. **Pixel Decoding**
   - Test flat regions (run mode)
   - Test gradual transitions (regular mode)
   - Test sharp edges
   - Test boundary pixels (first row/column)

### Integration Tests

4. **Round-Trip Tests**
   ```swift
   let original = MultiComponentImageData.grayscale(pixels: testPixels, bitsPerSample: 8)
   let encoder = JPEGLSEncoder()
   let encoded = try encoder.encode(original, near: 0, interleaveMode: .none)
   
   let decoder = JPEGLSDecoder()
   let decoded = try decoder.decode(encoded)
   
   // Verify pixel-perfect match
   for row in 0..<height {
       for col in 0..<width {
           #expect(decoded.components[0].pixels[row][col] == original.components[0].pixels[row][col])
       }
   }
   ```

5. **CharLS Conformance**
   - Decode CharLS reference files
   - Compare with reference images
   - Validate against known checksums

### Performance Tests

6. **Benchmark Decoding Speed**
   - Various image sizes (256x256 to 4096x4096)
   - Different bit depths (8, 12, 16-bit)
   - Lossless vs near-lossless
   - Interleaving modes

## Implementation Phases

### Phase 1: Foundation (Estimated: 3-4 hours)
- [ ] Create `JPEGLSDecoder` struct with basic structure
- [ ] Implement scan data extraction
- [ ] Add simple tests for extraction

### Phase 2: Regular Mode Decoding (Estimated: 4-6 hours)
- [ ] Implement Golomb-Rice code reading
- [ ] Implement pixel decoding loop for regular mode only
- [ ] Handle neighbour pixels correctly
- [ ] Add tests for flat and gradient images

### Phase 3: Run Mode Support (Estimated: 2-3 hours)
- [ ] Integrate run mode decoder
- [ ] Implement run-length reading
- [ ] Handle run interruptions
- [ ] Add tests for flat regions

### Phase 4: Multi-Component (Estimated: 3-4 hours)
- [ ] Implement non-interleaved decoding (separate scans)
- [ ] Implement line-interleaved decoding
- [ ] Implement sample-interleaved decoding
- [ ] Add RGB tests

### Phase 5: Integration & Testing (Estimated: 4-5 hours)
- [ ] Round-trip tests (encode → decode → verify)
- [ ] CharLS conformance tests
- [ ] Error handling and edge cases
- [ ] Performance benchmarks

### Phase 6: CLI Integration (Estimated: 1-2 hours)
- [ ] Update `DecodeCommand.swift` to use `JPEGLSDecoder`
- [ ] Test CLI decode command end-to-end
- [ ] Update documentation

**Total Estimated Effort**: 17-24 hours of focused development

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Golomb-Rice code reading bugs | High | Extensive unit tests, comparison with encoder output |
| Context synchronization errors | High | Step-by-step verification against encoder |
| Neighbour pixel tracking bugs | Medium | Comprehensive boundary condition tests |
| Performance issues | Medium | Benchmark early, optimise incrementally |
| CharLS incompatibility | Low | Parser already handles CharLS extensions |

## Success Criteria

1. ✅ `JPEGLSDecoder` API matches `JPEGLSEncoder` in simplicity
2. ✅ Round-trip tests pass: encode → decode → pixel-perfect match
3. ✅ All CharLS reference files decode correctly
4. ✅ >95% test coverage maintained
5. ✅ CLI `decode` command works end-to-end
6. ✅ Documentation updated (README.md, MILESTONES.md)
7. ✅ Performance acceptable (within 2x of encoder speed)

## References

- ITU-T.87 (ISO/IEC 14495-1:1999): JPEG-LS standard
- `Sources/JPEGLS/JPEGLSEncoder.swift`: Reference implementation for encoding
- `Sources/JPEGLS/Decoder/`: Existing decoder math components
- CharLS project: Reference implementation and test files

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-17  
**Status**: Ready for Implementation
