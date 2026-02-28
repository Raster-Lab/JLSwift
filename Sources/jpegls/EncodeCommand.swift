import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    struct Encode: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Encode image to JPEG-LS format"
        )
        
        @Argument(help: "Input image file path (raw pixel data, PGM, or PPM)")
        var input: String
        
        @Argument(help: "Output JPEG-LS file path")
        var output: String
        
        @Option(name: .shortAndLong, help: "Image width in pixels (required for raw input; auto-detected from PGM/PPM)")
        var width: Int?
        
        @Option(name: .shortAndLong, help: "Image height in pixels (required for raw input; auto-detected from PGM/PPM)")
        var height: Int?
        
        @Option(name: .shortAndLong, help: "Bits per sample (2-16, default: 8; auto-detected from PGM/PPM MAXVAL)")
        var bitsPerSample: Int?
        
        @Option(name: .shortAndLong, help: "Number of components (1=grayscale, 3=RGB, default: 1; auto-detected from PGM/PPM)")
        var components: Int?
        
        @Option(name: .long, help: "NEAR parameter for near-lossless encoding (0=lossless, 1-255=lossy, default: 0)")
        var near: Int = 0
        
        @Option(name: .long, help: "Interleave mode: none, line, sample (default: none)")
        var interleave: String = "none"
        
        @Option(
            name: [.customLong("color-transform"), .customLong("colour-transform")],
            help: "Colour transformation: none, hp1, hp2, hp3 (default: none). Accepts both --color-transform and --colour-transform."
        )
        var colorTransform: String = "none"
        
        @Option(name: .long, help: "Custom T1 threshold (optional)")
        var t1: Int?
        
        @Option(name: .long, help: "Custom T2 threshold (optional)")
        var t2: Int?
        
        @Option(name: .long, help: "Custom T3 threshold (optional)")
        var t3: Int?
        
        @Option(name: .long, help: "Custom RESET value (optional)")
        var reset: Int?
        
        @Flag(
            name: [.customLong("optimise"), .customLong("optimize")],
            help: "Explicitly write computed preset parameters to the bitstream (makes the file self-contained). Accepts both --optimise and --optimize."
        )
        var optimise: Bool = false

        @Flag(
            name: [.customLong("no-colour"), .customLong("no-color")],
            help: "Disable ANSI colour codes in terminal output. Accepts both --no-colour and --no-color."
        )
        var noColour: Bool = false

        @Flag(name: .long, help: "Enable verbose output")
        var verbose: Bool = false
        
        @Flag(name: .long, help: "Suppress non-essential output (quiet mode)")
        var quiet: Bool = false
        
        mutating func run() throws {
            // Validate flags: verbose and quiet are mutually exclusive
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            
            guard (0...255).contains(near) else {
                throw ValidationError("NEAR parameter must be between 0 and 255")
            }
            
            // Parse interleave mode
            let interleaveMode = try parseInterleaveMode(interleave)
            
            // Parse colour transformation
            let colorTransformValue = try parseColorTransform(colorTransform)
            
            // Read input file
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            
            // Resolve image parameters — either from PGM/PPM header or from CLI options.
            let imageData: MultiComponentImageData
            let resolvedWidth: Int
            let resolvedHeight: Int
            let resolvedBitsPerSample: Int
            let resolvedComponents: Int
            
            if isPNMFile(path: input, data: inputData) {
                // PGM/PPM input: parse header and extract pixel data automatically.
                let pnm = try PNMSupport.parse(inputData)
                
                resolvedWidth      = pnm.width
                resolvedHeight     = pnm.height
                resolvedComponents = pnm.components
                // Derive bits-per-sample from MAXVAL unless the caller overrides it.
                resolvedBitsPerSample = bitsPerSample ?? bitsNeeded(forMaxVal: pnm.maxVal)
                
                guard (2...16).contains(resolvedBitsPerSample) else {
                    throw ValidationError("Bits per sample must be between 2 and 16")
                }
                
                imageData = try buildMultiComponentImageData(
                    componentPixels: pnm.componentPixels,
                    bitsPerSample: resolvedBitsPerSample
                )
            } else {
                // Raw input: require --width and --height; use defaults for the rest.
                guard let w = width else {
                    throw ValidationError("--width is required for raw input (omit for PGM/PPM files)")
                }
                guard let h = height else {
                    throw ValidationError("--height is required for raw input (omit for PGM/PPM files)")
                }
                
                resolvedWidth      = w
                resolvedHeight     = h
                resolvedBitsPerSample = bitsPerSample ?? 8
                resolvedComponents = components ?? 1
                
                guard (2...16).contains(resolvedBitsPerSample) else {
                    throw ValidationError("Bits per sample must be between 2 and 16")
                }
                guard [1, 3].contains(resolvedComponents) else {
                    throw ValidationError("Components must be 1 (grayscale) or 3 (RGB)")
                }
                
                let expectedSize = resolvedWidth * resolvedHeight * resolvedComponents * ((resolvedBitsPerSample + 7) / 8)
                guard inputData.count >= expectedSize else {
                    throw ValidationError("Input file size (\(inputData.count) bytes) is smaller than expected (\(expectedSize) bytes)")
                }
                
                imageData = try buildRawImageData(
                    from: inputData,
                    width: resolvedWidth,
                    height: resolvedHeight,
                    bitsPerSample: resolvedBitsPerSample,
                    components: resolvedComponents
                )
            }
            
            if verbose {
                print("JPEG-LS Encoder")
                print("===============")
                print("Input: \(input)")
                print("Output: \(output)")
                print("Dimensions: \(resolvedWidth)x\(resolvedHeight)")
                print("Bits per sample: \(resolvedBitsPerSample)")
                print("Components: \(resolvedComponents)")
                print("NEAR: \(near) (\(near == 0 ? "lossless" : "near-lossless"))")
                print("Interleave mode: \(interleave)")
                print("Colour transformation: \(colorTransform)")
                if let t1 = t1, let t2 = t2, let t3 = t3, let reset = reset {
                    print("Custom preset: T1=\(t1), T2=\(t2), T3=\(t3), RESET=\(reset)")
                }
                print()
            }
            
            // Determine interleave mode (grayscale always uses .none)
            let actualInterleaveMode: JPEGLSInterleaveMode = resolvedComponents == 1 ? .none : interleaveMode
            
            // Resolve preset parameters:
            // 1. If all four custom values (--t1/--t2/--t3/--reset) are provided, use them.
            // 2. Else if --optimise is set, compute and embed the default parameters explicitly.
            // 3. Otherwise pass nil (encoder computes defaults internally, no LSE marker written for near=0).
            let resolvedPresetParameters: JPEGLSPresetParameters?
            if let t1 = t1, let t2 = t2, let t3 = t3, let reset = reset {
                let maxValue = (1 << resolvedBitsPerSample) - 1
                resolvedPresetParameters = try JPEGLSPresetParameters(
                    maxValue: maxValue,
                    threshold1: t1,
                    threshold2: t2,
                    threshold3: t3,
                    reset: reset
                )
                if verbose {
                    print("Custom preset: T1=\(t1), T2=\(t2), T3=\(t3), RESET=\(reset)")
                    print()
                }
            } else if optimise {
                resolvedPresetParameters = try JPEGLSPresetParameters.defaultParameters(
                    bitsPerSample: resolvedBitsPerSample, near: near
                )
                if verbose {
                    print("Optimise: embedding default preset parameters in bitstream")
                    print()
                }
            } else {
                resolvedPresetParameters = nil
            }
            
            // Create encoder configuration
            let config = try JPEGLSEncoder.Configuration(
                near: near,
                interleaveMode: actualInterleaveMode,
                presetParameters: resolvedPresetParameters,
                colorTransformation: colorTransformValue
            )
            
            if verbose {
                print("Encoding...")
            }
            
            let encoder = JPEGLSEncoder()
            let jpegLSData = try encoder.encode(imageData, configuration: config)
            
            // Write output file
            try jpegLSData.write(to: URL(fileURLWithPath: output))
            
            if verbose {
                print("Encoded successfully")
                print("Output file size: \(jpegLSData.count) bytes")
                print("Uncompressed size: \(inputData.count) bytes")
                let ratio = Double(inputData.count) / Double(jpegLSData.count)
                print("Compression ratio: \(String(format: "%.2f", ratio)):1")
                print()
            }
            
            if !quiet {
                print("✓ Encoding complete: \(output)")
            }
        }
        
        // MARK: - Private Helpers
        
        /// Returns `true` if the file at `path` is a PGM (P5) or PPM (P6) binary image.
        private func isPNMFile(path: String, data: Data) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "pgm" || ext == "ppm" { return true }
            // Also inspect the magic bytes for headerless detection.
            if data.count >= 2 {
                let magic = data.prefix(2)
                return (magic[0] == UInt8(ascii: "P") && (magic[1] == UInt8(ascii: "5") || magic[1] == UInt8(ascii: "6")))
            }
            return false
        }
        
        /// Returns the minimum number of bits needed to represent values up to `maxVal`.
        private func bitsNeeded(forMaxVal maxVal: Int) -> Int {
            var bits = 1
            while (1 << bits) - 1 < maxVal { bits += 1 }
            return bits
        }
        
        /// Build `MultiComponentImageData` from pre-parsed `[component][row][col]` pixel arrays.
        private func buildMultiComponentImageData(
            componentPixels: [[[Int]]],
            bitsPerSample: Int
        ) throws -> MultiComponentImageData {
            switch componentPixels.count {
            case 1:
                return try MultiComponentImageData.grayscale(
                    pixels: componentPixels[0],
                    bitsPerSample: bitsPerSample
                )
            case 3:
                return try MultiComponentImageData.rgb(
                    redPixels:   componentPixels[0],
                    greenPixels: componentPixels[1],
                    bluePixels:  componentPixels[2],
                    bitsPerSample: bitsPerSample
                )
            default:
                throw ValidationError("PGM/PPM input must have 1 or 3 components; got \(componentPixels.count)")
            }
        }
        
        /// Build `MultiComponentImageData` from packed raw pixel bytes.
        private func buildRawImageData(
            from data: Data,
            width: Int,
            height: Int,
            bitsPerSample: Int,
            components: Int
        ) throws -> MultiComponentImageData {
            if components == 1 {
                let pixels = try extractPixels(from: data, width: width, height: height, bitsPerSample: bitsPerSample)
                return try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bitsPerSample)
            } else {
                let bytesPerPixel = (bitsPerSample + 7) / 8
                var redPixels:   [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                var greenPixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                var bluePixels:  [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                
                for row in 0..<height {
                    for col in 0..<width {
                        let pixelIndex = row * width + col
                        let offset = pixelIndex * 3 * bytesPerPixel
                        redPixels[row][col]   = try extractPixelValue(from: data, at: offset,                    bitsPerSample: bitsPerSample)
                        greenPixels[row][col] = try extractPixelValue(from: data, at: offset + bytesPerPixel,    bitsPerSample: bitsPerSample)
                        bluePixels[row][col]  = try extractPixelValue(from: data, at: offset + 2 * bytesPerPixel, bitsPerSample: bitsPerSample)
                    }
                }
                return try MultiComponentImageData.rgb(
                    redPixels:   redPixels,
                    greenPixels: greenPixels,
                    bluePixels:  bluePixels,
                    bitsPerSample: bitsPerSample
                )
            }
        }
        
        private func parseInterleaveMode(_ mode: String) throws -> JPEGLSInterleaveMode {
            switch mode.lowercased() {
            case "none":   return .none
            case "line":   return .line
            case "sample": return .sample
            default:
                throw ValidationError("Invalid interleave mode: \(mode). Must be none, line, or sample")
            }
        }
        
        private func parseColorTransform(_ transform: String) throws -> JPEGLSColorTransformation {
            switch transform.lowercased() {
            case "none": return .none
            case "hp1":  return .hp1
            case "hp2":  return .hp2
            case "hp3":  return .hp3
            default:
                throw ValidationError("Invalid colour transformation: \(transform). Must be none, hp1, hp2, or hp3")
            }
        }
        
        private func extractPixels(from data: Data, width: Int, height: Int, bitsPerSample: Int) throws -> [[Int]] {
            var pixels: [[Int]] = []
            let bytesPerPixel = (bitsPerSample + 7) / 8
            
            for row in 0..<height {
                var rowPixels: [Int] = []
                for col in 0..<width {
                    let offset = (row * width + col) * bytesPerPixel
                    rowPixels.append(try extractPixelValue(from: data, at: offset, bitsPerSample: bitsPerSample))
                }
                pixels.append(rowPixels)
            }
            
            return pixels
        }
        
        private func extractPixelValue(from data: Data, at offset: Int, bitsPerSample: Int) throws -> Int {
            let bytesPerPixel = (bitsPerSample + 7) / 8
            
            guard offset + bytesPerPixel <= data.count else {
                throw ValidationError("Insufficient data at offset \(offset)")
            }
            
            if bytesPerPixel == 1 {
                return Int(data[offset])
            } else {
                // Big-endian for multi-byte pixels
                var value = 0
                for i in 0..<bytesPerPixel {
                    value = (value << 8) | Int(data[offset + i])
                }
                return value
            }
        }
    }
}
