// PNGSupport.swift
// Minimal pure-Swift PNG encoder for writing greyscale and RGB images.
//
// Supports 8-bit and 16-bit samples for both greyscale (1 component) and RGB
// (3 components) images. Pixel data in the IDAT stream is wrapped in a valid
// zlib stream using uncompressed (stored) DEFLATE blocks, making the output
// compatible with all standard PNG decoders without requiring a compression
// library.

import Foundation

// MARK: - PNG Encoder Errors

/// Errors produced by the PNG encoder.
public enum PNGEncoderError: Error, CustomStringConvertible, Equatable {
    /// Image width or height is zero.
    case invalidDimensions
    /// Component count is not 1 (greyscale) or 3 (RGB).
    case unsupportedComponentCount(Int)
    /// `maxVal` is outside the range 1…65535.
    case invalidMaxVal

    public var description: String {
        switch self {
        case .invalidDimensions:
            return "PNG encoder: width and height must be greater than zero"
        case .unsupportedComponentCount(let n):
            return "PNG encoder: only 1 (greyscale) or 3 (RGB) components supported; got \(n)"
        case .invalidMaxVal:
            return "PNG encoder: maxVal must be in the range 1…65535"
        }
    }
}

// MARK: - PNG Encoder

/// Minimal PNG file encoder supporting 8-bit and 16-bit greyscale and RGB images.
///
/// Produces valid PNG files using uncompressed (stored) DEFLATE blocks wrapped in a
/// standard zlib container. The output is readable by all conforming PNG decoders.
///
/// **Usage example:**
/// ```swift
/// // Encode a 2×2 8-bit greyscale image.
/// let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
/// let pngData = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
/// ```
public enum PNGSupport {

    // MARK: - Public API

    /// Encode pixel data as a PNG file.
    ///
    /// - Parameters:
    ///   - componentPixels: Pixel data organised as `[component][row][column]` where
    ///     component count is 1 (greyscale) or 3 (RGB).
    ///   - width: Image width in pixels (must be > 0).
    ///   - height: Image height in pixels (must be > 0).
    ///   - maxVal: Maximum sample value; determines bit depth (≤255 → 8-bit, >255 → 16-bit).
    /// - Returns: Raw PNG file data beginning with the standard 8-byte PNG signature.
    /// - Throws: `PNGEncoderError` if the parameters are invalid.
    public static func encode(
        componentPixels: [[[Int]]],
        width: Int,
        height: Int,
        maxVal: Int
    ) throws -> Data {
        guard width > 0, height > 0 else {
            throw PNGEncoderError.invalidDimensions
        }
        let numComponents = componentPixels.count
        guard numComponents == 1 || numComponents == 3 else {
            throw PNGEncoderError.unsupportedComponentCount(numComponents)
        }
        guard maxVal >= 1, maxVal <= 65535 else {
            throw PNGEncoderError.invalidMaxVal
        }

        let bitDepth: UInt8  = maxVal <= 255 ? 8 : 16
        let colorType: UInt8 = numComponents == 3 ? 2 : 0   // 2 = RGB, 0 = Greyscale
        let bytesPerSample   = bitDepth == 16 ? 2 : 1

        // Build IHDR data (13 bytes per PNG specification).
        var ihdr = Data(capacity: 13)
        ihdr.pngAppend32(UInt32(width))
        ihdr.pngAppend32(UInt32(height))
        ihdr.append(bitDepth)   // bit depth
        ihdr.append(colorType)  // colour type
        ihdr.append(0)          // compression method (always 0 = deflate)
        ihdr.append(0)          // filter method (always 0)
        ihdr.append(0)          // interlace method (0 = no interlace)

        // Build the raw scanline buffer.
        // Each row begins with a single filter-type byte (0 = None) followed by
        // width × numComponents × bytesPerSample pixel bytes.
        let rowStride = 1 + width * numComponents * bytesPerSample
        var scanlines = Data(capacity: height * rowStride)
        for row in 0..<height {
            scanlines.append(0)  // filter type: None
            for col in 0..<width {
                for comp in 0..<numComponents {
                    let val = componentPixels[comp][row][col]
                    if bytesPerSample == 2 {
                        scanlines.append(UInt8((val >> 8) & 0xFF))
                        scanlines.append(UInt8(val & 0xFF))
                    } else {
                        scanlines.append(UInt8(val & 0xFF))
                    }
                }
            }
        }

        // Wrap scanlines in a zlib stream (stored / no-compression DEFLATE).
        let idat = makeZlibStored(scanlines)

        // Assemble the final PNG file.
        var png = Data(capacity: 8 + 25 + (12 + idat.count) + 12)
        // PNG file signature.
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.pngAppendChunk(type: "IHDR", data: ihdr)
        png.pngAppendChunk(type: "IDAT", data: idat)
        png.pngAppendChunk(type: "IEND", data: Data())

        return png
    }

    // MARK: - Internal Helpers (internal for testability)

    /// Wrap `payload` in a zlib stream using stored (no-compression) DEFLATE blocks.
    ///
    /// The output is a valid zlib stream (CMF + FLG + DEFLATE blocks + Adler-32),
    /// suitable for use as PNG IDAT chunk data.
    static func makeZlibStored(_ payload: Data) -> Data {
        // zlib header:
        //   CMF = 0x78: deflate method (CM=8), window size 32768 (CINFO=7)
        //   FLG = 0x01: no preset dictionary; (0x78*256 + 0x01) = 30721 which is 31×991 ✓
        var out = Data()
        out.append(0x78)
        out.append(0x01)

        // Emit DEFLATE stored blocks (BTYPE=00). Each block holds at most 65535 bytes.
        let total = payload.count
        var offset = 0
        repeat {
            let remaining = total - offset
            let blockLen  = min(remaining, 65535)
            let isLast    = (offset + blockLen >= total)

            // BFINAL | BTYPE: bit 0 = isFinal, bits 1-2 = 00 (stored)
            out.append(isLast ? 0x01 : 0x00)

            // LEN and NLEN (one's complement of LEN), both little-endian.
            let len  = UInt16(blockLen)
            let nlen = ~len
            out.append(UInt8(len  & 0xFF))
            out.append(UInt8(len  >> 8))
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8(nlen >> 8))

            if blockLen > 0 {
                out.append(contentsOf: payload[offset ..< (offset + blockLen)])
            }
            offset += blockLen
        } while offset < total

        // Adler-32 checksum over the uncompressed data (big-endian per zlib spec).
        out.pngAppend32(adler32(payload))
        return out
    }

    /// Compute an Adler-32 checksum (as defined in RFC 1950 §8.2).
    static func adler32(_ data: Data) -> UInt32 {
        let mod: UInt32 = 65521
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        for byte in data {
            s1 = (s1 + UInt32(byte)) % mod
            s2 = (s2 + s1) % mod
        }
        return (s2 << 16) | s1
    }

    /// Compute a CRC-32 checksum using the standard PNG/IEEE 802.3 polynomial
    /// (reflected form 0xEDB88320).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var v = UInt32(byte) ^ (crc & 0xFF)
            for _ in 0..<8 {
                v = (v & 1) == 1 ? (v >> 1) ^ 0xEDB8_8320 : v >> 1
            }
            crc = v ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Data helpers (file-private)

private extension Data {
    /// Append a 32-bit value in big-endian byte order.
    mutating func pngAppend32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >>  8) & 0xFF))
        append(UInt8( value        & 0xFF))
    }

    /// Append a PNG chunk: 4-byte length + 4-byte type + data + 4-byte CRC.
    mutating func pngAppendChunk(type: String, data chunkData: Data) {
        pngAppend32(UInt32(chunkData.count))
        let typeBytes = Data(type.utf8)
        append(typeBytes)
        append(chunkData)
        var crcInput = typeBytes
        crcInput.append(chunkData)
        pngAppend32(PNGSupport.crc32(crcInput))
    }
}
