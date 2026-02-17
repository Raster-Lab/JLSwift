# JPEG-LS Decoder Bug Investigation

## Summary
The JPEG-LS decoder has multiple bugs that have been partially fixed, but round-trip encode/decode still fails.

## Bugs Fixed

### 1. LSE Preset Parameters Length Check
**File**: `Sources/JPEGLS/Decoder/JPEGLSParser.swift` line 379
**Issue**: Check was for length == 13, should be length == 11
**Status**: ✅ FIXED

### 2. Interleaved Mode Context Sharing
**Files**: `Sources/JPEGLS/JPEGLSDecoder.swift` lines 265-310 (sample-interleaved), 208-246 (line-interleaved)
**Issue**: Decoder created separate contexts per component in interleaved modes, but encoder uses single shared context
**Impact**: Sample-interleaved and line-interleaved modes would decode incorrectly
**Status**: ✅ FIXED

### 3. Encoder Context Model Near Parameter
**File**: `Sources/JPEGLS/JPEGLSEncoder.swift` line 281
**Issue**: Encoder didn't pass `near` parameter when creating context model
**Status**: ✅ FIXED

## Remaining Bug

### Symptom
- First pixel (0,0) decodes correctly
- Subsequent pixels drift increasingly from expected values
- Error accumulates across the image
- Affects ALL interleave modes (none, line, sample)

### Analysis
The issue suggests:
1. Context updates may have incorrect formula
2. Bias correction may be applied incorrectly
3. Error sign handling may need adjustment per ITU-T.87 Section 4.4.1

### What's Been Ruled Out
- ✅ Gradient computation (identical in encoder/decoder)
- ✅ Gradient quantization (identical in encoder/decoder) 
- ✅ Error mapping/unmapping (confirmed to be exact inverses)
- ✅ Neighbor pixel boundaries (correct per ITU-T.87)
- ✅ Context B initialization (spec says 0, not 1)
- ✅ Bitstream byte stuffing (handled correctly)

### Next Steps
1. Create minimal 2-pixel test case to isolate exact divergence point
2. Compare encoded bitstream byte-by-byte with reference implementation
3. Verify context update formula against ITU-T.87 Section 4.3.3
4. Check if error sign negation based on context sign is needed (ITU-T.87 Section 4.4.1)

