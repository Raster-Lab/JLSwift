import Foundation
import JPEGLS

/// Minimal DICOM Part-10 reader, scoped to what the JPEG-LS test/benchmark
/// harness needs: image geometry, pixel format, and the Pixel Data element.
///
/// This deliberately lives in the CLI target — the `JPEGLS` library is, by
/// design, DICOM-independent. The parser understands Explicit and Implicit VR
/// Little Endian datasets (the meta group is always Explicit VR LE) and both
/// native (uncompressed) and encapsulated Pixel Data. It does **not** aim to be
/// a general DICOM toolkit: it reads only the handful of tags required to drive
/// a lossless round-trip, and skips everything else (including sequences).
///
/// Known limitation: a small number of multi-frame Ultrasound files use
/// Implicit VR LE datasets with deeply nested private sequences that defeat
/// purely sequential parsing; `parse` throws for those. Callers (e.g. the
/// `bench-dicom` harness) treat such files as unreadable and skip them rather
/// than failing — they are not a JPEG-LS conformance signal.
enum DICOMSupport {

    // MARK: - Public model

    /// A decoded DICOM image header plus its raw Pixel Data bytes.
    struct Image: Sendable {
        var rows: Int                  // (0028,0010)
        var columns: Int               // (0028,0011)
        var samplesPerPixel: Int       // (0028,0002), default 1
        var bitsAllocated: Int         // (0028,0100)
        var bitsStored: Int            // (0028,0101)
        var highBit: Int               // (0028,0102)
        var pixelRepresentation: Int   // (0028,0103): 0 = unsigned, 1 = signed
        var planarConfiguration: Int   // (0028,0006): 0 = interleaved, 1 = planar
        var numberOfFrames: Int        // (0028,0008), default 1
        var photometric: String        // (0028,0004)
        var transferSyntaxUID: String  // (0002,0010)
        var isEncapsulated: Bool
        /// Native pixel bytes (uncompressed), or the concatenated codestream
        /// fragments (encapsulated).
        var pixelData: Data

        var isSigned: Bool { pixelRepresentation == 1 }
        var bytesPerSample: Int { (bitsAllocated + 7) / 8 }

        /// Whether this frame can be fed to the JPEG-LS encoder for a lossless
        /// round-trip: native (uncompressed), unsigned, ≤16-bit samples.
        var isEncodableLossless: Bool {
            !isEncapsulated && !isSigned && bitsAllocated <= 16 && bitsStored >= 1
                && rows > 0 && columns > 0 && samplesPerPixel >= 1
        }
    }

    enum DICOMError: Error, CustomStringConvertible {
        case notDICOM
        case truncated
        case missingPixelData
        case unsupported(String)

        var description: String {
            switch self {
            case .notDICOM:          return "not a DICOM Part-10 file (missing 'DICM' magic)"
            case .truncated:         return "DICOM stream ended unexpectedly"
            case .missingPixelData:  return "no Pixel Data (7FE0,0010) element found"
            case .unsupported(let s): return "unsupported DICOM feature: \(s)"
            }
        }
    }

    // Well-known transfer syntaxes.
    static let implicitVRLittleEndian = "1.2.840.10008.1.2"
    static let explicitVRLittleEndian = "1.2.840.10008.1.2.1"

    // VRs that carry a 32-bit length (with 2 reserved bytes) in Explicit VR.
    private static let longFormVRs: Set<UInt16> = {
        let strs = ["OB", "OW", "OF", "OD", "OL", "OV", "SQ", "UC", "UR", "UT", "UN"]
        return Set(strs.map { vrCode($0) })
    }()

    private static func vrCode(_ s: String) -> UInt16 {
        let b = Array(s.utf8)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }

    // MARK: - Parse

    static func parse(_ data: Data) throws -> Image {
        let bytes = [UInt8](data)
        // Part-10 preamble: 128-byte preamble + "DICM".
        guard bytes.count > 132,
              bytes[128] == 0x44, bytes[129] == 0x49,
              bytes[130] == 0x43, bytes[131] == 0x4D else {
            throw DICOMError.notDICOM
        }

        var cursor = 132

        // --- File Meta Information (group 0002): always Explicit VR LE. ---
        var transferSyntax = implicitVRLittleEndian
        while cursor + 8 <= bytes.count {
            let group = readU16(bytes, cursor)
            if group != 0x0002 { break }  // end of meta group
            let element = readU16(bytes, cursor + 2)
            let (length, valueOffset) = readExplicitVRHeader(bytes, cursor)
            if group == 0x0002, element == 0x0010 {
                transferSyntax = readString(bytes, valueOffset, length)
            }
            cursor = valueOffset + Int(length)
        }

        // Every transfer syntax *except* Implicit VR LE encodes the dataset in
        // Explicit VR Little Endian — including the encapsulated JPEG / JPEG-LS
        // / RLE syntaxes. Only "1.2.840.10008.1.2" is implicit.
        let explicit = (transferSyntax != implicitVRLittleEndian)
        // Anything that isn't one of the two native LE syntaxes is encapsulated
        // (JPEG / JPEG-LS / RLE …). Encapsulated Pixel Data has undefined length.
        let encapsulated = !(transferSyntax == implicitVRLittleEndian || transferSyntax == explicitVRLittleEndian)

        // --- Main dataset. ---
        var img = Image(
            rows: 0, columns: 0, samplesPerPixel: 1,
            bitsAllocated: 0, bitsStored: 0, highBit: 0,
            pixelRepresentation: 0, planarConfiguration: 0, numberOfFrames: 1,
            photometric: "", transferSyntaxUID: transferSyntax,
            isEncapsulated: encapsulated, pixelData: Data()
        )

        var sawPixelData = false
        while cursor + 8 <= bytes.count {
            let group = readU16(bytes, cursor)
            let element = readU16(bytes, cursor + 2)

            let length: UInt32
            let valueOffset: Int
            if explicit {
                (length, valueOffset) = readExplicitVRHeader(bytes, cursor)
            } else {
                length = readU32(bytes, cursor + 4)
                valueOffset = cursor + 8
            }

            // Pixel Data.
            if group == 0x7FE0, element == 0x0010 {
                if length == 0xFFFF_FFFF {
                    // Encapsulated: items = Basic Offset Table then fragments.
                    img.pixelData = readEncapsulatedFragments(bytes, valueOffset)
                    img.isEncapsulated = true
                } else {
                    let end = min(valueOffset + Int(length), bytes.count)
                    img.pixelData = Data(bytes[valueOffset..<end])
                }
                sawPixelData = true
                break
            }

            // Undefined length ⇒ a sequence; skip it (and any nesting) wholesale.
            if length == 0xFFFF_FFFF {
                cursor = skipUndefinedLengthSequence(bytes, valueOffset)
                continue
            }

            if group == 0x0028 {
                switch element {
                case 0x0002: img.samplesPerPixel = Int(readU16(bytes, valueOffset))
                case 0x0004: img.photometric = readString(bytes, valueOffset, length)
                case 0x0006: img.planarConfiguration = Int(readU16(bytes, valueOffset))
                case 0x0008: img.numberOfFrames = max(1, Int(readString(bytes, valueOffset, length).trimmingCharacters(in: .whitespaces)) ?? 1)
                case 0x0010: img.rows = Int(readU16(bytes, valueOffset))
                case 0x0011: img.columns = Int(readU16(bytes, valueOffset))
                case 0x0100: img.bitsAllocated = Int(readU16(bytes, valueOffset))
                case 0x0101: img.bitsStored = Int(readU16(bytes, valueOffset))
                case 0x0102: img.highBit = Int(readU16(bytes, valueOffset))
                case 0x0103: img.pixelRepresentation = Int(readU16(bytes, valueOffset))
                default: break
                }
            }

            cursor = valueOffset + Int(length)
            if group > 0x7FE0 { break }
        }

        guard sawPixelData else { throw DICOMError.missingPixelData }
        return img
    }

    // MARK: - Pixel extraction

    /// Build a single-component `[row][col]` integer array from the first frame
    /// of a native, unsigned grayscale image, plus the bit depth to encode at.
    ///
    /// Returns `nil` if the image isn't a native unsigned grayscale frame.
    static func grayscaleFrame(_ img: Image) -> (pixels: [[Int]], bitsPerSample: Int)? {
        guard img.isEncodableLossless, img.samplesPerPixel == 1 else { return nil }

        let w = img.columns, h = img.rows
        let bps = img.bytesPerSample
        let frameBytes = w * h * bps
        guard img.pixelData.count >= frameBytes else { return nil }

        var pixels = [[Int]](repeating: [Int](repeating: 0, count: w), count: h)
        var maxVal = 0
        // Mask to the stored bits so any padding in the high bits is ignored.
        let storedMask = img.bitsStored >= 16 ? 0xFFFF : ((1 << img.bitsStored) - 1)

        img.pixelData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!
            for row in 0..<h {
                let rowOff = row * w * bps
                for col in 0..<w {
                    let off = rowOff + col * bps
                    let value: Int
                    if bps == 1 {
                        value = Int(base.load(fromByteOffset: off, as: UInt8.self)) & storedMask
                    } else {
                        // Little-endian 16-bit sample.
                        let lo = Int(base.load(fromByteOffset: off, as: UInt8.self))
                        let hi = Int(base.load(fromByteOffset: off + 1, as: UInt8.self))
                        value = ((hi << 8) | lo) & storedMask
                    }
                    pixels[row][col] = value
                    if value > maxVal { maxVal = value }
                }
            }
        }

        // JPEG-LS bit depth must cover the actual sample range, and be ≥ 2.
        var bits = max(2, img.bitsStored)
        while (1 << bits) - 1 < maxVal && bits < 16 { bits += 1 }
        return (pixels, bits)
    }

    // MARK: - Low-level readers

    private static func readU16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func readU32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    private static func readString(_ b: [UInt8], _ off: Int, _ length: UInt32) -> String {
        let end = min(off + Int(length), b.count)
        guard off <= end else { return "" }
        let slice = b[off..<end]
        let trimmed = slice.drop { $0 == 0 }.reversed().drop { $0 == 0 || $0 == 0x20 }.reversed()
        return String(decoding: Array(trimmed), as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// Parse an Explicit VR element header at `start`, returning (valueLength, valueOffset).
    private static func readExplicitVRHeader(_ b: [UInt8], _ start: Int) -> (UInt32, Int) {
        let vr = readU16(b, start + 4)
        if longFormVRs.contains(vr) {
            // VR(2) + reserved(2) + length(4)
            let length = readU32(b, start + 8)
            return (length, start + 12)
        } else {
            // VR(2) + length(2)
            let length = UInt32(readU16(b, start + 6))
            return (length, start + 8)
        }
    }

    /// Given the offset just past an undefined-length element header, skip the
    /// entire sequence (handling nested items / sequences) and return the offset
    /// immediately following its Sequence Delimitation Item (FFFE,E0DD).
    private static func skipUndefinedLengthSequence(_ b: [UInt8], _ start: Int) -> Int {
        var i = start
        var depth = 1
        while i + 8 <= b.count && depth > 0 {
            let group = readU16(b, i)
            let element = readU16(b, i + 2)
            let length = readU32(b, i + 4)
            i += 8
            if group == 0xFFFE && element == 0xE0DD {        // sequence delimiter
                depth -= 1
            } else if group == 0xFFFE && element == 0xE000 { // item
                if length == 0xFFFF_FFFF {
                    depth += 1                               // undefined-length item: descend
                } else {
                    i += Int(length)                         // defined-length item: skip
                }
            } else if length != 0xFFFF_FFFF {
                i += Int(length)
            } else {
                depth += 1
            }
        }
        return i
    }

    /// Read encapsulated Pixel Data fragments: skip the Basic Offset Table item,
    /// then concatenate all fragment items up to the Sequence Delimitation Item.
    private static func readEncapsulatedFragments(_ b: [UInt8], _ start: Int) -> Data {
        var i = start
        var out = Data()
        var first = true
        while i + 8 <= b.count {
            let group = readU16(b, i)
            let element = readU16(b, i + 2)
            let length = readU32(b, i + 4)
            i += 8
            if group == 0xFFFE && element == 0xE0DD { break }   // sequence delimiter
            guard group == 0xFFFE && element == 0xE000 else { break }
            let end = min(i + Int(length), b.count)
            if first {
                first = false   // Basic Offset Table — skip its contents
            } else {
                out.append(contentsOf: b[i..<end])
            }
            i = end
        }
        return out
    }
}
