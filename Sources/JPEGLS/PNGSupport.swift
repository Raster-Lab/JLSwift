// PNGSupport.swift
// Minimal pure-Swift PNG encoder and decoder for greyscale and RGB images.
//
// Encoder: supports 8-bit and 16-bit samples for both greyscale (1 component) and RGB
// (3 components) images. Pixel data in the IDAT stream is wrapped in a valid
// zlib stream using uncompressed (stored) DEFLATE blocks, making the output
// compatible with all standard PNG decoders without requiring a compression
// library.
//
// Decoder: supports 8-bit and 16-bit greyscale and RGB PNG files using uncompressed
// (stored) DEFLATE blocks and filter type 0 (None). This covers all PNG files
// produced by the encoder above; compressed PNGs from other tools are not supported.

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

    /// Returns `true` if `data` begins with the standard 8-byte PNG signature.
    ///
    /// Use this to detect PNG input before attempting to decode.
    public static func isPNG(_ data: Data) -> Bool {
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= 8 && Array(data.prefix(8)) == sig
    }

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
        // zlib header (RFC 1950 §2.2):
        //   CMF = 0x78: deflate method (CM=8), window size 32768 (CINFO=7)
        //   FLG = 0x01: no preset dictionary, compression level 0 (fastest)
        //   The FCHECK field in FLG must be chosen so that (CMF*256 + FLG) % 31 == 0:
        //   0x78*256 = 30720; 30720 % 31 = 30; FLG must satisfy FLG % 31 = 1 → FLG = 0x01.
        //   Verification: (0x78*256 + 0x01) = 30721 = 31 × 991, so 30721 % 31 = 0. ✓
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

// MARK: - PNG Decoder Errors

/// Errors produced by the PNG decoder.
public enum PNGDecoderError: Error, CustomStringConvertible, Equatable {
    /// The file does not begin with the standard 8-byte PNG signature.
    case invalidSignature
    /// No IHDR chunk was found.
    case missingIHDR
    /// Bit depth is not 8 or 16.
    case unsupportedBitDepth(UInt8)
    /// Colour type is not 0 (greyscale) or 2 (RGB).
    case unsupportedColorType(UInt8)
    /// Interlaced PNG files are not supported.
    case interlacedNotSupported
    /// No IDAT chunk was found.
    case missingIDAT
    /// The zlib header is malformed.
    case invalidZlibStream
    /// A DEFLATE block type other than 00 (stored) was encountered.
    case unsupportedDEFLATEBlockType(UInt8)
    /// A scanline filter type other than 0 (None) was encountered.
    case unsupportedFilterType(UInt8)
    /// The pixel data is shorter than expected.
    case truncatedData

    public var description: String {
        switch self {
        case .invalidSignature:
            return "PNG decoder: file does not begin with the PNG signature"
        case .missingIHDR:
            return "PNG decoder: no IHDR chunk found"
        case .unsupportedBitDepth(let d):
            return "PNG decoder: unsupported bit depth \(d) — only 8 and 16 are supported"
        case .unsupportedColorType(let t):
            return "PNG decoder: unsupported colour type \(t) — only 0 (greyscale) and 2 (RGB) are supported"
        case .interlacedNotSupported:
            return "PNG decoder: interlaced PNG files are not supported"
        case .missingIDAT:
            return "PNG decoder: no IDAT chunk found"
        case .invalidZlibStream:
            return "PNG decoder: invalid zlib stream header"
        case .unsupportedDEFLATEBlockType(let t):
            return "PNG decoder: unsupported DEFLATE block type \(t) — only stored (type 0) is supported; " +
                   "use uncompressed PNG output from this tool or convert with an external tool"
        case .unsupportedFilterType(let f):
            return "PNG decoder: unsupported scanline filter type \(f) — only type 0 (None) is supported"
        case .truncatedData:
            return "PNG decoder: pixel data is shorter than expected"
        }
    }
}

// MARK: - PNG Decoder

/// A decoded PNG image.
public struct PNGImage: Sendable {
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Bit depth per sample (8 or 16).
    public let bitDepth: Int
    /// Pixel data organised as `[component][row][column]`.
    /// Component count is 1 for greyscale or 3 for RGB.
    public let componentPixels: [[[Int]]]

    /// Maximum sample value (255 for 8-bit, 65535 for 16-bit).
    public var maxVal: Int { (1 << bitDepth) - 1 }
}

extension PNGSupport {

    // MARK: - Public Decode API

    /// Decode a PNG file into component pixel arrays.
    ///
    /// Only uncompressed (stored-DEFLATE, BTYPE=00) PNG files with filter type 0 (None)
    /// are supported. This covers all PNG files produced by `PNGSupport.encode(...)`.
    ///
    /// - Parameter data: Raw PNG file bytes.
    /// - Returns: A `PNGImage` containing dimensions, bit depth, and pixel data.
    /// - Throws: `PNGDecoderError` if the file is invalid or uses unsupported features.
    ///
    /// **Usage example:**
    /// ```swift
    /// let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
    /// let pngData = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
    /// let image = try PNGSupport.decode(pngData)
    /// // image.componentPixels[0][0][0] == 10
    /// ```
    public static func decode(_ data: Data) throws -> PNGImage {
        // Verify PNG signature (8 bytes).
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 8, Array(data.prefix(8)) == signature else {
            throw PNGDecoderError.invalidSignature
        }

        // Parse chunks.
        var offset = 8
        var width  = 0
        var height = 0
        var bitDepth:  UInt8 = 0
        var colorType: UInt8 = 0
        var foundIHDR = false
        var idatData  = Data()

        while offset + 12 <= data.count {
            let chunkLength = Int(readBE32(data, at: offset));   offset += 4
            let typeBytes   = data[offset ..< offset + 4];       offset += 4
            let chunkType   = String(bytes: typeBytes, encoding: .ascii) ?? ""
            let chunkEnd    = offset + chunkLength

            switch chunkType {
            case "IHDR":
                guard chunkLength == 13 else { throw PNGDecoderError.missingIHDR }
                width      = Int(readBE32(data, at: offset))
                height     = Int(readBE32(data, at: offset + 4))
                bitDepth   = data[offset + 8]
                colorType  = data[offset + 9]
                let interlace = data[offset + 12]
                foundIHDR = true
                guard bitDepth == 8 || bitDepth == 16 else {
                    throw PNGDecoderError.unsupportedBitDepth(bitDepth)
                }
                guard colorType == 0 || colorType == 2 else {
                    throw PNGDecoderError.unsupportedColorType(colorType)
                }
                guard interlace == 0 else {
                    throw PNGDecoderError.interlacedNotSupported
                }
            case "IDAT":
                if chunkEnd <= data.count {
                    idatData.append(data[offset ..< chunkEnd])
                }
            case "IEND":
                break
            default:
                break  // Ignore ancillary and unknown chunks.
            }

            offset = chunkEnd + 4  // Skip chunk data + 4-byte CRC.
        }

        guard foundIHDR else { throw PNGDecoderError.missingIHDR }
        guard !idatData.isEmpty else { throw PNGDecoderError.missingIDAT }

        // Decompress the concatenated IDAT data (zlib stream with stored DEFLATE blocks).
        let scanlines = try inflateStored(idatData)

        // Reconstruct pixels from filtered scanlines.
        let numComponents = colorType == 2 ? 3 : 1
        let bytesPerSample = bitDepth == 16 ? 2 : 1
        let rowStride = 1 + width * numComponents * bytesPerSample

        guard scanlines.count >= height * rowStride else {
            throw PNGDecoderError.truncatedData
        }

        var componentPixels = Array(
            repeating: Array(repeating: Array(repeating: 0, count: width), count: height),
            count: numComponents
        )

        for row in 0..<height {
            let rowStart = row * rowStride
            let filterType = scanlines[rowStart]
            guard filterType == 0 else {
                throw PNGDecoderError.unsupportedFilterType(filterType)
            }
            let pixelStart = rowStart + 1

            for col in 0..<width {
                for comp in 0..<numComponents {
                    let byteOffset = pixelStart + (col * numComponents + comp) * bytesPerSample
                    if bytesPerSample == 2 {
                        let hi = Int(scanlines[byteOffset])
                        let lo = Int(scanlines[byteOffset + 1])
                        componentPixels[comp][row][col] = (hi << 8) | lo
                    } else {
                        componentPixels[comp][row][col] = Int(scanlines[byteOffset])
                    }
                }
            }
        }

        return PNGImage(
            width: width,
            height: height,
            bitDepth: Int(bitDepth),
            componentPixels: componentPixels
        )
    }

    // MARK: - Internal Decode Helpers

    /// Decompress a zlib stream that uses only stored (BTYPE=00) DEFLATE blocks.
    static func inflateStored(_ data: Data) throws -> Data {
        guard data.count >= 2 else { throw PNGDecoderError.invalidZlibStream }

        // Validate zlib CMF/FLG header: (CMF * 256 + FLG) % 31 must be 0.
        let cmf = UInt32(data[0])
        let flg = UInt32(data[1])
        guard (cmf * 256 + flg) % 31 == 0 else {
            throw PNGDecoderError.invalidZlibStream
        }
        // Bit 5 of FLG is the FDICT flag; a preset dictionary is not supported here
        // but we do not strictly need to reject it for stored blocks.

        var pos    = 2
        var output = Data()
        var done   = false

        while !done {
            guard pos < data.count else { break }
            let header = data[pos]; pos += 1
            let bfinal = (header & 0x01) != 0
            let btype  = (header >> 1) & 0x03

            switch btype {
            case 0x00:  // Stored block
                guard pos + 4 <= data.count else { throw PNGDecoderError.truncatedData }
                let len  = UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
                let nlen = UInt16(data[pos + 2]) | (UInt16(data[pos + 3]) << 8)
                pos += 4
                guard nlen == ~len else { throw PNGDecoderError.invalidZlibStream }
                let blockLen = Int(len)
                guard pos + blockLen <= data.count else { throw PNGDecoderError.truncatedData }
                output.append(data[pos ..< pos + blockLen])
                pos += blockLen
            default:
                throw PNGDecoderError.unsupportedDEFLATEBlockType(btype)
            }

            if bfinal { done = true }
        }

        return output
    }

    /// Read a big-endian 32-bit unsigned integer from `data` at `offset`.
    private static func readBE32(_ data: Data, at offset: Int) -> UInt32 {
        (UInt32(data[offset])     << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) <<  8)
            |  UInt32(data[offset + 3])
    }
}
