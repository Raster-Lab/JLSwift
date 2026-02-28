// TIFFSupport.swift
// Minimal pure-Swift Baseline TIFF encoder and decoder for greyscale and RGB images.
//
// Encoder: supports 8-bit and 16-bit samples for both greyscale (1 component) and RGB
// (3 components) images. Pixel data is stored without compression (TIFF
// Compression tag = 1), in a single strip, using chunky (interleaved) planar
// configuration. The output is a little-endian ('II') TIFF file readable by
// all conforming TIFF decoders.
//
// Decoder: supports uncompressed (Compression = 1) TIFF files with 8-bit or 16-bit
// samples, 1 (greyscale) or 3 (RGB) components, and chunky planar configuration.
// This covers all TIFF files produced by the encoder above; compressed or exotic
// TIFF variants are not supported.

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

// MARK: - TIFF Decoder Errors

/// Errors produced by the TIFF decoder.
public enum TIFFDecoderError: Error, CustomStringConvertible, Equatable {
    /// The file does not begin with a valid TIFF byte-order mark ('II' or 'MM').
    case invalidByteOrderMark
    /// The TIFF magic number is not 42.
    case invalidMagicNumber
    /// A required IFD tag is missing.
    case missingRequiredTag(UInt16)
    /// Compression type is not 1 (no compression).
    case unsupportedCompression(UInt16)
    /// BitsPerSample is not 8 or 16.
    case unsupportedBitsPerSample(Int)
    /// SamplesPerPixel is not 1 (greyscale) or 3 (RGB).
    case unsupportedSamplesPerPixel(Int)
    /// PlanarConfiguration is not 1 (chunky/interleaved).
    case unsupportedPlanarConfiguration(UInt16)
    /// The pixel data is shorter than expected.
    case truncatedData

    public var description: String {
        switch self {
        case .invalidByteOrderMark:
            return "TIFF decoder: file does not begin with 'II' (little-endian) or 'MM' (big-endian)"
        case .invalidMagicNumber:
            return "TIFF decoder: magic number is not 42"
        case .missingRequiredTag(let tag):
            return "TIFF decoder: required IFD tag \(tag) is missing"
        case .unsupportedCompression(let c):
            return "TIFF decoder: compression type \(c) is not supported — only uncompressed (type 1) is supported"
        case .unsupportedBitsPerSample(let b):
            return "TIFF decoder: BitsPerSample \(b) is not supported — only 8 and 16 are supported"
        case .unsupportedSamplesPerPixel(let s):
            return "TIFF decoder: SamplesPerPixel \(s) is not supported — only 1 (greyscale) or 3 (RGB) is supported"
        case .unsupportedPlanarConfiguration(let p):
            return "TIFF decoder: PlanarConfiguration \(p) is not supported — only chunky (type 1) is supported"
        case .truncatedData:
            return "TIFF decoder: pixel data is shorter than expected"
        }
    }
}

// MARK: - TIFF Decoder

/// A decoded TIFF image.
public struct TIFFImage: Sendable {
    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Bits per sample (8 or 16).
    public let bitsPerSample: Int
    /// Pixel data organised as `[component][row][column]`.
    /// Component count is 1 for greyscale or 3 for RGB.
    public let componentPixels: [[[Int]]]

    /// Maximum sample value (255 for 8-bit, 65535 for 16-bit).
    public var maxVal: Int { (1 << bitsPerSample) - 1 }
}

extension TIFFSupport {

    // MARK: - Public Decode API

    /// Decode an uncompressed Baseline TIFF file into component pixel arrays.
    ///
    /// Only uncompressed (Compression = 1) TIFF files with 8-bit or 16-bit samples and
    /// chunky planar configuration are supported. This covers all TIFF files produced by
    /// `TIFFSupport.encode(...)`.
    ///
    /// - Parameter data: Raw TIFF file bytes.
    /// - Returns: A `TIFFImage` containing dimensions, bits per sample, and pixel data.
    /// - Throws: `TIFFDecoderError` if the file is invalid or uses unsupported features.
    ///
    /// **Usage example:**
    /// ```swift
    /// let pixels: [[[Int]]] = [[[10, 20], [30, 40]]]
    /// let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
    /// let image = try TIFFSupport.decode(tiffData)
    /// // image.componentPixels[0][0][0] == 10
    /// ```
    public static func decode(_ data: Data) throws -> TIFFImage {
        guard data.count >= 8 else { throw TIFFDecoderError.invalidByteOrderMark }

        // Detect byte order.
        let isLittleEndian: Bool
        if data[0] == 0x49 && data[1] == 0x49 {      // 'II'
            isLittleEndian = true
        } else if data[0] == 0x4D && data[1] == 0x4D { // 'MM'
            isLittleEndian = false
        } else {
            throw TIFFDecoderError.invalidByteOrderMark
        }

        // Helpers to read integers with the correct byte order.
        func read16(at offset: Int) -> UInt16 {
            let a = UInt16(data[offset]), b = UInt16(data[offset + 1])
            return isLittleEndian ? (b << 8 | a) : (a << 8 | b)
        }
        func read32(at offset: Int) -> UInt32 {
            let a = UInt32(data[offset]),     b = UInt32(data[offset + 1])
            let c = UInt32(data[offset + 2]), d = UInt32(data[offset + 3])
            return isLittleEndian
                ? (d << 24 | c << 16 | b << 8 | a)
                : (a << 24 | b << 16 | c << 8 | d)
        }

        // Verify magic number 42.
        let magic = read16(at: 2)
        guard magic == 42 else { throw TIFFDecoderError.invalidMagicNumber }

        // Read IFD offset.
        let ifdOffset = Int(read32(at: 4))
        guard ifdOffset + 2 <= data.count else { throw TIFFDecoderError.truncatedData }

        let entryCount = Int(read16(at: ifdOffset))
        let entriesStart = ifdOffset + 2

        // Parse IFD entries into a tag → (type, count, value/offset) dictionary.
        struct IFDEntry { var type: UInt16; var count: UInt32; var valueOrOffset: UInt32 }
        var tags: [UInt16: IFDEntry] = [:]

        for i in 0..<entryCount {
            let base   = entriesStart + i * 12
            guard base + 12 <= data.count else { break }
            let tag    = read16(at: base)
            let type   = read16(at: base + 2)
            let count  = read32(at: base + 4)
            let valOff = read32(at: base + 8)
            tags[tag] = IFDEntry(type: type, count: count, valueOrOffset: valOff)
        }

        // Helper to resolve a tag value: for SHORT (type=3) with count=1 the value is
        // stored inline in the lower 2 bytes of valueOrOffset (LE: low word first).
        func resolveUInt32(tag: UInt16) -> UInt32? {
            guard let e = tags[tag] else { return nil }
            if e.type == 3 && e.count == 1 {
                // SHORT stored inline: the 2-byte value sits in the first 2 bytes of
                // the value/offset field.
                let raw = e.valueOrOffset
                return isLittleEndian ? (raw & 0xFFFF) : (raw >> 16)
            }
            if e.type == 3 {
                // Multiple SHORTs: valueOrOffset is an offset into the file; read first value.
                let off = Int(e.valueOrOffset)
                guard off + 2 <= data.count else { return nil }
                return UInt32(read16(at: off))
            }
            if e.type == 4 { return e.valueOrOffset }  // LONG
            return nil
        }

        // Read required tags.
        guard let w = resolveUInt32(tag: 256) else { throw TIFFDecoderError.missingRequiredTag(256) }
        guard let h = resolveUInt32(tag: 257) else { throw TIFFDecoderError.missingRequiredTag(257) }
        guard let bps = resolveUInt32(tag: 258) else { throw TIFFDecoderError.missingRequiredTag(258) }
        guard let comp = resolveUInt32(tag: 259) else { throw TIFFDecoderError.missingRequiredTag(259) }
        guard let spp = resolveUInt32(tag: 277) else { throw TIFFDecoderError.missingRequiredTag(277) }

        let width          = Int(w)
        let height         = Int(h)
        let bitsPerSample  = Int(bps)
        let compression    = UInt16(comp)
        let samplesPerPixel = Int(spp)

        guard compression == 1 else { throw TIFFDecoderError.unsupportedCompression(compression) }
        guard bitsPerSample == 8 || bitsPerSample == 16 else {
            throw TIFFDecoderError.unsupportedBitsPerSample(bitsPerSample)
        }
        guard samplesPerPixel == 1 || samplesPerPixel == 3 else {
            throw TIFFDecoderError.unsupportedSamplesPerPixel(samplesPerPixel)
        }

        // PlanarConfiguration (tag 284) — defaults to 1 (chunky) if absent.
        if let pc = resolveUInt32(tag: 284) {
            guard pc == 1 else { throw TIFFDecoderError.unsupportedPlanarConfiguration(UInt16(pc)) }
        }

        // Read strip offset(s). TIFFSupport.encode always writes a single strip.
        guard let stripOffEntry = tags[273] else { throw TIFFDecoderError.missingRequiredTag(273) }
        let stripOffset: Int
        if stripOffEntry.count == 1 {
            stripOffset = Int(resolveUInt32(tag: 273) ?? 0)
        } else {
            stripOffset = Int(stripOffEntry.valueOrOffset)
        }

        // Extract pixel data.
        let bytesPerSample  = bitsPerSample / 8
        let bytesPerPixel   = samplesPerPixel * bytesPerSample
        let totalBytes      = width * height * bytesPerPixel
        guard stripOffset + totalBytes <= data.count else { throw TIFFDecoderError.truncatedData }

        var componentPixels = Array(
            repeating: Array(repeating: Array(repeating: 0, count: width), count: height),
            count: samplesPerPixel
        )

        for row in 0..<height {
            for col in 0..<width {
                let pixelBase = stripOffset + (row * width + col) * bytesPerPixel
                for comp in 0..<samplesPerPixel {
                    let off = pixelBase + comp * bytesPerSample
                    if bytesPerSample == 2 {
                        // TIFF stores 16-bit samples in the file byte order.
                        let a = UInt16(data[off]), b = UInt16(data[off + 1])
                        let v: UInt16 = isLittleEndian ? (b << 8 | a) : (a << 8 | b)
                        componentPixels[comp][row][col] = Int(v)
                    } else {
                        componentPixels[comp][row][col] = Int(data[off])
                    }
                }
            }
        }

        return TIFFImage(
            width: width,
            height: height,
            bitsPerSample: bitsPerSample,
            componentPixels: componentPixels
        )
    }
}
