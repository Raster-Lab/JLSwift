/// JPEG-LS bitstream parser per ISO/IEC 14495-1:1999 / ITU-T.87
///
/// Parses JPEG-LS encoded data streams, extracting frame headers, scan headers,
/// preset parameters, and locating compressed image data.
///
/// ## CharLS Compatibility
///
/// This parser includes support for CharLS-specific extension markers in the range 0xFF60-0xFF7F.
/// These markers are used by the CharLS library as escape sequences within scan data (similar to
/// the standard 0xFF00 byte stuffing). The parser treats these sequences transparently, allowing
/// it to correctly parse CharLS-encoded files while maintaining compatibility with standard JPEG-LS.

import Foundation

/// Result of parsing a JPEG-LS bitstream
///
/// Contains all metadata needed for decoding the image data.
public struct JPEGLSParseResult: Sendable {
    /// Frame header describing image dimensions and components
    public let frameHeader: JPEGLSFrameHeader
    
    /// Scan headers for each scan in the image
    public let scanHeaders: [JPEGLSScanHeader]
    
    /// Preset parameters (if custom parameters were specified via LSE marker)
    public let presetParameters: JPEGLSPresetParameters?
    
    /// Application marker data (APP0-APP15)
    public let applicationMarkers: [(marker: JPEGLSMarker, data: Data)]
    
    /// Comment marker data
    public let comments: [Data]
    
    /// Initialize parse result
    ///
    /// - Parameters:
    ///   - frameHeader: Frame header
    ///   - scanHeaders: Scan headers
    ///   - presetParameters: Optional custom preset parameters
    ///   - applicationMarkers: Application markers
    ///   - comments: Comment data
    public init(
        frameHeader: JPEGLSFrameHeader,
        scanHeaders: [JPEGLSScanHeader],
        presetParameters: JPEGLSPresetParameters? = nil,
        applicationMarkers: [(marker: JPEGLSMarker, data: Data)] = [],
        comments: [Data] = []
    ) {
        self.frameHeader = frameHeader
        self.scanHeaders = scanHeaders
        self.presetParameters = presetParameters
        self.applicationMarkers = applicationMarkers
        self.comments = comments
    }
}

/// JPEG-LS bitstream parser
///
/// Parses JPEG-LS file format according to ITU-T.87 standard.
/// Validates marker sequence and extracts all necessary metadata for decoding.
public final class JPEGLSParser {
    private let reader: JPEGLSBitstreamReader
    
    /// Initialize parser with encoded data
    ///
    /// - Parameter data: JPEG-LS encoded data
    public init(data: Data) {
        self.reader = JPEGLSBitstreamReader(data: data)
    }
    
    /// Parse the JPEG-LS bitstream
    ///
    /// Validates the structure and extracts all metadata.
    ///
    /// The parser handles both standard JPEG-LS files and CharLS-encoded files with extension markers.
    /// Unknown markers (including CharLS-specific markers 0xFF60-0xFF7F) are gracefully skipped.
    ///
    /// - Returns: Parse result containing frame header, scan headers, and parameters
    /// - Throws: `JPEGLSError` if the bitstream is invalid or corrupted
    public func parse() throws -> JPEGLSParseResult {
        // Parse SOI marker
        try expectMarker(.startOfImage)
        
        var frameHeader: JPEGLSFrameHeader?
        var scanHeaders: [JPEGLSScanHeader] = []
        var presetParameters: JPEGLSPresetParameters?
        var applicationMarkers: [(marker: JPEGLSMarker, data: Data)] = []
        var comments: [Data] = []
        
        // Parse marker segments until EOI
        while !reader.isAtEnd {
            // Read marker bytes manually to handle unknown markers
            let byte1 = try reader.readByte()
            guard byte1 == JPEGLSMarker.markerPrefix else {
                throw JPEGLSError.invalidBitstreamStructure(
                    reason: "Expected marker prefix (0xFF), got 0x\(String(byte1, radix: 16))"
                )
            }
            
            let byte2 = try reader.readByte()
            
            // Try to parse as known marker
            guard let marker = JPEGLSMarker(rawValue: byte2) else {
                // Unknown marker - skip it gracefully
                // Some markers have no length field (standalone markers)
                if (byte2 >= 0xD0 && byte2 <= 0xD7) || byte2 == 0xD8 || byte2 == 0xD9 {
                    // RST markers (0xD0-0xD7), SOI (0xD8), and EOI (0xD9) have no length field
                    continue
                } else if byte2 >= 0x60 && byte2 <= 0x7F {
                    // CharLS uses markers in the 0xFF60-0xFF7F range as standalone markers (no length field)
                    // These appear to be used for internal purposes and can be safely skipped
                    continue
                } else {
                    // Read length and skip the marker segment
                    let length = try reader.readUInt16()
                    guard length >= 2 else {
                        throw JPEGLSError.invalidBitstreamStructure(
                            reason: "Invalid marker segment length for unknown marker 0xFF\(String(byte2, radix: 16)): \(length)"
                        )
                    }
                    let skipLength = Int(length) - 2
                    _ = try reader.readBytes(skipLength)
                    continue
                }
            }
            
            switch marker {
            case .endOfImage:
                // End of JPEG-LS stream
                guard let frame = frameHeader else {
                    throw JPEGLSError.invalidBitstreamStructure(
                        reason: "No frame header found before EOI"
                    )
                }
                guard !scanHeaders.isEmpty else {
                    throw JPEGLSError.invalidBitstreamStructure(
                        reason: "No scan headers found before EOI"
                    )
                }
                return JPEGLSParseResult(
                    frameHeader: frame,
                    scanHeaders: scanHeaders,
                    presetParameters: presetParameters,
                    applicationMarkers: applicationMarkers,
                    comments: comments
                )
                
            case .startOfFrameJPEGLS:
                // Parse frame header
                guard frameHeader == nil else {
                    throw JPEGLSError.invalidBitstreamStructure(
                        reason: "Multiple SOF markers found"
                    )
                }
                frameHeader = try parseFrameHeader()
                
            case .startOfScan:
                // Parse scan header
                guard let frame = frameHeader else {
                    throw JPEGLSError.invalidBitstreamStructure(
                        reason: "SOS marker found before SOF"
                    )
                }
                let scanHeader = try parseScanHeader(frameHeader: frame)
                scanHeaders.append(scanHeader)
                
                // Skip scan data until we hit a marker
                // Scan data ends when we encounter a marker (0xFF followed by non-stuffing byte)
                // Byte stuffing rules:
                //   - FF 00: Standard JPEG-LS byte stuffing (0x00 is removed during decoding)
                //   - FF 60-FF 7F: CharLS escape sequences (treated like byte stuffing for compatibility)
                //   - FF XX (other): Real marker - terminates scan data
                while !reader.isAtEnd {
                    let byte = try reader.readByte()
                    if byte == JPEGLSMarker.markerPrefix {
                        // Check next byte to determine if it's stuffing or a real marker
                        if let nextByte = reader.peekByte() {
                            if nextByte == 0x00 || (nextByte >= 0x60 && nextByte <= 0x7F) {
                                // Byte stuffing or CharLS escape - skip and continue reading scan data
                                _ = try reader.readByte()
                                continue
                            } else {
                                // Real marker - back up to re-read the FF byte in the outer loop
                                try reader.seek(to: reader.currentPosition - 1)
                                break
                            }
                        } else {
                            // End of stream
                            break
                        }
                    }
                }
                
            case .jpegLSExtension:
                // Parse JPEG-LS extension
                try parseJPEGLSExtension(
                    frameHeader: frameHeader,
                    presetParameters: &presetParameters
                )
                
            case .applicationMarker0, .applicationMarker1, .applicationMarker2,
                 .applicationMarker3, .applicationMarker4, .applicationMarker5,
                 .applicationMarker6, .applicationMarker7, .applicationMarker8,
                 .applicationMarker9, .applicationMarker10, .applicationMarker11,
                 .applicationMarker12, .applicationMarker13, .applicationMarker14,
                 .applicationMarker15:
                // Parse application marker
                let data = try parseMarkerSegment()
                applicationMarkers.append((marker: marker, data: data))
                
            case .comment:
                // Parse comment
                let data = try parseMarkerSegment()
                comments.append(data)
                
            case .restart0, .restart1, .restart2, .restart3,
                 .restart4, .restart5, .restart6, .restart7:
                // Restart markers have no length field, just skip
                continue
                
            case .startOfImage:
                throw JPEGLSError.invalidBitstreamStructure(
                    reason: "Unexpected SOI marker"
                )
            }
        }
        
        throw JPEGLSError.invalidBitstreamStructure(
            reason: "Missing EOI marker"
        )
    }
    
    // MARK: - Private Parsing Methods
    
    /// Expect a specific marker
    private func expectMarker(_ expected: JPEGLSMarker) throws {
        let marker = try reader.readMarker()
        guard marker == expected else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Expected \(expected), got \(marker)"
            )
        }
    }
    
    /// Parse a generic marker segment with length field
    private func parseMarkerSegment() throws -> Data {
        let length = try reader.readUInt16()
        guard length >= 2 else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Invalid marker segment length: \(length)"
            )
        }
        // Length includes the 2 bytes of the length field itself
        let dataLength = Int(length) - 2
        return try reader.readBytes(dataLength)
    }
    
    /// Parse frame header (SOF marker segment)
    private func parseFrameHeader() throws -> JPEGLSFrameHeader {
        let length = try reader.readUInt16()
        
        // Read precision (bits per sample)
        let bitsPerSample = Int(try reader.readByte())
        
        // Read dimensions
        let height = Int(try reader.readUInt16())
        let width = Int(try reader.readUInt16())
        
        // Read component count
        let componentCount = Int(try reader.readByte())
        
        // Validate expected length
        let expectedLength = 2 + 1 + 2 + 2 + 1 + (componentCount * 3)
        guard length == expectedLength else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Invalid SOF length: expected \(expectedLength), got \(length)"
            )
        }
        
        // Read component specifications
        var components: [JPEGLSFrameHeader.ComponentSpec] = []
        components.reserveCapacity(componentCount)
        
        for _ in 0..<componentCount {
            let id = try reader.readByte()
            let samplingFactors = try reader.readByte()
            let horizontalSampling = samplingFactors >> 4
            let verticalSampling = samplingFactors & 0x0F
            _ = try reader.readByte()  // Quantization table selector (not used in JPEG-LS)
            
            components.append(JPEGLSFrameHeader.ComponentSpec(
                id: id,
                horizontalSamplingFactor: horizontalSampling,
                verticalSamplingFactor: verticalSampling
            ))
        }
        
        return try JPEGLSFrameHeader(
            bitsPerSample: bitsPerSample,
            height: height,
            width: width,
            componentCount: componentCount,
            components: components
        )
    }
    
    /// Parse scan header (SOS marker segment)
    private func parseScanHeader(frameHeader: JPEGLSFrameHeader) throws -> JPEGLSScanHeader {
        let length = try reader.readUInt16()
        
        // Read component count in this scan
        let componentCount = Int(try reader.readByte())
        
        // Validate expected length
        let expectedLength = 2 + 1 + (componentCount * 2) + 3
        guard length == expectedLength else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Invalid SOS length: expected \(expectedLength), got \(length)"
            )
        }
        
        // Read component selectors
        var components: [JPEGLSScanHeader.ComponentSelector] = []
        components.reserveCapacity(componentCount)
        
        for _ in 0..<componentCount {
            let id = try reader.readByte()
            _ = try reader.readByte()  // Table selector (not used in JPEG-LS)
            components.append(JPEGLSScanHeader.ComponentSelector(id: id))
        }
        
        // Read NEAR parameter
        let near = Int(try reader.readByte())
        
        // Read interleave mode
        let interleaveModeValue = try reader.readByte()
        guard let interleaveMode = JPEGLSInterleaveMode(rawValue: interleaveModeValue) else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Invalid interleave mode: \(interleaveModeValue)"
            )
        }
        
        // Read point transform
        let pointTransform = Int(try reader.readByte())
        
        let scanHeader = try JPEGLSScanHeader(
            componentCount: componentCount,
            components: components,
            near: near,
            interleaveMode: interleaveMode,
            pointTransform: pointTransform
        )
        
        // Validate scan header against frame header
        try scanHeader.validate(against: frameHeader)
        
        return scanHeader
    }
    
    /// Parse JPEG-LS extension marker (LSE)
    private func parseJPEGLSExtension(
        frameHeader: JPEGLSFrameHeader?,
        presetParameters: inout JPEGLSPresetParameters?
    ) throws {
        let length = try reader.readUInt16()
        
        // Read extension type
        let extensionTypeByte = try reader.readByte()
        guard let extensionType = JPEGLSExtensionType(rawValue: extensionTypeByte) else {
            // Unknown extension type - skip the rest
            let skipLength = Int(length) - 3  // Length includes itself (2) and type (1)
            _ = try reader.readBytes(skipLength)
            return
        }
        
        switch extensionType {
        case .presetCodingParameters:
            // Parse preset parameters
            guard length == 13 else {
                throw JPEGLSError.invalidBitstreamStructure(
                    reason: "Invalid LSE preset parameters length: \(length)"
                )
            }
            
            let maxValue = Int(try reader.readUInt16())
            let threshold1 = Int(try reader.readUInt16())
            let threshold2 = Int(try reader.readUInt16())
            let threshold3 = Int(try reader.readUInt16())
            let reset = Int(try reader.readUInt16())
            
            presetParameters = try JPEGLSPresetParameters(
                maxValue: maxValue,
                threshold1: threshold1,
                threshold2: threshold2,
                threshold3: threshold3,
                reset: reset
            )
            
        case .mappingTable, .mappingTableContinuation:
            // Mapping tables not yet supported - skip
            let skipLength = Int(length) - 3
            _ = try reader.readBytes(skipLength)
            
        case .extendedDimensions:
            // Extended dimensions not yet supported - skip
            let skipLength = Int(length) - 3
            _ = try reader.readBytes(skipLength)
        }
    }
}
