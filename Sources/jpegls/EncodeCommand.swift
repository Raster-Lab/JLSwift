import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    struct Encode: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Encode image to JPEG-LS format"
        )
        
        @Argument(help: "Input image file path (raw pixel data)")
        var input: String
        
        @Argument(help: "Output JPEG-LS file path")
        var output: String
        
        @Option(name: .shortAndLong, help: "Image width in pixels")
        var width: Int
        
        @Option(name: .shortAndLong, help: "Image height in pixels")
        var height: Int
        
        @Option(name: .shortAndLong, help: "Bits per sample (2-16, default: 8)")
        var bitsPerSample: Int = 8
        
        @Option(name: .shortAndLong, help: "Number of components (1=grayscale, 3=RGB, default: 1)")
        var components: Int = 1
        
        @Option(name: .long, help: "NEAR parameter for near-lossless encoding (0=lossless, 1-255=lossy, default: 0)")
        var near: Int = 0
        
        @Option(name: .long, help: "Interleave mode: none, line, sample (default: none)")
        var interleave: String = "none"
        
        @Option(name: .long, help: "Color transformation: none, hp1, hp2, hp3 (default: none)")
        var colorTransform: String = "none"
        
        @Option(name: .long, help: "Custom T1 threshold (optional)")
        var t1: Int?
        
        @Option(name: .long, help: "Custom T2 threshold (optional)")
        var t2: Int?
        
        @Option(name: .long, help: "Custom T3 threshold (optional)")
        var t3: Int?
        
        @Option(name: .long, help: "Custom RESET value (optional)")
        var reset: Int?
        
        @Flag(name: .long, help: "Enable verbose output")
        var verbose: Bool = false
        
        @Flag(name: .long, help: "Suppress non-essential output (quiet mode)")
        var quiet: Bool = false
        
        mutating func run() throws {
            // Validate flags: verbose and quiet are mutually exclusive
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            
            // Validate inputs
            guard (2...16).contains(bitsPerSample) else {
                throw ValidationError("Bits per sample must be between 2 and 16")
            }
            
            guard [1, 3].contains(components) else {
                throw ValidationError("Components must be 1 (grayscale) or 3 (RGB)")
            }
            
            guard (0...255).contains(near) else {
                throw ValidationError("NEAR parameter must be between 0 and 255")
            }
            
            // Parse interleave mode
            let interleaveMode = try parseInterleaveMode(interleave)
            
            // Parse color transformation
            let parsedColorTransform = try parseColorTransform(colorTransform)
            
            if verbose {
                print("JPEG-LS Encoder")
                print("===============")
                print("Input: \(input)")
                print("Output: \(output)")
                print("Dimensions: \(width)x\(height)")
                print("Bits per sample: \(bitsPerSample)")
                print("Components: \(components)")
                print("NEAR: \(near) (\(near == 0 ? "lossless" : "near-lossless"))")
                print("Interleave mode: \(interleave)")
                print("Color transformation: \(colorTransform)")
                if let t1 = t1, let t2 = t2, let t3 = t3, let reset = reset {
                    print("Custom preset: T1=\(t1), T2=\(t2), T3=\(t3), RESET=\(reset)")
                }
                print()
            }
            
            // Read input file
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            
            // Validate input data size
            let expectedSize = width * height * components * ((bitsPerSample + 7) / 8)
            guard inputData.count >= expectedSize else {
                throw ValidationError("Input file size (\(inputData.count) bytes) is smaller than expected (\(expectedSize) bytes)")
            }
            
            // Convert input data to pixel arrays
            let imageData: MultiComponentImageData
            if components == 1 {
                // Grayscale - organize pixels as 2D array [row][column]
                let pixels = try extractPixels(from: inputData, width: width, height: height, bitsPerSample: bitsPerSample)
                imageData = try MultiComponentImageData.grayscale(
                    pixels: pixels,
                    bitsPerSample: bitsPerSample
                )
            } else {
                // RGB - organize pixels as 2D arrays for each component
                let bytesPerPixel = (bitsPerSample + 7) / 8
                var redPixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                var greenPixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                var bluePixels: [[Int]] = Array(repeating: Array(repeating: 0, count: width), count: height)
                
                for row in 0..<height {
                    for col in 0..<width {
                        let pixelIndex = row * width + col
                        let offset = pixelIndex * 3 * bytesPerPixel
                        redPixels[row][col] = try extractPixelValue(from: inputData, at: offset, bitsPerSample: bitsPerSample)
                        greenPixels[row][col] = try extractPixelValue(from: inputData, at: offset + bytesPerPixel, bitsPerSample: bitsPerSample)
                        bluePixels[row][col] = try extractPixelValue(from: inputData, at: offset + 2 * bytesPerPixel, bitsPerSample: bitsPerSample)
                    }
                }
                
                imageData = try MultiComponentImageData.rgb(
                    redPixels: redPixels,
                    greenPixels: greenPixels,
                    bluePixels: bluePixels,
                    bitsPerSample: bitsPerSample
                )
            }
            
            // Determine interleave mode
            let actualInterleaveMode: JPEGLSInterleaveMode
            if components == 1 {
                // Grayscale always uses .none
                actualInterleaveMode = .none
            } else {
                // RGB uses specified mode
                actualInterleaveMode = interleaveMode
            }
            
            // Create encoder
            let encoder = JPEGLSEncoder()
            
            // Create configuration
            let config = try JPEGLSEncoder.Configuration(
                near: near,
                interleaveMode: actualInterleaveMode,
                presetParameters: nil,  // Custom presets not yet supported
                colorTransformation: parsedColorTransform
            )
            
            // Log warning if custom parameters were requested but not applied
            if t1 != nil || t2 != nil || t3 != nil || reset != nil {
                if verbose {
                    print("Warning: Custom preset parameters are not yet supported by the encoder")
                    print()
                }
            }
            
            // Encode
            if verbose {
                print("Encoding...")
            }
            
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
        
        private func parseInterleaveMode(_ mode: String) throws -> JPEGLSInterleaveMode {
            switch mode.lowercased() {
            case "none":
                return .none
            case "line":
                return .line
            case "sample":
                return .sample
            default:
                throw ValidationError("Invalid interleave mode: \(mode). Must be none, line, or sample")
            }
        }
        
        private func parseColorTransform(_ transform: String) throws -> JPEGLSColorTransformation {
            switch transform.lowercased() {
            case "none":
                return .none
            case "hp1":
                return .hp1
            case "hp2":
                return .hp2
            case "hp3":
                return .hp3
            default:
                throw ValidationError("Invalid color transformation: \(transform). Must be none, hp1, hp2, or hp3")
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
