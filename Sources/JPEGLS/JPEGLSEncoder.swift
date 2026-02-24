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
        
        /// Colour transformation for multi-component images (default: none)
        ///
        /// When set to a non-none value, the encoder applies the forward colour transformation
        /// (HP1, HP2, or HP3) to the pixel data before JPEG-LS encoding and writes an APP8
        /// marker with the "mrfx" signature so decoders can identify and invert the transform.
        /// Only applicable for images with exactly 3 components (e.g. RGB).
        public let colorTransformation: JPEGLSColorTransformation
        
        /// Initialize encoding configuration
        ///
        /// - Parameters:
        ///   - near: NEAR parameter (0 = lossless, 1-255 = near-lossless)
        ///   - interleaveMode: Interleaving mode for multi-component images
        ///   - presetParameters: Optional custom preset parameters (uses defaults if nil)
        ///   - colorTransformation: Colour transformation for 3-component images (default: none)
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
        
        // Write APP8 "mrfx" colour transform marker (ITU-T T.870 Annex A) before SOF
        // when a non-identity colour transformation is requested.
        if configuration.colorTransformation != .none {
            writeColorTransformMarker(configuration.colorTransformation, to: writer)
        }
        
        // Apply forward colour transformation to the pixel data when requested.
        // The transform is applied per-pixel across all three components, with values
        // reduced modulo (MAXVAL+1) so they remain in [0, MAXVAL] (ITU-T T.870 §A.2).
        let maxValue = (1 << imageData.frameHeader.bitsPerSample) - 1
        let encodingData: MultiComponentImageData
        if configuration.colorTransformation != .none && imageData.components.count == 3 {
            encodingData = try applyForwardColorTransform(
                to: imageData,
                transform: configuration.colorTransformation,
                maxValue: maxValue
            )
        } else {
            encodingData = imageData
        }
        
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
    
    /// Write APP8 "mrfx" colour transform marker (ITU-T T.870 Annex A).
    ///
    /// The APP8 marker with the "mrfx" identifier is the Part 2 mechanism for embedding
    /// the colour transform ID in the JPEG-LS bitstream so decoders can automatically
    /// apply the correct inverse transform.
    ///
    /// Format: FF E8 [length 2B] 6D 72 66 78 [transformId 1B]
    /// where "mrfx" = 0x6D 0x72 0x66 0x78.
    ///
    /// - Parameters:
    ///   - transform: Colour transformation to signal
    ///   - writer: Destination bitstream writer
    private func writeColorTransformMarker(
        _ transform: JPEGLSColorTransformation,
        to writer: JPEGLSBitstreamWriter
    ) {
        // Payload: "mrfx" (4 bytes) + transform ID (1 byte)
        var payload = Data()
        payload.append(0x6D)  // 'm'
        payload.append(0x72)  // 'r'
        payload.append(0x66)  // 'f'
        payload.append(0x78)  // 'x'
        payload.append(transform.rawValue)
        writer.writeMarkerSegment(marker: .applicationMarker8, payload: payload)
    }
    
    /// Apply the forward colour transformation to all pixels in the image data.
    ///
    /// Each pixel's three components are transformed per the selected transform type.
    /// Values are reduced modulo `maxValue + 1` so the output stays in `[0, maxValue]`.
    ///
    /// - Parameters:
    ///   - imageData: Source image data (must have exactly 3 components)
    ///   - transform: Colour transformation to apply
    ///   - maxValue: Maximum sample value (e.g. 255 for 8-bit images)
    /// - Returns: New `MultiComponentImageData` with transformed pixel values
    /// - Throws: `JPEGLSError` if the transform or data structure is invalid
    private func applyForwardColorTransform(
        to imageData: MultiComponentImageData,
        transform: JPEGLSColorTransformation,
        maxValue: Int
    ) throws -> MultiComponentImageData {
        let height = imageData.frameHeader.height
        let width = imageData.frameHeader.width
        
        var c0 = imageData.components[0].pixels
        var c1 = imageData.components[1].pixels
        var c2 = imageData.components[2].pixels
        
        for row in 0..<height {
            for col in 0..<width {
                let transformed = try transform.transformForward(
                    [c0[row][col], c1[row][col], c2[row][col]],
                    maxValue: maxValue
                )
                c0[row][col] = transformed[0]
                c1[row][col] = transformed[1]
                c2[row][col] = transformed[2]
            }
        }
        
        return try MultiComponentImageData(
            components: [
                MultiComponentImageData.ComponentData(id: imageData.components[0].id, pixels: c0),
                MultiComponentImageData.ComponentData(id: imageData.components[1].id, pixels: c1),
                MultiComponentImageData.ComponentData(id: imageData.components[2].id, pixels: c2)
            ],
            frameHeader: imageData.frameHeader
        )
    }
    
    /// Write frame header (SOF55) to bitstream
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
        
        // Encode based on interleave mode
        switch scanHeader.interleaveMode {
        case .none:
            try encodeNoneInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer
            )
            
        case .line:
            try encodeLineInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer
            )
            
        case .sample:
            try encodeSampleInterleaved(
                buffer: buffer,
                scanHeader: scanHeader,
                regularMode: regularMode,
                runMode: runMode,
                context: &context,
                writer: writer
            )
        }
        
        // Flush any remaining bits
        writer.flush()
    }
    
    /// Encode non-interleaved scan (component by component)
    private func encodeNoneInterleaved(
        buffer: JPEGLSPixelBuffer,
        scanHeader: JPEGLSScanHeader,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter
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
                                writer: writer
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
                        writer: writer
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
        writer: JPEGLSBitstreamWriter
    ) throws {
        // Encode line by line, all components per line
        for row in 0..<buffer.height {
            for component in scanHeader.components {
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
                                    writer: writer
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
                            writer: writer
                        )
                        col += 1
                    }
                }
            }
        }
    }
    
    /// Encode sample-interleaved scan
    private func encodeSampleInterleaved(
        buffer: JPEGLSPixelBuffer,
        scanHeader: JPEGLSScanHeader,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter
    ) throws {
        // Encode sample by sample, all components per pixel
        for row in 0..<buffer.height {
            for col in 0..<buffer.width {
                for component in scanHeader.components {
                    guard let neighbors = buffer.getNeighbors(
                        componentId: component.id,
                        row: row,
                        column: col
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
                        writer: writer
                    )
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
        writer: JPEGLSBitstreamWriter
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
        writeRegularModeBits(encodedPixel, to: writer)
        
        // Update context
        context.updateContext(
            contextIndex: encodedPixel.contextIndex,
            predictionError: encodedPixel.error,
            sign: encodedPixel.sign
        )
        
        return encodedPixel.reconstructedValue
    }
    
    /// Write regular mode encoded bits to bitstream
    private func writeRegularModeBits(
        _ encoded: EncodedPixel,
        to writer: JPEGLSBitstreamWriter
    ) {
        // Write unary prefix (quotient)
        for _ in 0..<encoded.unaryLength {
            writer.writeBits(0, count: 1)
        }
        writer.writeBits(1, count: 1)  // Terminating 1
        
        // Write remainder (k bits)
        if encoded.golombK > 0 {
            writer.writeBits(UInt32(encoded.remainder), count: encoded.golombK)
        }
    }
    
    /// Write run interruption error to bitstream using adaptive Golomb-Rice encoding.
    ///
    /// Uses the run interruption context statistics from `context` to compute the
    /// Golomb-Rice parameter k per ITU-T.87 §4.5.3, then updates the context
    /// statistics with the absolute prediction error.
    ///
    /// - Parameters:
    ///   - mappedError: Non-negative mapped prediction error (MErrval)
    ///   - absError: Absolute value of the signed prediction error (for context update)
    ///   - context: Context model (provides and receives run interruption stats)
    ///   - regularMode: Regular mode encoder (provides golombEncode helper)
    ///   - writer: Bitstream writer
    private func writeRunInterruptionBits(
        mappedError: Int,
        absError: Int,
        context: inout JPEGLSContextModel,
        regularMode: JPEGLSRegularMode,
        writer: JPEGLSBitstreamWriter
    ) {
        let k = context.computeRunInterruptionGolombK()
        let (unaryLength, remainder) = regularMode.golombEncode(value: mappedError, k: k)
        for _ in 0..<unaryLength {
            writer.writeBits(0, count: 1)
        }
        writer.writeBits(1, count: 1)
        if k > 0 {
            writer.writeBits(UInt32(remainder), count: k)
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
