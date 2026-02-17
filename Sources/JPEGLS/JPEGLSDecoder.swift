/// High-level JPEG-LS decoder API
///
/// Provides a simple interface to decode JPEG-LS encoded data to raw pixel data.
/// Handles all aspects of JPEG-LS file decoding including marker parsing, bitstream
/// reading, and pixel reconstruction.

import Foundation

/// High-level JPEG-LS decoder
///
/// Decodes JPEG-LS encoded data to multi-component image data per ITU-T.87.
/// Supports all decoding modes (lossless, near-lossless) and interleaving modes.
///
/// **Example usage:**
/// ```swift
/// // Create decoder
/// let decoder = JPEGLSDecoder()
///
/// // Decode JPEG-LS file
/// let imageData = try decoder.decode(jpegLSData)
///
/// // Access pixel data
/// let pixels = imageData.components[0].pixels
/// ```
public struct JPEGLSDecoder: Sendable {
    /// Initialize decoder
    public init() {}
    
    /// Decode JPEG-LS data to pixel data
    ///
    /// - Parameter data: JPEG-LS encoded data
    /// - Returns: Decoded multi-component image data
    /// - Throws: `JPEGLSError` if decoding fails
    public func decode(_ data: Data) throws -> MultiComponentImageData {
        // Parse JPEG-LS structure
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        // Get preset parameters (default or custom)
        let parameters = try parseResult.presetParameters ?? JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: parseResult.frameHeader.bitsPerSample
        )
        
        // Extract scan data from bitstream
        let scanDataList = try extractScanData(from: data, parseResult: parseResult)
        
        // Validate we have the expected number of scans
        guard scanDataList.count == parseResult.scanHeaders.count else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Scan data count (\(scanDataList.count)) doesn't match scan header count (\(parseResult.scanHeaders.count))"
            )
        }
        
        // Decode based on interleave mode
        guard let firstScanHeader = parseResult.scanHeaders.first else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "No scan headers found")
        }
        
        let decodedComponents: [MultiComponentImageData.ComponentData]
        
        switch firstScanHeader.interleaveMode {
        case .none:
            // Non-interleaved: one scan per component
            decodedComponents = try decodeNoneInterleaved(
                frameHeader: parseResult.frameHeader,
                scanHeaders: parseResult.scanHeaders,
                scanDataList: scanDataList,
                parameters: parameters
            )
            
        case .line:
            // Line-interleaved: all components in one scan, line by line
            decodedComponents = try decodeLineInterleaved(
                frameHeader: parseResult.frameHeader,
                scanHeader: firstScanHeader,
                scanData: scanDataList[0],
                parameters: parameters
            )
            
        case .sample:
            // Sample-interleaved: all components in one scan, pixel by pixel
            decodedComponents = try decodeSampleInterleaved(
                frameHeader: parseResult.frameHeader,
                scanHeader: firstScanHeader,
                scanData: scanDataList[0],
                parameters: parameters
            )
        }
        
        // Create result
        return try MultiComponentImageData(
            components: decodedComponents,
            frameHeader: parseResult.frameHeader
        )
    }
    
    // MARK: - Scan Data Extraction
    
    /// Extract compressed scan data from JPEG-LS file
    ///
    /// Locates and extracts the bitstream data between SOS marker content and next marker/EOI for each scan.
    ///
    /// - Parameters:
    ///   - data: Complete JPEG-LS file data
    ///   - parseResult: Parsed structure information
    /// - Returns: Array of scan data buffers
    /// - Throws: `JPEGLSError` if scan data cannot be extracted
    private func extractScanData(from data: Data, parseResult: JPEGLSParseResult) throws -> [Data] {
        var scanDataList: [Data] = []
        var position = 0
        let expectedScans = parseResult.scanHeaders.count
        
        // Parse through the file looking for SOS markers
        while position < data.count - 1 && scanDataList.count < expectedScans {
            // Look for marker prefix
            if data[position] == 0xFF {
                let markerCode = data[position + 1]
                
                // Check if this is a SOS marker
                if markerCode == JPEGLSMarker.startOfScan.rawValue {
                    // Skip marker (2 bytes)
                    position += 2
                    
                    // Read and skip SOS segment length and content
                    guard position + 2 <= data.count else {
                        throw JPEGLSError.prematureEndOfStream
                    }
                    let sosLength = Int(data[position]) << 8 | Int(data[position + 1])
                    position += sosLength
                    
                    // Now at start of scan data
                    let scanDataStart = position
                    
                    // Find end of scan data (next VALID marker, not byte stuffing)
                    // Extended stuffing rules for CharLS compatibility:
                    //   - FF 00: Standard byte stuffing
                    //   - FF 60-7F: CharLS escapes
                    //   - FF XX where XX is not a valid marker: CharLS extended stuffing
                    var scanDataEnd = position
                    while scanDataEnd < data.count - 1 {
                        if data[scanDataEnd] == 0xFF {
                            let nextByte = data[scanDataEnd + 1]
                            
                            // Check if nextByte is a valid JPEG-LS marker
                            let isValidMarker = JPEGLSMarker(rawValue: nextByte) != nil
                            let isStuffing = nextByte == 0x00 || 
                                           (nextByte >= 0x60 && nextByte <= 0x7F) ||
                                           !isValidMarker
                            
                            if !isStuffing {
                                // Valid marker - scan data ends here
                                break
                            }
                            // Stuffing - skip both bytes and continue
                            scanDataEnd += 2
                        } else {
                            scanDataEnd += 1
                        }
                    }
                    
                    // Extract scan data (including byte stuffing - decoder will handle it)
                    let scanData = data[scanDataStart..<scanDataEnd]
                    scanDataList.append(Data(scanData))
                    
                    position = scanDataEnd
                } else {
                    // Some other marker - skip it
                    position += 1
                }
            } else {
                position += 1
            }
        }
        
        guard scanDataList.count == expectedScans else {
            throw JPEGLSError.invalidBitstreamStructure(
                reason: "Expected \(expectedScans) scans, found \(scanDataList.count)"
            )
        }
        
        return scanDataList
    }
    
    // MARK: - Non-Interleaved Decoding
    
    /// Decode non-interleaved image (one scan per component)
    private func decodeNoneInterleaved(
        frameHeader: JPEGLSFrameHeader,
        scanHeaders: [JPEGLSScanHeader],
        scanDataList: [Data],
        parameters: JPEGLSPresetParameters
    ) throws -> [MultiComponentImageData.ComponentData] {
        var components: [MultiComponentImageData.ComponentData] = []
        
        for (scanIndex, scanHeader) in scanHeaders.enumerated() {
            let scanData = scanDataList[scanIndex]
            let reader = JPEGLSBitstreamReader(data: scanData)
            
            // Decode this component
            let pixels = try decodeComponent(
                reader: reader,
                width: frameHeader.width,
                height: frameHeader.height,
                scanHeader: scanHeader,
                parameters: parameters
            )
            
            components.append(MultiComponentImageData.ComponentData(
                id: scanHeader.components[0].id,
                pixels: pixels
            ))
        }
        
        return components
    }
    
    // MARK: - Line-Interleaved Decoding
    
    /// Decode line-interleaved image (all components in one scan, line by line)
    private func decodeLineInterleaved(
        frameHeader: JPEGLSFrameHeader,
        scanHeader: JPEGLSScanHeader,
        scanData: Data,
        parameters: JPEGLSPresetParameters
    ) throws -> [MultiComponentImageData.ComponentData] {
        let reader = JPEGLSBitstreamReader(data: scanData)
        let componentCount = scanHeader.componentCount
        
        // Initialize pixel buffers for all components
        var componentPixels = (0..<componentCount).map { componentId in
            return Array(repeating: Array(repeating: 0, count: frameHeader.width), count: frameHeader.height)
        }
        
        // Initialize shared decoder and context (one context shared across all components in interleaved mode)
        let decoder = try JPEGLSRegularModeDecoder(parameters: parameters, near: scanHeader.near)
        let runDecoder = try JPEGLSRunModeDecoder(parameters: parameters, near: scanHeader.near)
        var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
        
        // Decode line by line, all components per line
        for row in 0..<frameHeader.height {
            for componentIndex in 0..<componentCount {
                // Decode one line for this component
                try decodeLineForComponent(
                    reader: reader,
                    pixels: &componentPixels[componentIndex],
                    row: row,
                    width: frameHeader.width,
                    decoder: decoder,
                    runDecoder: runDecoder,
                    context: &context,
                    scanHeader: scanHeader,
                    parameters: parameters
                )
            }
        }
        
        // Create component data
        return (0..<componentCount).map { componentIndex in
            MultiComponentImageData.ComponentData(
                id: scanHeader.components[componentIndex].id,
                pixels: componentPixels[componentIndex]
            )
        }
    }
    
    // MARK: - Sample-Interleaved Decoding
    
    /// Decode sample-interleaved image (all components in one scan, pixel by pixel)
    private func decodeSampleInterleaved(
        frameHeader: JPEGLSFrameHeader,
        scanHeader: JPEGLSScanHeader,
        scanData: Data,
        parameters: JPEGLSPresetParameters
    ) throws -> [MultiComponentImageData.ComponentData] {
        let reader = JPEGLSBitstreamReader(data: scanData)
        let componentCount = scanHeader.componentCount
        
        // Initialize pixel buffers for all components
        var componentPixels = (0..<componentCount).map { _ in
            return Array(repeating: Array(repeating: 0, count: frameHeader.width), count: frameHeader.height)
        }
        
        // Initialize shared decoder and context (one context shared across all components in interleaved mode)
        let decoder = try JPEGLSRegularModeDecoder(parameters: parameters, near: scanHeader.near)
        let runDecoder = try JPEGLSRunModeDecoder(parameters: parameters, near: scanHeader.near)
        var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
        
        // Decode pixel by pixel, cycling through components
        for row in 0..<frameHeader.height {
            for col in 0..<frameHeader.width {
                for componentIndex in 0..<componentCount {
                    // Get neighbors for this component
                    let (a, b, c, d) = getNeighbors(
                        pixels: componentPixels[componentIndex],
                        row: row,
                        col: col,
                        width: frameHeader.width
                    )
                    
                    // Decode pixel
                    let pixel = try decodeSinglePixel(
                        reader: reader,
                        decoder: decoder,
                        runDecoder: runDecoder,
                        context: &context,
                        a: a, b: b, c: c, d: d,
                        parameters: parameters,
                        near: scanHeader.near
                    )
                    
                    componentPixels[componentIndex][row][col] = pixel
                }
            }
        }
        
        // Create component data
        return (0..<componentCount).map { componentIndex in
            MultiComponentImageData.ComponentData(
                id: scanHeader.components[componentIndex].id,
                pixels: componentPixels[componentIndex]
            )
        }
    }
    
    // MARK: - Component Decoding
    
    /// Decode a single component (used for non-interleaved mode)
    private func decodeComponent(
        reader: JPEGLSBitstreamReader,
        width: Int,
        height: Int,
        scanHeader: JPEGLSScanHeader,
        parameters: JPEGLSPresetParameters
    ) throws -> [[Int]] {
        let decoder = try JPEGLSRegularModeDecoder(parameters: parameters, near: scanHeader.near)
        let runDecoder = try JPEGLSRunModeDecoder(parameters: parameters, near: scanHeader.near)
        var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
        
        // Initialize pixel buffer
        var pixels = Array(repeating: Array(repeating: 0, count: width), count: height)
        
        // Decode pixels in raster order
        for row in 0..<height {
            var col = 0
            while col < width {
                // Get neighbor pixels
                let (a, b, c, d) = getNeighbors(pixels: pixels, row: row, col: col, width: width)
                
                // Check for run mode: all quantized gradients are zero
                let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c, d: d)
                let q1 = decoder.quantizeGradient(d1)
                let q2 = decoder.quantizeGradient(d2)
                let q3 = decoder.quantizeGradient(d3)
                
                if q1 == 0 && q2 == 0 && q3 == 0 {
                    // Run mode: decode run of pixels with value = a (the run value)
                    let runResult = try decodeRun(
                        reader: reader,
                        runDecoder: runDecoder,
                        context: &context,
                        runValue: a,
                        remainingInLine: width - col,
                        parameters: parameters,
                        near: scanHeader.near
                    )
                    
                    // Fill in run pixels
                    for i in 0..<runResult.runLength {
                        if col + i < width {
                            pixels[row][col + i] = a
                        }
                    }
                    col += runResult.runLength
                    
                    // If there was an interruption pixel, add it
                    if let interruptionPixel = runResult.interruptionPixel {
                        if col < width {
                            pixels[row][col] = interruptionPixel
                            col += 1
                        }
                    }
                } else {
                    // Regular mode
                    let pixel = try decodeSinglePixel(
                        reader: reader,
                        decoder: decoder,
                        runDecoder: runDecoder,
                        context: &context,
                        a: a, b: b, c: c, d: d,
                        parameters: parameters,
                        near: scanHeader.near
                    )
                    pixels[row][col] = pixel
                    col += 1
                }
            }
        }
        
        return pixels
    }
    
    /// Decode a single line for a component (used for line-interleaved mode)
    private func decodeLineForComponent(
        reader: JPEGLSBitstreamReader,
        pixels: inout [[Int]],
        row: Int,
        width: Int,
        decoder: JPEGLSRegularModeDecoder,
        runDecoder: JPEGLSRunModeDecoder,
        context: inout JPEGLSContextModel,
        scanHeader: JPEGLSScanHeader,
        parameters: JPEGLSPresetParameters
    ) throws {
        var col = 0
        while col < width {
            // Get neighbor pixels
            let (a, b, c, d) = getNeighbors(pixels: pixels, row: row, col: col, width: width)
            
            // Check for run mode: all quantized gradients are zero
            let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c, d: d)
            let q1 = decoder.quantizeGradient(d1)
            let q2 = decoder.quantizeGradient(d2)
            let q3 = decoder.quantizeGradient(d3)
            
            if q1 == 0 && q2 == 0 && q3 == 0 {
                // Run mode: decode run of pixels with value = a (the run value)
                let runResult = try decodeRun(
                    reader: reader,
                    runDecoder: runDecoder,
                    context: &context,
                    runValue: a,
                    remainingInLine: width - col,
                    parameters: parameters,
                    near: scanHeader.near
                )
                
                // Fill in run pixels
                for i in 0..<runResult.runLength {
                    if col + i < width {
                        pixels[row][col + i] = a
                    }
                }
                col += runResult.runLength
                
                // If there was an interruption pixel, add it
                if let interruptionPixel = runResult.interruptionPixel {
                    if col < width {
                        pixels[row][col] = interruptionPixel
                        col += 1
                    }
                }
            } else {
                // Regular mode
                let pixel = try decodeSinglePixel(
                    reader: reader,
                    decoder: decoder,
                    runDecoder: runDecoder,
                    context: &context,
                    a: a, b: b, c: c, d: d,
                    parameters: parameters,
                    near: scanHeader.near
                )
                
                pixels[row][col] = pixel
                col += 1
            }
        }
    }
    
    // MARK: - Pixel Decoding
    
    /// Decode a single pixel in regular mode
    private func decodeSinglePixel(
        reader: JPEGLSBitstreamReader,
        decoder: JPEGLSRegularModeDecoder,
        runDecoder: JPEGLSRunModeDecoder,
        context: inout JPEGLSContextModel,
        a: Int, b: Int, c: Int, d: Int,
        parameters: JPEGLSPresetParameters,
        near: Int
    ) throws -> Int {
        // Compute gradients
        let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c, d: d)
        
        // Quantize gradients
        let q1 = decoder.quantizeGradient(d1)
        let q2 = decoder.quantizeGradient(d2)
        let q3 = decoder.quantizeGradient(d3)
        
        // Get context
        let contextIndex = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
        let k = context.computeGolombParameter(contextIndex: contextIndex)
        
        // Read Golomb-Rice encoded error
        let mappedError = try readGolombCode(reader: reader, k: k)
        
        // Decode pixel using decoder
        let result = decoder.decodePixel(
            mappedError: mappedError,
            a: a, b: b, c: c, d: d,
            context: context
        )
        
        // Update context
        context.updateContext(
            contextIndex: contextIndex,
            predictionError: result.error,
            sign: result.sign
        )
        
        return result.sample
    }
    
    /// Decode a run of identical pixels
    private func decodeRun(
        reader: JPEGLSBitstreamReader,
        runDecoder: JPEGLSRunModeDecoder,
        context: inout JPEGLSContextModel,
        runValue: Int,
        remainingInLine: Int,
        parameters: JPEGLSPresetParameters,
        near: Int
    ) throws -> (runLength: Int, interruptionPixel: Int?) {
        // Read run length
        let runLength = try readRunLength(
            reader: reader,
            runDecoder: runDecoder,
            context: &context,
            remainingInLine: remainingInLine
        )
        
        // If run ends before end of line, decode interruption pixel
        if runLength < remainingInLine {
            // Get k for interruption sample
            // Per ITU-T.87, interruption uses simple k=0 or k=1 depending on context
            let k = 0  // Simplified - use fixed k for now
            
            // Read Golomb-Rice encoded interruption error
            let mappedError = try readGolombCode(reader: reader, k: k)
            
            // Decode interruption sample
            let interruption = runDecoder.decodeRunInterruption(
                mappedError: mappedError,
                runValue: runValue
            )
            
            // Update context for run mode
            context.updateRunIndex(completedRunLength: runLength)
            
            return (runLength, interruption.sample)
        }
        
        // Full run to end of line
        context.updateRunIndex(completedRunLength: runLength)
        return (runLength, nil)
    }
    
    // MARK: - Golomb-Rice Decoding
    
    /// Read Golomb-Rice encoded value from bitstream
    ///
    /// Reads unary prefix followed by k remainder bits.
    ///
    /// - Parameters:
    ///   - reader: Bitstream reader
    ///   - k: Golomb parameter
    /// - Returns: Mapped error value
    /// - Throws: `JPEGLSError` if reading fails
    private func readGolombCode(reader: JPEGLSBitstreamReader, k: Int) throws -> Int {
        // Read unary prefix (count zeros until 1)
        var unaryCount = 0
        while try reader.readBits(1) == 0 {
            unaryCount += 1
            // Limit check to prevent infinite loop on corrupted data
            // For 16-bit images, mapped error can be up to 2*MAXVAL = 131070
            // Using a higher limit (200000) to provide safety margin
            guard unaryCount < 200000 else {
                throw JPEGLSError.decodingFailed(reason: "Excessive unary prefix in Golomb code")
            }
        }
        
        // Read k remainder bits
        let remainder = k > 0 ? Int(try reader.readBits(k)) : 0
        
        // Compute mapped error: quotient * (1 << k) + remainder
        return (unaryCount << k) | remainder
    }
    
    /// Read run length from bitstream
    ///
    /// Decodes variable-length run encoding per ITU-T.87.
    ///
    /// - Parameters:
    ///   - reader: Bitstream reader
    ///   - runDecoder: Run mode decoder
    ///   - context: Context model (for J parameter)
    ///   - remainingInLine: Pixels remaining in current line
    /// - Returns: Decoded run length
    /// - Throws: `JPEGLSError` if reading fails
    private func readRunLength(
        reader: JPEGLSBitstreamReader,
        runDecoder: JPEGLSRunModeDecoder,
        context: inout JPEGLSContextModel,
        remainingInLine: Int
    ) throws -> Int {
        let runIndex = context.currentRunIndex
        let j = runDecoder.computeJ(runIndex: runIndex)
        
        // Read continuation bits (count '1' bits until we see a '0')
        var continuationBits = 0
        while try reader.readBits(1) == 1 {
            continuationBits += 1
            // Safety check
            guard continuationBits < 1000 else {
                throw JPEGLSError.decodingFailed(reason: "Excessive continuation bits in run length")
            }
        }
        
        // Read remainder bits
        let remainder = j > 0 ? Int(try reader.readBits(j)) : 0
        
        // Decode run length
        let decoded = runDecoder.decodeRunLength(
            continuationBits: continuationBits,
            remainder: remainder,
            runIndex: runIndex
        )
        
        // Return the total run length, but cap at remaining pixels in line
        return min(decoded.totalRunLength, remainingInLine)
    }
    
    // MARK: - Helper Methods
    
    /// Get neighbor pixels for gradient computation
    ///
    /// Handles boundary conditions per ITU-T.87 Section 3.2.
    ///
    /// - Parameters:
    ///   - pixels: Current pixel buffer
    ///   - row: Current row
    ///   - col: Current column
    ///   - width: Image width (for top-right boundary check)
    /// - Returns: Tuple of (a, b, c, d) neighbor pixels
    private func getNeighbors(
        pixels: [[Int]],
        row: Int,
        col: Int,
        width: Int
    ) -> (a: Int, b: Int, c: Int, d: Int) {
        if row == 0 && col == 0 {
            return (0, 0, 0, 0)
        } else if row == 0 {
            let left = pixels[row][col - 1]
            return (left, left, left, left)
        } else if col == 0 {
            let top = pixels[row - 1][col]
            let topRight = (col + 1 < width) ? pixels[row - 1][col + 1] : top
            return (top, top, top, topRight)
        } else {
            let a = pixels[row][col - 1]      // Left
            let b = pixels[row - 1][col]      // Top
            let c = pixels[row - 1][col - 1]  // Top-left
            let d = (col + 1 < width) ? pixels[row - 1][col + 1] : b  // Top-right (or top if at edge)
            return (a, b, c, d)
        }
    }
}
