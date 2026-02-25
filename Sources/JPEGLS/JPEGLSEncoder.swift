/// High-level JPEG-LS encoder API
///
/// Provides a simple interface to encode raw pixel data to JPEG-LS format.
/// Handles all aspects of JPEG-LS file generation including markers, headers,
/// and bitstream encoding.

import Foundation

/// High-level JPEG-LS encoder
///
/// Encodes multi-component image data to JPEG-LS file format per ITU-T.87.
/// Supports all encoding modes (lossless, near-lossless) and interleaving modes.
///
/// **Example usage:**
/// ```swift
/// // Create encoder
/// let encoder = JPEGLSEncoder()
///
/// // Prepare image data
/// let imageData = try MultiComponentImageData.grayscale(
///     pixels: pixels,
///     bitsPerSample: 8
/// )
///
/// // Encode to JPEG-LS
/// let jpegLSData = try encoder.encode(
///     imageData,
///     near: 0,  // Lossless
///     interleaveMode: .none
/// )
/// ```
public struct JPEGLSEncoder: Sendable {
    /// Configuration for encoding
    public struct Configuration: Sendable {
        /// NEAR parameter for near-lossless encoding (0 = lossless)
        public let near: Int
        
        /// Interleaving mode for multi-component images
        public let interleaveMode: JPEGLSInterleaveMode
        
        /// Optional custom preset parameters
        public let presetParameters: JPEGLSPresetParameters?
        
        /// Colour transformation applied before encoding (default: .none).
        ///
        /// When a transformation other than `.none` is specified the encoder:
        ///   1. Writes an APP8 "mrfx" marker so decoders can invert the transform.
        ///   2. Applies the forward transform (with modular arithmetic) to every
        ///      pixel before the JPEG-LS codec runs.
        public let colorTransformation: JPEGLSColorTransformation
        
        /// Initialize encoding configuration
        ///
        /// - Parameters:
        ///   - near: NEAR parameter (0 = lossless, 1-255 = near-lossless)
        ///   - interleaveMode: Interleaving mode for multi-component images
        ///   - presetParameters: Optional custom preset parameters (uses defaults if nil)
        ///   - colorTransformation: Colour transform to apply before encoding (default: .none)
        /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is out of range
        public init(
            near: Int = 0,
            interleaveMode: JPEGLSInterleaveMode = .none,
            presetParameters: JPEGLSPresetParameters? = nil,
            colorTransformation: JPEGLSColorTransformation = .none
        ) throws {
            guard near >= 0 && near <= 255 else {
                throw JPEGLSError.invalidNearParameter(near: near)
            }
            
            self.near = near
            self.interleaveMode = interleaveMode
            self.presetParameters = presetParameters
            self.colorTransformation = colorTransformation
        }
    }
    
    /// Initialize encoder
    public init() {}
    
    /// Encode image data to JPEG-LS format
    ///
    /// - Parameters:
    ///   - imageData: Multi-component image data to encode
    ///   - configuration: Encoding configuration
    /// - Returns: JPEG-LS encoded data
    /// - Throws: `JPEGLSError` if encoding fails
    public func encode(
        _ imageData: MultiComponentImageData,
        configuration: Configuration
    ) throws -> Data {
        let writer = JPEGLSBitstreamWriter()
        
        // Write SOI marker (Start of Image)
        writer.writeMarker(.startOfImage)
        
        // Write APP8 "mrfx" colour-transform marker when a transform is requested.
        // This must appear before the SOF so that decoders can read it and invert the transform.
        let colorTransformation = configuration.colorTransformation
        if colorTransformation != .none {
            writeColorTransformMarker(colorTransformation, to: writer)
        }
        
        // Apply forward colour transform to pixel data (modular arithmetic keeps
        // values within [0, MAXVAL] for storage in MultiComponentImageData).
        let maxValue = (1 << imageData.frameHeader.bitsPerSample) - 1
        let encodingData = colorTransformation != .none
            ? try applyForwardColorTransform(imageData, transformation: colorTransformation, maxValue: maxValue)
            : imageData
        
        // Write LSE type 4 (extended dimensions) before SOF when either dimension > 65535
        // per ITU-T.87 §5.1.1.4.
        let frame = encodingData.frameHeader
        if frame.width > 65535 || frame.height > 65535 {
            writeExtendedDimensions(frame, to: writer)
        }
        
        // Write frame header (SOF55)
        try writeFrameHeader(encodingData.frameHeader, to: writer)
        
        // Write preset parameters if custom or near-lossless
        let parameters = try configuration.presetParameters ?? JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: encodingData.frameHeader.bitsPerSample
        )
        
        if configuration.presetParameters != nil || configuration.near > 0 {
            try writePresetParameters(parameters, to: writer)
        }
        
        // Encode scan(s) based on interleave mode
        switch configuration.interleaveMode {
        case .none:
            // Non-interleaved: one scan per component
            for component in encodingData.components {
                try encodeScan(
                    imageData: encodingData,
                    componentIDs: [component.id],
                    configuration: configuration,
                    parameters: parameters,
                    writer: writer
                )
            }
            
        case .line, .sample:
            // Interleaved: single scan with all components
            let componentIDs = encodingData.components.map { $0.id }
            try encodeScan(
                imageData: encodingData,
                componentIDs: componentIDs,
                configuration: configuration,
                parameters: parameters,
                writer: writer
            )
        }
        
        // Write EOI marker (End of Image)
        writer.writeMarker(.endOfImage)
        
        return try writer.getData()
    }
    
    /// Convenience method to encode with individual parameters
    ///
    /// - Parameters:
    ///   - imageData: Multi-component image data to encode
    ///   - near: NEAR parameter (0 = lossless, 1-255 = near-lossless)
    ///   - interleaveMode: Interleaving mode
    /// - Returns: JPEG-LS encoded data
    /// - Throws: `JPEGLSError` if encoding fails
    public func encode(
        _ imageData: MultiComponentImageData,
        near: Int = 0,
        interleaveMode: JPEGLSInterleaveMode = .none
    ) throws -> Data {
        let config = try Configuration(near: near, interleaveMode: interleaveMode)
        return try encode(imageData, configuration: config)
    }
    
    // MARK: - Private Methods
    
    /// Write an APP8 "mrfx" colour-transform marker to the bitstream.
    ///
    /// Format per ISO/IEC 14495-2 Annex A:
    ///   FF E8  — APP8 marker
    ///   00 07  — segment length (7 bytes including the length field)
    ///   "mrfx" — four-byte identifier (0x6D 0x72 0x66 0x78)
    ///   id     — one-byte transform code (matches JPEGLSColorTransformation.rawValue)
    ///
    /// - Parameters:
    ///   - transformation: Colour transform to signal.
    ///   - writer: Destination bitstream writer.
    private func writeColorTransformMarker(
        _ transformation: JPEGLSColorTransformation,
        to writer: JPEGLSBitstreamWriter
    ) {
        var payload = Data()
        // "mrfx" identifier
        payload.append(0x6D)  // 'm'
        payload.append(0x72)  // 'r'
        payload.append(0x66)  // 'f'
        payload.append(0x78)  // 'x'
        // Transform ID
        payload.append(transformation.rawValue)
        writer.writeMarkerSegment(marker: .applicationMarker8, payload: payload)
    }
    
    /// Apply the forward colour transform to all pixels in the image.
    ///
    /// Returns a new `MultiComponentImageData` whose pixel values are the transformed
    /// versions of the originals.  Modular arithmetic is used so that every value
    /// stays within [0, maxValue] and can be stored in the pixel buffer without
    /// failing the range-validation checks.
    ///
    /// - Parameters:
    ///   - imageData: Original image data with untransformed pixels.
    ///   - transformation: Colour transform to apply.
    ///   - maxValue: MAXVAL for the image (used for modular arithmetic).
    /// - Returns: New image data with transformed pixels.
    /// - Throws: `JPEGLSError` if the transform is not valid for the component count.
    private func applyForwardColorTransform(
        _ imageData: MultiComponentImageData,
        transformation: JPEGLSColorTransformation,
        maxValue: Int
    ) throws -> MultiComponentImageData {
        guard transformation != .none else { return imageData }
        guard transformation.isValid(forComponentCount: imageData.frameHeader.componentCount) else {
            throw JPEGLSError.encodingFailed(
                reason: "Colour transformation \(transformation) is invalid for \(imageData.frameHeader.componentCount) components"
            )
        }
        
        let componentCount = imageData.components.count
        let height = imageData.frameHeader.height
        let width  = imageData.frameHeader.width
        
        // Build mutable per-component pixel arrays
        var transformedPixels = imageData.components.map { $0.pixels }
        
        // Transform each pixel position across all components simultaneously
        for row in 0..<height {
            for col in 0..<width {
                let original = (0..<componentCount).map { transformedPixels[$0][row][col] }
                let result = try transformation.transformForward(original, maxValue: maxValue)
                for idx in 0..<componentCount {
                    transformedPixels[idx][row][col] = result[idx]
                }
            }
        }
        
        // Reconstruct ComponentData array preserving component IDs
        let transformedComponents = imageData.components.enumerated().map { (idx, comp) in
            MultiComponentImageData.ComponentData(id: comp.id, pixels: transformedPixels[idx])
        }
        
        return try MultiComponentImageData(
            components: transformedComponents,
            frameHeader: imageData.frameHeader
        )
    }
    
    private func writeFrameHeader(
        _ frameHeader: JPEGLSFrameHeader,
        to writer: JPEGLSBitstreamWriter
    ) throws {
        writer.writeMarker(.startOfFrameJPEGLS)
        
        // Length: 8 + 3 * componentCount
        let length = UInt16(8 + 3 * frameHeader.componentCount)
        writer.writeUInt16(length)
        
        // Precision (bits per sample)
        writer.writeByte(UInt8(frameHeader.bitsPerSample))
        
        // Dimensions — use 0 for any dimension > 65535 (encoded in preceding LSE type 4)
        writer.writeUInt16(UInt16(frameHeader.height > 65535 ? 0 : frameHeader.height))
        writer.writeUInt16(UInt16(frameHeader.width  > 65535 ? 0 : frameHeader.width))
        
        // Component count
        writer.writeByte(UInt8(frameHeader.componentCount))
        
        // Component specifications
        for component in frameHeader.components {
            writer.writeByte(component.id)
            // Sampling factors combined into single byte: (H << 4) | V
            let samplingByte = (component.horizontalSamplingFactor << 4) | component.verticalSamplingFactor
            writer.writeByte(samplingByte)
            writer.writeByte(0)  // Quantization table ID (unused in JPEG-LS, always 0)
        }
    }
    
    /// Write preset parameters (LSE) to bitstream
    private func writePresetParameters(
        _ parameters: JPEGLSPresetParameters,
        to writer: JPEGLSBitstreamWriter
    ) throws {
        writer.writeMarker(.jpegLSExtension)
        
        // Length: 13 bytes (marker type + parameters)
        writer.writeUInt16(13)
        
        // LSE marker type: 1 (preset parameters)
        writer.writeByte(1)
        
        // MAXVAL
        writer.writeUInt16(UInt16(parameters.maxValue))
        
        // T1, T2, T3
        writer.writeUInt16(UInt16(parameters.threshold1))
        writer.writeUInt16(UInt16(parameters.threshold2))
        writer.writeUInt16(UInt16(parameters.threshold3))
        
        // RESET
        writer.writeUInt16(UInt16(parameters.reset))
    }
    
    /// Write extended dimensions LSE type 4 marker segment per ITU-T.87 §5.1.1.4.
    ///
    /// Emitted before the SOF marker when either image dimension exceeds 65535.
    /// The corresponding SOF fields for those dimensions will contain 0.
    ///
    /// - Parameters:
    ///   - frameHeader: Frame header whose dimensions should be encoded.
    ///   - writer: Destination bitstream writer.
    private func writeExtendedDimensions(_ frameHeader: JPEGLSFrameHeader, to writer: JPEGLSBitstreamWriter) {
        var payload = Data()
        payload.append(JPEGLSExtensionType.extendedDimensions.rawValue)  // Id = 0x04
        payload.append(4)  // Wxy = 4 (32-bit dimensions)
        // XSIZE (width) as 4 bytes big-endian
        payload.append(UInt8((frameHeader.width >> 24) & 0xFF))
        payload.append(UInt8((frameHeader.width >> 16) & 0xFF))
        payload.append(UInt8((frameHeader.width >> 8) & 0xFF))
        payload.append(UInt8(frameHeader.width & 0xFF))
        // YSIZE (height) as 4 bytes big-endian
        payload.append(UInt8((frameHeader.height >> 24) & 0xFF))
        payload.append(UInt8((frameHeader.height >> 16) & 0xFF))
        payload.append(UInt8((frameHeader.height >> 8) & 0xFF))
        payload.append(UInt8(frameHeader.height & 0xFF))
        writer.writeMarkerSegment(marker: .jpegLSExtension, payload: payload)
    }
    
    /// Write a mapping table (LSE type 2) to the bitstream.
    ///
    /// Emits an LSE marker segment containing the mapping table specification.
    /// If the table has more entries than can fit in a single LSE segment
    /// (maximum payload ≈ 65530 bytes), the remainder is emitted as LSE type 3
    /// (mapping table continuation) segments.
    ///
    /// - Parameters:
    ///   - table: The mapping table to write.
    ///   - writer: Destination bitstream writer.
    func writeMappingTable(
        _ table: JPEGLSMappingTable,
        to writer: JPEGLSBitstreamWriter
    ) {
        let entryWidth = table.entryWidth
        // Maximum entry bytes per segment. Ll is UInt16 (max 65535).
        // Overhead for type 2: 1 (Id) + 1 (TID) + 1 (Wt) = 3 bytes counted in Ll.
        // (Ll itself = 2 bytes also counted.) Max payload = 65535 - 2 - 3 = 65530 bytes.
        let maxDataBytesPerSegment = 65530
        let maxEntriesPerSegment = maxDataBytesPerSegment / entryWidth

        // Always emit at least one LSE type 2 segment (even for an empty table, to
        // declare the table ID and entry width).  Subsequent chunks are emitted as
        // LSE type 3 (mapping table continuation) segments.
        let chunks: [ArraySlice<Int>]
        if table.entries.isEmpty {
            chunks = [table.entries[0..<0]]
        } else {
            var slices: [ArraySlice<Int>] = []
            var start = 0
            while start < table.entries.count {
                let end = min(start + maxEntriesPerSegment, table.entries.count)
                slices.append(table.entries[start..<end])
                start = end
            }
            chunks = slices
        }

        for (chunkIndex, chunk) in chunks.enumerated() {
            // Build the segment payload without byte stuffing.
            // Marker-segment payloads are raw data; stuffing only applies to scan data.
            var payload = Data()
            if chunkIndex == 0 {
                // LSE type 2: Id + TID + Wt + entries
                payload.append(JPEGLSExtensionType.mappingTable.rawValue)
                payload.append(table.id)
                payload.append(UInt8(entryWidth))
            } else {
                // LSE type 3: Id + TID + entries
                payload.append(JPEGLSExtensionType.mappingTableContinuation.rawValue)
                payload.append(table.id)
            }
            for entry in chunk {
                if entryWidth == 1 {
                    payload.append(UInt8(entry & 0xFF))
                } else {
                    payload.append(UInt8((entry >> 8) & 0xFF))
                    payload.append(UInt8(entry & 0xFF))
                }
            }
            // writeMarkerSegment writes raw payload bytes without marker stuffing,
            // which is correct for all JPEG marker-segment payloads.
            writer.writeMarkerSegment(marker: .jpegLSExtension, payload: payload)
        }
    }
    
    /// Encode a single scan
    private func encodeScan(
        imageData: MultiComponentImageData,
        componentIDs: [UInt8],
        configuration: Configuration,
        parameters: JPEGLSPresetParameters,
        writer: JPEGLSBitstreamWriter
    ) throws {
        // Create scan header
        let scanHeader = try JPEGLSScanHeader(
            componentCount: componentIDs.count,
            components: componentIDs.map { id in
                JPEGLSScanHeader.ComponentSelector(id: id)
            },
            near: configuration.near,
            interleaveMode: configuration.interleaveMode,
            pointTransform: 0
        )
        
        // Write scan header (SOS)
        try writeScanHeader(scanHeader, to: writer)
        
        // Encode scan data
        try encodeScanData(
            imageData: imageData,
            scanHeader: scanHeader,
            parameters: parameters,
            writer: writer
        )
    }
    
    /// Write scan header (SOS) to bitstream
    private func writeScanHeader(
        _ scanHeader: JPEGLSScanHeader,
        to writer: JPEGLSBitstreamWriter
    ) throws {
        writer.writeMarker(.startOfScan)
        
        // Length: 6 + 2 * componentCount
        let length = UInt16(6 + 2 * scanHeader.componentCount)
        writer.writeUInt16(length)
        
        // Component count
        writer.writeByte(UInt8(scanHeader.componentCount))
        
        // Component selectors
        for component in scanHeader.components {
            writer.writeByte(component.id)
            // Tdi field: mapping table ID (0 = no mapping table) per ITU-T.87 §5.1.2.
            writer.writeByte(component.mappingTableID)
        }
        
        // NEAR parameter
        writer.writeByte(UInt8(scanHeader.near))
        
        // Interleave mode (ILV)
        let ilv: UInt8 = switch scanHeader.interleaveMode {
        case .none: 0
        case .line: 1
        case .sample: 2
        }
        writer.writeByte(ilv)
        
        // Point transform (0 for lossless)
        writer.writeByte(UInt8(scanHeader.pointTransform))
    }
    
    /// Encode scan data (the actual pixel encoding)
    private func encodeScanData(
        imageData: MultiComponentImageData,
        scanHeader: JPEGLSScanHeader,
        parameters: JPEGLSPresetParameters,
        writer: JPEGLSBitstreamWriter
    ) throws {
        // Create pixel buffer
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Create context model
        var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
        
        // Create regular mode encoder
        let regularMode = try JPEGLSRegularMode(
            parameters: parameters,
            near: scanHeader.near
        )
        
        // Create run mode encoder
        let runMode = try JPEGLSRunMode(
            parameters: parameters,
            near: scanHeader.near
        )
        
        // Compute Golomb-Rice LIMIT parameters per ITU-T.87 §4.4
        let (limit, qbppBits) = computeGolombLimit(parameters: parameters, near: scanHeader.near)
        
        // Encode based on interleave mode
        switch scanHeader.interleaveMode {
        case .none:
            try encodeNoneInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer,
                limit: limit,
                qbppBits: qbppBits
            )
            
        case .line:
            try encodeLineInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer,
                limit: limit,
                qbppBits: qbppBits
            )
            
        case .sample:
            try encodeSampleInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer,
                limit: limit,
                qbppBits: qbppBits
            )
        }
        
        // Flush any remaining bits
        writer.flush()
    }

    /// Compute the Golomb-Rice LIMIT and qbppBits for a scan per ITU-T.87 §4.4.
    ///
    /// - Parameters:
    ///   - parameters: Preset coding parameters
    ///   - near: Near-lossless parameter (0 for lossless)
    /// - Returns: Tuple of (limit, qbppBits)
    private func computeGolombLimit(
        parameters: JPEGLSPresetParameters,
        near: Int
    ) -> (limit: Int, qbppBits: Int) {
        let range: Int
        if near == 0 {
            range = parameters.maxValue + 1
        } else {
            let qstep = 2 * near + 1
            range = (parameters.maxValue + 2 * near) / qstep + 1
        }
        var qbppBits = 0
        var r = range - 1
        while r > 0 {
            qbppBits += 1
            r >>= 1
        }
        qbppBits = max(qbppBits, 2)
        let limit = 2 * (qbppBits + 8)
        return (limit, qbppBits)
    }
    
    /// Encode non-interleaved scan (component by component)
    private func encodeNoneInterleaved(
        buffer: JPEGLSPixelBuffer,
        scanHeader: JPEGLSScanHeader,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) throws {
        guard scanHeader.componentCount == 1 else {
            throw JPEGLSError.encodingFailed(
                reason: "Non-interleaved mode requires exactly 1 component per scan"
            )
        }
        
        let componentId = scanHeader.components[0].id
        let near = scanHeader.near
        
        // Track reconstructed values for near-lossless neighbour computation.
        // For lossless (NEAR = 0) this array is never read; for near-lossless it
        // stores what the decoder will reconstruct so that subsequent pixels use
        // the same context as the decoder.
        var reconstructed = Array(
            repeating: Array(repeating: 0, count: buffer.width),
            count: buffer.height
        )
        
        // Encode pixels in raster order with run mode support
        for row in 0..<buffer.height {
            // Per ITU-T.87 §4.5.1, RUNindex is reset to 0 at the start of each scan line.
            context.setRunIndex(0)
            var col = 0
            while col < buffer.width {
                guard let neighbors = buffer.getNeighbors(
                    componentId: componentId,
                    row: row,
                    column: col
                ) else {
                    throw JPEGLSError.encodingFailed(
                        reason: "Failed to get neighbors for pixel at (\(row), \(col))"
                    )
                }
                
                // Use reconstructed neighbours for near-lossless; originals for lossless.
                let (a, b, c, d): (Int, Int, Int, Int)
                if near > 0 {
                    (a, b, c, d) = computeReconstructedNeighbors(
                        from: reconstructed, row: row, col: col,
                        width: buffer.width, height: buffer.height
                    )
                } else {
                    (a, b, c, d) = (neighbors.left, neighbors.top, neighbors.topLeft, neighbors.topRight)
                }
                
                // Check for run mode: all quantized gradients are zero
                let (d1, d2, d3) = regularMode.computeGradients(a: a, b: b, c: c, d: d)
                let q1 = regularMode.quantizeGradient(d1)
                let q2 = regularMode.quantizeGradient(d2)
                let q3 = regularMode.quantizeGradient(d3)
                
                if q1 == 0 && q2 == 0 && q3 == 0 {
                    // Run mode: scan ahead for matching pixels.
                    // The run value is the reconstructed left neighbour (a).
                    let runValue = a
                    guard let componentPixels = buffer.getComponentPixels(componentId: componentId) else {
                        throw JPEGLSError.encodingFailed(reason: "Failed to get component pixels")
                    }
                    let linePixels = componentPixels[row]
                    let runLength = runMode.detectRunLength(
                        pixels: linePixels,
                        startIndex: col,
                        runValue: runValue
                    )
                    
                    let remainingInLine = buffer.width - col
                    let actualRunLength = min(runLength, remainingInLine)
                    
                    // Encode run length
                    let encoded = runMode.encodeRunLength(
                        runLength: actualRunLength,
                        runIndex: context.currentRunIndex
                    )
                    
                    // Write continuation bits (1s)
                    for _ in 0..<encoded.continuationBits {
                        writer.writeBits(1, count: 1)
                    }
                    
                    // Store the run value as reconstructed for every run pixel.
                    if near > 0 {
                        for runCol in col..<col + actualRunLength {
                            reconstructed[row][runCol] = runValue
                        }
                    }
                    
                    if actualRunLength < remainingInLine {
                        // Run was interrupted — write termination and remainder.
                        writeRunTermination(encoded: encoded, writer: writer)
                        
                        // Encode the interruption pixel
                        let interruptionCol = col + actualRunLength
                        if interruptionCol < buffer.width {
                            guard let interruptionNeighbors = buffer.getNeighbors(
                                componentId: componentId,
                                row: row,
                                column: interruptionCol
                            ) else {
                                throw JPEGLSError.encodingFailed(
                                    reason: "Failed to get neighbors for interruption pixel at (\(row), \(interruptionCol))"
                                )
                            }
                            
                            let interruption = runMode.encodeRunInterruption(
                                interruptionValue: interruptionNeighbors.actual,
                                runValue: runValue
                            )
                            
                            writeRunInterruptionBits(
                                mappedError: interruption.mappedError,
                                absError: abs(interruption.error),
                                context: &context,
                                regularMode: regularMode,
                                writer: writer,
                                limit: limit,
                                qbppBits: qbppBits
                            )
                            // Run interruption uses the exact (unquantised) original pixel
                            // value as its reconstructed value: the decoder will similarly
                            // reconstruct it without quantisation rounding.
                            if near > 0 {
                                reconstructed[row][interruptionCol] = interruptionNeighbors.actual
                            }
                            col = interruptionCol + 1
                        } else {
                            col = interruptionCol
                        }
                    } else {
                        // Run reaches end of line.  Only write the termination bit if
                        // there is a partial-block remainder — when the run exactly fills
                        // the line with full blocks the decoder exits the run-length loop
                        // at the last '1' bit and never reads a '0' terminator.
                        if encoded.remainder > 0 {
                            writeRunTermination(encoded: encoded, writer: writer)
                        }
                        col += actualRunLength
                    }
                    
                    // Update RUNindex to stay in sync with the decoder.
                    // The decoder increments runIndex after each '1' bit and decrements
                    // it when it reads the '0' terminator (interrupted runs and EOL with
                    // a partial block).  Exact-block EOL runs leave the index at the
                    // post-increment level.
                    let finalRunIndex = min(encoded.runIndex + encoded.continuationBits, 31)
                    if actualRunLength < remainingInLine || encoded.remainder > 0 {
                        context.setRunIndex(max(finalRunIndex - 1, 0))
                    } else {
                        context.setRunIndex(finalRunIndex)
                    }
                } else {
                    // Regular mode
                    let rv = encodePixel(
                        actual: neighbors.actual,
                        a: a, b: b, c: c, d: d,
                        regularMode: regularMode,
                        context: &context,
                        writer: writer,
                        limit: limit,
                        qbppBits: qbppBits
                    )
                    if near > 0 {
                        reconstructed[row][col] = rv
                    }
                    col += 1
                }
            }
        }
    }
    
    /// Encode line-interleaved scan
    private func encodeLineInterleaved(
        buffer: JPEGLSPixelBuffer,
        scanHeader: JPEGLSScanHeader,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) throws {
        // Encode line by line, all components per line
        for row in 0..<buffer.height {
            for component in scanHeader.components {
                // Per ITU-T.87 §4.5.1, RUNindex is reset to 0 at the start of each scan line.
                context.setRunIndex(0)
                var col = 0
                while col < buffer.width {
                    guard let neighbors = buffer.getNeighbors(
                        componentId: component.id,
                        row: row,
                        column: col
                    ) else {
                        throw JPEGLSError.encodingFailed(
                            reason: "Failed to get neighbors for pixel at (\(row), \(col))"
                        )
                    }
                    
                    // Check for run mode
                    let (d1, d2, d3) = regularMode.computeGradients(
                        a: neighbors.left, b: neighbors.top, c: neighbors.topLeft, d: neighbors.topRight
                    )
                    let q1 = regularMode.quantizeGradient(d1)
                    let q2 = regularMode.quantizeGradient(d2)
                    let q3 = regularMode.quantizeGradient(d3)
                    
                    if q1 == 0 && q2 == 0 && q3 == 0 {
                        // Run mode
                        let runValue = neighbors.left
                        guard let componentPixels = buffer.getComponentPixels(componentId: component.id) else {
                            throw JPEGLSError.encodingFailed(reason: "Failed to get component pixels")
                        }
                        let linePixels = componentPixels[row]
                        let runLength = runMode.detectRunLength(
                            pixels: linePixels,
                            startIndex: col,
                            runValue: runValue
                        )
                        
                        let remainingInLine = buffer.width - col
                        let actualRunLength = min(runLength, remainingInLine)
                        
                        let encoded = runMode.encodeRunLength(
                            runLength: actualRunLength,
                            runIndex: context.currentRunIndex
                        )
                        
                        for _ in 0..<encoded.continuationBits {
                            writer.writeBits(1, count: 1)
                        }
                        
                        if actualRunLength < remainingInLine {
                            writeRunTermination(encoded: encoded, writer: writer)
                            
                            let interruptionCol = col + actualRunLength
                            if interruptionCol < buffer.width {
                                guard let interruptionNeighbors = buffer.getNeighbors(
                                    componentId: component.id,
                                    row: row,
                                    column: interruptionCol
                                ) else {
                                    throw JPEGLSError.encodingFailed(
                                        reason: "Failed to get neighbors for interruption pixel"
                                    )
                                }
                                
                                let interruption = runMode.encodeRunInterruption(
                                    interruptionValue: interruptionNeighbors.actual,
                                    runValue: runValue
                                )
                                
                                writeRunInterruptionBits(
                                    mappedError: interruption.mappedError,
                                    absError: abs(interruption.error),
                                    context: &context,
                                    regularMode: regularMode,
                                    writer: writer,
                                    limit: limit,
                                    qbppBits: qbppBits
                                )
                                
                                col = interruptionCol + 1
                            } else {
                                col = interruptionCol
                            }
                        } else {
                            // EOL: only write the terminator when there is a partial-block
                            // remainder — exact-block EOL runs need no terminator.
                            if encoded.remainder > 0 {
                                writeRunTermination(encoded: encoded, writer: writer)
                            }
                            col += actualRunLength
                        }
                        
                        // Synchronise RUNindex with the decoder.
                        let finalRunIndex = min(encoded.runIndex + encoded.continuationBits, 31)
                        if actualRunLength < remainingInLine || encoded.remainder > 0 {
                            context.setRunIndex(max(finalRunIndex - 1, 0))
                        } else {
                            context.setRunIndex(finalRunIndex)
                        }
                    } else {
                        // Regular mode
                        encodePixel(
                            actual: neighbors.actual,
                            a: neighbors.left,
                            b: neighbors.top,
                            c: neighbors.topLeft,
                            d: neighbors.topRight,
                            regularMode: regularMode,
                            context: &context,
                            writer: writer,
                            limit: limit,
                            qbppBits: qbppBits
                        )
                        col += 1
                    }
                }
            }
        }
    }
    
    /// Encode sample-interleaved scan
    ///
    /// Per ITU-T.87 §C.5, run mode is entered when ALL components at a sample
    /// position have zero quantised gradients.  A single run length is then
    /// written for all components, and each component's interruption sample is
    /// encoded individually after the run.
    private func encodeSampleInterleaved(
        buffer: JPEGLSPixelBuffer,
        scanHeader: JPEGLSScanHeader,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) throws {
        let components = scanHeader.components

        // Encode row by row
        for row in 0..<buffer.height {
            // Per ITU-T.87 §4.5.1, RUNindex is reset to 0 at the start of each scan line.
            context.setRunIndex(0)
            var col = 0
            while col < buffer.width {
                // Check if ALL components have zero quantised gradients at (row, col)
                var allGradientsZero = true
                for component in components {
                    guard let neighbors = buffer.getNeighbors(
                        componentId: component.id, row: row, column: col
                    ) else {
                        throw JPEGLSError.encodingFailed(
                            reason: "Failed to get neighbors for pixel at (\(row), \(col))"
                        )
                    }
                    let (d1, d2, d3) = regularMode.computeGradients(
                        a: neighbors.left, b: neighbors.top,
                        c: neighbors.topLeft, d: neighbors.topRight
                    )
                    if regularMode.quantizeGradient(d1) != 0 ||
                       regularMode.quantizeGradient(d2) != 0 ||
                       regularMode.quantizeGradient(d3) != 0 {
                        allGradientsZero = false
                        break
                    }
                }

                if allGradientsZero {
                    // Run mode: detect the run length across all components simultaneously.
                    // The run continues while every component's pixel equals its run value.
                    var runValue: [Int] = []
                    var componentLinePixels: [[Int]] = []
                    for component in components {
                        guard let neighbors = buffer.getNeighbors(
                            componentId: component.id, row: row, column: col
                        ) else {
                            throw JPEGLSError.encodingFailed(
                                reason: "Failed to get neighbors for run at (\(row), \(col))"
                            )
                        }
                        runValue.append(neighbors.left)
                        guard let allPixels = buffer.getComponentPixels(componentId: component.id) else {
                            throw JPEGLSError.encodingFailed(reason: "Failed to get component pixels")
                        }
                        componentLinePixels.append(allPixels[row])
                    }

                    // Detect run: the minimum run length across all components
                    let remainingInLine = buffer.width - col
                    var runLength = remainingInLine
                    for (cIdx, linePixels) in componentLinePixels.enumerated() {
                        let compRun = runMode.detectRunLength(
                            pixels: linePixels,
                            startIndex: col,
                            runValue: runValue[cIdx]
                        )
                        runLength = min(runLength, compRun)
                    }
                    let actualRunLength = min(runLength, remainingInLine)

                    // Encode run length (same encoding as non-interleaved/line-interleaved)
                    let encoded = runMode.encodeRunLength(
                        runLength: actualRunLength,
                        runIndex: context.currentRunIndex
                    )
                    for _ in 0..<encoded.continuationBits {
                        writer.writeBits(1, count: 1)
                    }

                    if actualRunLength < remainingInLine {
                        // Run interrupted — write termination and remainder
                        writeRunTermination(encoded: encoded, writer: writer)

                        // Encode interruption pixel for EACH component independently
                        let interruptionCol = col + actualRunLength
                        if interruptionCol < buffer.width {
                            for (cIdx, component) in components.enumerated() {
                                guard let intNeighbors = buffer.getNeighbors(
                                    componentId: component.id,
                                    row: row, column: interruptionCol
                                ) else {
                                    throw JPEGLSError.encodingFailed(
                                        reason: "Failed to get interruption neighbors"
                                    )
                                }
                                let interruption = runMode.encodeRunInterruption(
                                    interruptionValue: intNeighbors.actual,
                                    runValue: runValue[cIdx]
                                )
                                writeRunInterruptionBits(
                                    mappedError: interruption.mappedError,
                                    absError: abs(interruption.error),
                                    context: &context,
                                    regularMode: regularMode,
                                    writer: writer,
                                    limit: limit,
                                    qbppBits: qbppBits
                                )
                            }
                            col = interruptionCol + 1
                        } else {
                            col = interruptionCol
                        }
                    } else {
                        if encoded.remainder > 0 {
                            writeRunTermination(encoded: encoded, writer: writer)
                        }
                        col += actualRunLength
                    }

                    // Synchronise RUNindex with the decoder
                    let finalRunIndex = min(encoded.runIndex + encoded.continuationBits, 31)
                    if actualRunLength < remainingInLine || encoded.remainder > 0 {
                        context.setRunIndex(max(finalRunIndex - 1, 0))
                    } else {
                        context.setRunIndex(finalRunIndex)
                    }
                } else {
                    // Regular mode: encode each component at (row, col)
                    for component in components {
                        guard let neighbors = buffer.getNeighbors(
                            componentId: component.id, row: row, column: col
                        ) else {
                            throw JPEGLSError.encodingFailed(
                                reason: "Failed to get neighbors for pixel at (\(row), \(col))"
                            )
                        }
                        encodePixel(
                            actual: neighbors.actual,
                            a: neighbors.left,
                            b: neighbors.top,
                            c: neighbors.topLeft,
                            d: neighbors.topRight,
                            regularMode: regularMode,
                            context: &context,
                            writer: writer,
                            limit: limit,
                            qbppBits: qbppBits
                        )
                    }
                    col += 1
                }
            }
        }
    }
    
    /// Compute boundary-condition-aware neighbours from a reconstructed-value buffer.
    ///
    /// Mirrors the boundary conditions applied by `JPEGLSPixelBuffer.getNeighbors`
    /// but operates on the encoder's local reconstructed-value array, which is
    /// populated during near-lossless encoding to track the values that the decoder
    /// will reconstruct.
    ///
    /// - Returns: Tuple (a, b, c, d) = (left, top, topLeft, topRight) neighbours.
    private func computeReconstructedNeighbors(
        from reconstructed: [[Int]],
        row: Int,
        col: Int,
        width: Int,
        height: Int
    ) -> (a: Int, b: Int, c: Int, d: Int) {
        if row == 0 && col == 0 {
            return (0, 0, 0, 0)
        } else if row == 0 {
            let left = reconstructed[row][col - 1]
            return (left, left, left, left)
        } else if col == 0 {
            let top = reconstructed[row - 1][col]
            let topRight = (width > 1) ? reconstructed[row - 1][col + 1] : top
            return (top, top, top, topRight)
        } else {
            let left = reconstructed[row][col - 1]
            let top = reconstructed[row - 1][col]
            let topLeft = reconstructed[row - 1][col - 1]
            let topRight = (col + 1 < width) ? reconstructed[row - 1][col + 1] : top
            return (left, top, topLeft, topRight)
        }
    }
    
    /// Encode a single pixel in regular mode and return its reconstructed value.
    ///
    /// Takes pre-computed neighbour values so that the caller can supply either
    /// original or reconstructed neighbours as appropriate (e.g. for near-lossless
    /// mode the encoder passes reconstructed neighbours; for lossless it uses the
    /// original pixel values directly).
    ///
    /// - Returns: The reconstructed sample value that the decoder will produce,
    ///   which the caller should store for use as a neighbour in subsequent pixels
    ///   when operating in near-lossless mode.
    @discardableResult
    private func encodePixel(
        actual: Int,
        a: Int,
        b: Int,
        c: Int,
        d: Int,
        regularMode: JPEGLSRegularMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) -> Int {
        // Regular mode encoding
        let encodedPixel = regularMode.encodePixel(
            actual: actual,
            a: a,
            b: b,
            c: c,
            d: d,
            context: context
        )
        
        // Write Golomb-Rice encoded bits
        writeRegularModeBits(encodedPixel, to: writer, limit: limit, qbppBits: qbppBits)
        
        // Update context
        context.updateContext(
            contextIndex: encodedPixel.contextIndex,
            predictionError: encodedPixel.error,
            sign: encodedPixel.sign
        )
        
        return encodedPixel.reconstructedValue
    }
    
    /// Write regular mode encoded bits to bitstream, implementing the Golomb-Rice
    /// LIMIT per ITU-T.87 §6.1.1.  When the unary prefix would equal or exceed
    /// (LIMIT − qbppBits − 1), the limited binary code is written instead:
    /// (LIMIT − qbppBits − 1) zero bits, then '1', then qbppBits bits for MErrval − 1.
    private func writeRegularModeBits(
        _ encoded: EncodedPixel,
        to writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) {
        let limitThreshold = limit - qbppBits - 1
        if encoded.unaryLength >= limitThreshold {
            // Limited binary code
            for _ in 0..<limitThreshold { writer.writeBits(0, count: 1) }
            writer.writeBits(1, count: 1)
            writer.writeBits(UInt32(encoded.mappedError - 1), count: qbppBits)
        } else {
            // Standard Golomb-Rice code
            for _ in 0..<encoded.unaryLength { writer.writeBits(0, count: 1) }
            writer.writeBits(1, count: 1)
            if encoded.golombK > 0 {
                writer.writeBits(UInt32(encoded.remainder), count: encoded.golombK)
            }
        }
    }
    
    /// Write run interruption error to bitstream using adaptive Golomb-Rice encoding,
    /// implementing the LIMIT per ITU-T.87 §4.5.3 and §6.1.1.
    ///
    /// - Parameters:
    ///   - mappedError: Non-negative mapped prediction error (MErrval)
    ///   - absError: Absolute value of the signed prediction error (for context update)
    ///   - context: Context model (provides and receives run interruption stats)
    ///   - regularMode: Regular mode encoder (provides golombEncode helper)
    ///   - writer: Bitstream writer
    ///   - limit: LIMIT = 2 × (qbppBits + 8)
    ///   - qbppBits: ⌈log₂(RANGE)⌉
    private func writeRunInterruptionBits(
        mappedError: Int,
        absError: Int,
        context: inout JPEGLSContextModel,
        regularMode: JPEGLSRegularMode,
        writer: JPEGLSBitstreamWriter,
        limit: Int,
        qbppBits: Int
    ) {
        let k = context.computeRunInterruptionGolombK()
        let (unaryLength, remainder) = regularMode.golombEncode(value: mappedError, k: k)
        let limitThreshold = limit - qbppBits - 1
        if unaryLength >= limitThreshold {
            // Limited binary code
            for _ in 0..<limitThreshold { writer.writeBits(0, count: 1) }
            writer.writeBits(1, count: 1)
            writer.writeBits(UInt32(mappedError - 1), count: qbppBits)
        } else {
            for _ in 0..<unaryLength { writer.writeBits(0, count: 1) }
            writer.writeBits(1, count: 1)
            if k > 0 {
                writer.writeBits(UInt32(remainder), count: k)
            }
        }
        // Update run interruption context statistics per ITU-T.87 §4.5.3
        context.updateRunInterruptionContext(absError: absError)
    }
    
    /// Write run termination and remainder bits to bitstream
    private func writeRunTermination(
        encoded: EncodedRun,
        writer: JPEGLSBitstreamWriter
    ) {
        writer.writeBits(0, count: 1)  // Termination bit
        if encoded.j > 0 {
            writer.writeBits(UInt32(encoded.remainder), count: encoded.j)
        }
    }
}
