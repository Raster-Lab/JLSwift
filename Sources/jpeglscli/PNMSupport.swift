// PNMSupport.swift
// Utilities for reading and writing PGM (P5) and PPM (P6) image files.

import Foundation

// MARK: - PNM Image

/// A decoded PGM or PPM image.
struct PNMImage {
    /// Image width in pixels.
    let width: Int
    /// Image height in pixels.
    let height: Int
    /// Maximum sample value (e.g. 255 for 8-bit, 4095 for 12-bit).
    let maxVal: Int
    /// Number of colour components: 1 for PGM, 3 for PPM.
    let components: Int
    /// Pixel data organized as `[component][row][column]`, values in `[0, maxVal]`.
    let componentPixels: [[[Int]]]
}

// MARK: - PNM Errors

/// Errors that can occur when reading or writing PGM/PPM files.
enum PNMError: Error, CustomStringConvertible {
    case invalidFormat(String)
    case unsupportedFormat(String)
    case insufficientData

    var description: String {
        switch self {
        case .invalidFormat(let msg):    return "Invalid PNM format: \(msg)"
        case .unsupportedFormat(let fmt): return "Unsupported PNM format: \(fmt)"
        case .insufficientData:           return "Insufficient pixel data in PNM file"
        }
    }
}

// MARK: - PNM Support

/// Utilities for reading (parsing) and writing (encoding) PGM and PPM image files.
enum PNMSupport {

    // MARK: Parsing

    /// Parse a PGM (P5) or PPM (P6) binary image from raw data.
    ///
    /// - Parameter data: The full contents of a `.pgm` or `.ppm` file.
    /// - Returns: A `PNMImage` with pixel data in `[component][row][column]` order.
    /// - Throws: `PNMError` if the data is malformed or uses an unsupported format.
    static func parse(_ data: Data) throws -> PNMImage {
        let headerEnd = try findHeaderEnd(data: data)

        guard let headerString = String(data: data.subdata(in: 0..<headerEnd), encoding: .ascii) else {
            throw PNMError.invalidFormat("Cannot decode header as ASCII")
        }

        // Filter out comment lines (lines starting with '#').
        let lines = headerString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard lines.count >= 3 else {
            throw PNMError.invalidFormat("Header too short")
        }

        let magic = lines[0]
        let components: Int
        switch magic {
        case "P5": components = 1
        case "P6": components = 3
        default:
            throw PNMError.unsupportedFormat("Only P5 (PGM) and P6 (PPM) are supported; got '\(magic)'")
        }

        let dimParts = lines[1].split(separator: " ")
        guard dimParts.count == 2,
              let width  = Int(dimParts[0]),
              let height = Int(dimParts[1]),
              width > 0, height > 0 else {
            throw PNMError.invalidFormat("Invalid dimensions in header")
        }

        guard let maxVal = Int(lines[2]), maxVal > 0, maxVal <= 65535 else {
            throw PNMError.invalidFormat("Invalid MAXVAL in header")
        }

        let pixelData = data.subdata(in: headerEnd..<data.count)
        let bytesPerSample = maxVal < 256 ? 1 : 2
        let expectedBytes  = width * height * components * bytesPerSample
        guard pixelData.count >= expectedBytes else {
            throw PNMError.insufficientData
        }

        // Decode interleaved pixel samples to [component][row][col].
        var componentPixels: [[[Int]]] = Array(
            repeating: Array(
                repeating: Array(repeating: 0, count: width),
                count: height
            ),
            count: components
        )

        var sampleIndex = 0
        for row in 0..<height {
            for col in 0..<width {
                for comp in 0..<components {
                    let byteOffset = sampleIndex * bytesPerSample
                    let value: Int
                    if bytesPerSample == 1 {
                        value = Int(pixelData[byteOffset])
                    } else {
                        value = (Int(pixelData[byteOffset]) << 8) | Int(pixelData[byteOffset + 1])
                    }
                    componentPixels[comp][row][col] = value
                    sampleIndex += 1
                }
            }
        }

        return PNMImage(
            width: width,
            height: height,
            maxVal: maxVal,
            components: components,
            componentPixels: componentPixels
        )
    }

    // MARK: Writing

    /// Encode decoded JPEG-LS pixel data to PGM (1 component) or PPM (3 components) format.
    ///
    /// - Parameters:
    ///   - componentPixels: Pixel data as `[component][row][column]`.
    ///   - width:  Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - maxVal: Maximum sample value (determines byte depth and MAXVAL field).
    /// - Returns: Raw data for a valid PGM or PPM file.
    /// - Throws: `PNMError` if the component count is not 1 or 3.
    static func encode(
        componentPixels: [[[Int]]],
        width: Int,
        height: Int,
        maxVal: Int
    ) throws -> Data {
        let numComponents = componentPixels.count
        let magic: String
        switch numComponents {
        case 1: magic = "P5"
        case 3: magic = "P6"
        default:
            throw PNMError.unsupportedFormat(
                "PNM output requires 1 (PGM) or 3 (PPM) components; got \(numComponents)"
            )
        }

        let header = "\(magic)\n\(width) \(height)\n\(maxVal)\n"
        var data = Data(header.utf8)

        let bytesPerSample = maxVal < 256 ? 1 : 2
        data.reserveCapacity(data.count + width * height * numComponents * bytesPerSample)

        for row in 0..<height {
            for col in 0..<width {
                for comp in 0..<numComponents {
                    let val = componentPixels[comp][row][col]
                    if bytesPerSample == 1 {
                        data.append(UInt8(clamping: val))
                    } else {
                        let v = UInt16(clamping: val)
                        data.append(UInt8((v >> 8) & 0xFF))
                        data.append(UInt8(v & 0xFF))
                    }
                }
            }
        }

        return data
    }

    // MARK: - Private Helpers

    /// Locate the byte offset at which binary pixel data begins (immediately after the
    /// third newline in the ASCII header section, which follows the MAXVAL token).
    private static func findHeaderEnd(data: Data) throws -> Int {
        var newlineCount = 0
        let limit = min(data.count, 1024)
        for i in 0..<limit {
            if data[i] == 0x0A { // '\n'
                newlineCount += 1
                if newlineCount == 3 {
                    return i + 1
                }
            }
        }
        throw PNMError.invalidFormat("Header end not found (expected 3 newlines within first 1024 bytes)")
    }
}
