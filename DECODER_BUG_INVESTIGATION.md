# JPEG-LS Decoder Bug Investigation

## Summary
The JPEG-LS decoder had a critical Golomb-Rice encoding off-by-one bug that caused pixel value drift during round-trip encode/decode. **This bug has been fixed.**

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

### 4. Golomb-Rice Encoding Off-By-One (Root Cause)
**File**: `Sources/JPEGLS/Encoder/JPEGLSRegularMode.swift` line 241
**Issue**: `golombEncode` computed `unaryLength = quotient + 1`, but `writeRegularModeBits` treated `unaryLength` as the number of zero bits and wrote a separate terminating 1 bit. This caused every Golomb code to have one extra zero bit, making the decoder read wrong mapped error values.
**Impact**: ALL decoded pixel values were wrong (the first pixel could decode as 255 instead of 0). Error accumulated across the entire image.
**Fix**: Changed `unaryLength = quotient` (number of zero bits only). Updated `totalBitLength` to `unaryLength + 1 + golombK`.
**Status**: ✅ FIXED

### 5. Decoder Golomb Unary Prefix Limit
**File**: `Sources/JPEGLS/JPEGLSDecoder.swift`
**Issue**: Hardcoded limit of 1000 on unary prefix was too small for 16-bit images (where mapped errors can be up to 131070)
**Fix**: Increased limit to 200000
**Status**: ✅ FIXED

### 6. Parser Test LSE Length Mismatch
**File**: `Tests/JPEGLSTests/JPEGLSParserTests.swift` line 173
**Issue**: Test constructed LSE segment with length 13 but parser expected 11 (matching encoder)
**Fix**: Updated test to use length 11
**Status**: ✅ FIXED

## Remaining Known Limitation

### Near-Lossless Round-Trip
**Status**: ⚠️ NOT YET IMPLEMENTED
**Cause**: The encoder's `JPEGLSRegularMode.encodePixel` does not quantize prediction errors by `(2*NEAR+1)` or track reconstructed pixel values. Near-lossless encoding requires:
1. Error quantization: `Errval = Errval / (2*NEAR + 1)`
2. Reconstructed value tracking: `Rx = Px' + Errval_quantized * (2*NEAR + 1)`
3. Using reconstructed values (not original) for subsequent predictions

This is a known encoder limitation documented in MILESTONES.md. Lossless mode (NEAR=0) works correctly for all image types and interleaving modes.

