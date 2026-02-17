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
        
        /// Initialize encoding configuration
        ///
        /// - Parameters:
        ///   - near: NEAR parameter (0 = lossless, 1-255 = near-lossless)
        ///   - interleaveMode: Interleaving mode for multi-component images
        ///   - presetParameters: Optional custom preset parameters (uses defaults if nil)
        /// - Throws: `JPEGLSError.invalidNearParameter` if NEAR is out of range
        public init(
            near: Int = 0,
            interleaveMode: JPEGLSInterleaveMode = .none,
            presetParameters: JPEGLSPresetParameters? = nil
        ) throws {
            guard near >= 0 && near <= 255 else {
                throw JPEGLSError.invalidNearParameter(near: near)
            }
            
            self.near = near
            self.interleaveMode = interleaveMode
            self.presetParameters = presetParameters
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
        
        // Write frame header (SOF55)
        try writeFrameHeader(imageData.frameHeader, to: writer)
        
        // Write preset parameters if custom or near-lossless
        let parameters = try configuration.presetParameters ?? JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: imageData.frameHeader.bitsPerSample
        )
        
        if configuration.presetParameters != nil || configuration.near > 0 {
            try writePresetParameters(parameters, to: writer)
        }
        
        // Encode scan(s) based on interleave mode
        switch configuration.interleaveMode {
        case .none:
            // Non-interleaved: one scan per component
            for component in imageData.components {
                try encodeScan(
                    imageData: imageData,
                    componentIDs: [component.id],
                    configuration: configuration,
                    parameters: parameters,
                    writer: writer
                )
            }
            
        case .line, .sample:
            // Interleaved: single scan with all components
            let componentIDs = imageData.components.map { $0.id }
            try encodeScan(
                imageData: imageData,
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
        
        // Dimensions
        writer.writeUInt16(UInt16(frameHeader.height))
        writer.writeUInt16(UInt16(frameHeader.width))
        
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
        
        // Length: 11 bytes (marker type + parameters)
        writer.writeUInt16(11)
        
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
            writer.writeByte(0)  // Mapping table selector (unused in JPEG-LS)
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
        var context = try JPEGLSContextModel(parameters: parameters)
        
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
        
        // Encode pixels in raster order
        for row in 0..<buffer.height {
            for col in 0..<buffer.width {
                try encodePixel(
                    buffer: buffer,
                    componentId: componentId,
                    row: row,
                    column: col,
                    regularMode: regularMode,
                    runMode: runMode,
                    context: &context,
                    writer: writer,
                    near: scanHeader.near
                )
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
                for col in 0..<buffer.width {
                    try encodePixel(
                        buffer: buffer,
                        componentId: component.id,
                        row: row,
                        column: col,
                        regularMode: regularMode,
                        runMode: runMode,
                        context: &context,
                        writer: writer,
                        near: scanHeader.near
                    )
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
                    try encodePixel(
                        buffer: buffer,
                        componentId: component.id,
                        row: row,
                        column: col,
                        regularMode: regularMode,
                        runMode: runMode,
                        context: &context,
                        writer: writer,
                        near: scanHeader.near
                    )
                }
            }
        }
    }
    
    /// Encode a single pixel (regular mode only for now)
    private func encodePixel(
        buffer: JPEGLSPixelBuffer,
        componentId: UInt8,
        row: Int,
        column: Int,
        regularMode: JPEGLSRegularMode,
        runMode: JPEGLSRunMode,
        context: inout JPEGLSContextModel,
        writer: JPEGLSBitstreamWriter,
        near: Int
    ) throws {
        guard let neighbors = buffer.getNeighbors(
            componentId: componentId,
            row: row,
            column: column
        ) else {
            throw JPEGLSError.encodingFailed(
                reason: "Failed to get neighbors for pixel at (\(row), \(column))"
            )
        }
        
        // TODO: Implement run mode encoding
        // For now, only use regular mode
        
        // Regular mode encoding
        let encodedPixel = regularMode.encodePixel(
            actual: neighbors.actual,
            a: neighbors.left,
            b: neighbors.top,
            c: neighbors.topLeft,
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
}
