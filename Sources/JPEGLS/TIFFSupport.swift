// TIFFSupport.swift
// Minimal pure-Swift Baseline TIFF encoder for writing greyscale and RGB images.
//
// Supports 8-bit and 16-bit samples for both greyscale (1 component) and RGB
// (3 components) images. Pixel data is stored without compression (TIFF
// Compression tag = 1), in a single strip, using chunky (interleaved) planar
// configuration. The output is a little-endian ('II') TIFF file readable by
// all conforming TIFF decoders.

import Foundation

// MARK: - TIFF Encoder Errors

/// Errors produced by the TIFF encoder.
public enum TIFFEncoderError: Error, CustomStringConvertible, Equatable {
    /// Image width or height is zero.
    case invalidDimensions
    /// Component count is not 1 (greyscale) or 3 (RGB).
    case unsupportedComponentCount(Int)
    /// `maxVal` is outside the range 1…65535.
    case invalidMaxVal

    public var description: String {
        switch self {
        case .invalidDimensions:
            return "TIFF encoder: width and height must be greater than zero"
        case .unsupportedComponentCount(let n):
            return "TIFF encoder: only 1 (greyscale) or 3 (RGB) components supported; got \(n)"
        case .invalidMaxVal:
            return "TIFF encoder: maxVal must be in the range 1…65535"
        }
    }
}

// MARK: - TIFF Encoder

/// Minimal Baseline TIFF file encoder supporting 8-bit and 16-bit greyscale and RGB images.
///
/// Produces valid Baseline TIFF files (little-endian, no compression, single strip,
/// chunky planar configuration). The output is readable by all conforming TIFF decoders.
///
/// **Usage example:**
/// ```swift
/// // Encode a 2×2 8-bit greyscale image.
/// let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
/// let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
/// ```
public enum TIFFSupport {

    // MARK: - Public API

    /// Encode pixel data as a Baseline TIFF file.
    ///
    /// - Parameters:
    ///   - componentPixels: Pixel data organised as `[component][row][column]` where
    ///     component count is 1 (greyscale) or 3 (RGB).
    ///   - width: Image width in pixels (must be > 0).
    ///   - height: Image height in pixels (must be > 0).
    ///   - maxVal: Maximum sample value; determines bit depth (≤255 → 8-bit, >255 → 16-bit).
    /// - Returns: Raw TIFF file data beginning with the standard 'II' little-endian header.
    /// - Throws: `TIFFEncoderError` if the parameters are invalid.
    public static func encode(
        componentPixels: [[[Int]]],
        width: Int,
        height: Int,
        maxVal: Int
    ) throws -> Data {
        guard width > 0, height > 0 else {
            throw TIFFEncoderError.invalidDimensions
        }
        let numComponents = componentPixels.count
        guard numComponents == 1 || numComponents == 3 else {
            throw TIFFEncoderError.unsupportedComponentCount(numComponents)
        }
        guard maxVal >= 1, maxVal <= 65535 else {
            throw TIFFEncoderError.invalidMaxVal
        }

        let bitsPerSample  = maxVal <= 255 ? 8 : 16
        let bytesPerSample = bitsPerSample == 16 ? 2 : 1

        // PhotometricInterpretation: 1 = BlackIsZero (greyscale), 2 = RGB.
        let photometric: UInt16 = numComponents == 3 ? 2 : 1

        // Build interleaved image data (chunky format, little-endian samples).
        var imageData = Data(capacity: height * width * numComponents * bytesPerSample)
        for row in 0..<height {
            for col in 0..<width {
                for comp in 0..<numComponents {
                    let val = componentPixels[comp][row][col]
                    if bytesPerSample == 2 {
                        // Little-endian 16-bit sample.
                        imageData.append(UInt8(val & 0xFF))
                        imageData.append(UInt8((val >> 8) & 0xFF))
                    } else {
                        imageData.append(UInt8(val & 0xFF))
                    }
                }
            }
        }

        // Layout plan:
        //   Offset 0:          8-byte TIFF header
        //   Offset 8:          IFD (2 + 10×12 + 4 = 126 bytes)
        //   Offset 134:        Extra data (BitsPerSample array for RGB: 3×SHORT = 6 bytes)
        //   Offset 134+extra:  Image data
        let numTags     = 10
        let ifdOffset   = 8
        let ifdSize     = 2 + numTags * 12 + 4   // count + entries + next-IFD pointer
        let extraOffset = ifdOffset + ifdSize

        // BitsPerSample for RGB requires 3 × SHORT (6 bytes) stored outside the IFD value field.
        var extraData = Data()
        var bpsSHORTOffset = 0
        if numComponents == 3 {
            bpsSHORTOffset = extraOffset
            extraData.tiffAppend16(UInt16(bitsPerSample))
            extraData.tiffAppend16(UInt16(bitsPerSample))
            extraData.tiffAppend16(UInt16(bitsPerSample))
        }

        let imageOffset = extraOffset + extraData.count

        // Assemble the TIFF file.
        var tiff = Data()

        // 8-byte TIFF header.
        tiff.append(0x49); tiff.append(0x49)  // 'II' — little-endian byte order
        tiff.tiffAppend16(42)                   // TIFF magic number
        tiff.tiffAppend32(UInt32(ifdOffset))    // offset to the first IFD

        // IFD entry count.
        tiff.tiffAppend16(UInt16(numTags))

        // IFD entries, sorted by tag number in ascending order (TIFF 6.0 §2).
        //   Tag 256 — ImageWidth (LONG).
        tiff.tiffEntry(tag: 256, type: 4, count: 1, value: UInt32(width))
        //   Tag 257 — ImageLength (LONG).
        tiff.tiffEntry(tag: 257, type: 4, count: 1, value: UInt32(height))
        //   Tag 258 — BitsPerSample (SHORT, 1 or 3 values).
        if numComponents == 1 {
            tiff.tiffEntry(tag: 258, type: 3, count: 1, value: UInt32(bitsPerSample))
        } else {
            // count > 1: value field holds the offset to the BitsPerSample SHORT array.
            tiff.tiffEntry(tag: 258, type: 3, count: UInt32(numComponents),
                           value: UInt32(bpsSHORTOffset))
        }
        //   Tag 259 — Compression: 1 = NoCompression.
        tiff.tiffEntry(tag: 259, type: 3, count: 1, value: 1)
        //   Tag 262 — PhotometricInterpretation.
        tiff.tiffEntry(tag: 262, type: 3, count: 1, value: UInt32(photometric))
        //   Tag 273 — StripOffsets (single strip, LONG).
        tiff.tiffEntry(tag: 273, type: 4, count: 1, value: UInt32(imageOffset))
        //   Tag 277 — SamplesPerPixel (SHORT).
        tiff.tiffEntry(tag: 277, type: 3, count: 1, value: UInt32(numComponents))
        //   Tag 278 — RowsPerStrip (entire image as one strip, LONG).
        tiff.tiffEntry(tag: 278, type: 4, count: 1, value: UInt32(height))
        //   Tag 279 — StripByteCounts (LONG).
        tiff.tiffEntry(tag: 279, type: 4, count: 1, value: UInt32(imageData.count))
        //   Tag 284 — PlanarConfiguration: 1 = Chunky (interleaved).
        tiff.tiffEntry(tag: 284, type: 3, count: 1, value: 1)

        // Next-IFD pointer: 0 (no additional IFDs).
        tiff.tiffAppend32(0)

        // Extra data (BitsPerSample array for RGB) followed by image data.
        tiff.append(extraData)
        tiff.append(imageData)

        return tiff
    }
}

// MARK: - Data helpers (file-private)

private extension Data {
    /// Append a 16-bit value in little-endian byte order.
    mutating func tiffAppend16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    /// Append a 32-bit value in little-endian byte order.
    mutating func tiffAppend32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    /// Append a 12-byte IFD entry.
    ///
    /// - Parameters:
    ///   - tag:   TIFF tag identifier.
    ///   - type:  Data type (3 = SHORT, 4 = LONG).
    ///   - count: Number of values.
    ///   - value: For a single SHORT (count == 1, type == 3) this is the 2-byte sample value,
    ///            stored left-aligned in the 4-byte value field. For LONG values or for
    ///            multi-value SHORT entries, this is either the inline value or the byte
    ///            offset to the data.
    mutating func tiffEntry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) {
        tiffAppend16(tag)
        tiffAppend16(type)
        tiffAppend32(count)
        if type == 3 && count == 1 {
            // Single SHORT: place the 2-byte value in the first 2 bytes of the field.
            tiffAppend16(UInt16(value & 0xFFFF))
            tiffAppend16(0)  // padding
        } else {
            // LONG value or offset to multi-value SHORT data.
            tiffAppend32(value)
        }
    }
}
