import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    /// Command to convert between image formats.
    ///
    /// Supported input formats: JPEG-LS (`.jls`), PNG (`.png`), TIFF (`.tiff`/`.tif`),
    /// PGM (`.pgm`), PPM (`.ppm`).
    ///
    /// Supported output formats: JPEG-LS (`.jls`), PNG (`.png`), TIFF (`.tiff`/`.tif`),
    /// PGM (`.pgm`), PPM (`.ppm`), raw (any other extension).
    ///
    /// When the output format is JPEG-LS, encoding parameters (--near, --interleave,
    /// --colour-transform, --t1/--t2/--t3/--reset, --optimise) are available.
    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Convert an image between supported formats",
            discussion: """
            Decodes the input file and re-encodes it in the target format determined by
            the output file extension.

            Supported input formats:
              JPEG-LS  (.jls)
              PNG      (.png) — uncompressed stored-DEFLATE only
              TIFF     (.tiff, .tif) — uncompressed baseline only
              PGM      (.pgm) — binary P5
              PPM      (.ppm) — binary P6

            Supported output formats:
              JPEG-LS  (.jls)
              PNG      (.png)
              TIFF     (.tiff, .tif)
              PGM      (.pgm)
              PPM      (.ppm)
              raw      (any other extension — packed pixel bytes, big-endian for 16-bit)

            JPEG-LS output options (--near, --interleave, --colour-transform, etc.) are
            only used when the output format is JPEG-LS.
            """
        )

        @Argument(help: "Input file path")
        var input: String

        @Argument(help: "Output file path (format is determined by extension)")
        var output: String

        // JPEG-LS encoding options (used only when the output is a .jls file).

        @Option(name: .long, help: "NEAR parameter for near-lossless JPEG-LS output (0–255, default: 0)")
        var near: Int = 0

        @Option(name: .long, help: "Interleave mode for JPEG-LS output: none, line, sample (default: none)")
        var interleave: String = "none"

        @Option(
            name: [.customLong("color-transform"), .customLong("colour-transform")],
            help: "Colour transformation for JPEG-LS output: none, hp1, hp2, hp3 (default: none). Accepts both --color-transform and --colour-transform."
        )
        var colorTransform: String = "none"

        @Option(name: .long, help: "Custom T1 threshold for JPEG-LS output (optional)")
        var t1: Int?

        @Option(name: .long, help: "Custom T2 threshold for JPEG-LS output (optional)")
        var t2: Int?

        @Option(name: .long, help: "Custom T3 threshold for JPEG-LS output (optional)")
        var t3: Int?

        @Option(name: .long, help: "Custom RESET value for JPEG-LS output (optional)")
        var reset: Int?

        @Flag(
            name: [.customLong("optimise"), .customLong("optimize")],
            help: "Embed computed preset parameters in JPEG-LS output bitstream. Accepts both --optimise and --optimize."
        )
        var optimise: Bool = false

        @Flag(name: .long, help: "Enable verbose output")
        var verbose: Bool = false

        @Flag(name: .long, help: "Suppress non-essential output (quiet mode)")
        var quiet: Bool = false

        @Flag(
            name: [.customLong("no-colour"), .customLong("no-color")],
            help: "Disable ANSI colour codes in terminal output. Accepts both --no-colour and --no-color."
        )
        var noColour: Bool = false

        mutating func run() throws {
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            guard (0...255).contains(near) else {
                throw ValidationError("NEAR parameter must be between 0 and 255")
            }

            if verbose {
                print("JPEG-LS Convert")
                print("===============")
                print("Input:  \(input)")
                print("Output: \(output)")
                print()
            }

            // Load and decode the input file.
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            let decoded   = try loadImage(path: input, data: inputData)

            if verbose {
                print("Decoded: \(decoded.width)×\(decoded.height), " +
                      "\(decoded.bitsPerSample)-bit, \(decoded.componentPixels.count) component(s)")
                print()
            }

            // Determine the output format from the file extension.
            let outExt = (output as NSString).pathExtension.lowercased()
            let outputData: Data

            switch outExt {
            case "jls":
                outputData = try encodeJPEGLS(decoded: decoded)
            case "png":
                outputData = try PNGSupport.encode(
                    componentPixels: decoded.componentPixels,
                    width: decoded.width,
                    height: decoded.height,
                    maxVal: decoded.maxVal
                )
            case "tiff", "tif":
                outputData = try TIFFSupport.encode(
                    componentPixels: decoded.componentPixels,
                    width: decoded.width,
                    height: decoded.height,
                    maxVal: decoded.maxVal
                )
            case "pgm":
                outputData = try PNMSupport.encode(
                    componentPixels: decoded.componentPixels,
                    width: decoded.width,
                    height: decoded.height,
                    maxVal: decoded.maxVal
                )
            case "ppm":
                outputData = try PNMSupport.encode(
                    componentPixels: decoded.componentPixels,
                    width: decoded.width,
                    height: decoded.height,
                    maxVal: decoded.maxVal
                )
            default:
                // Raw output: packed pixel bytes, big-endian for 16-bit samples.
                outputData = encodeRaw(decoded: decoded)
            }

            try outputData.write(to: URL(fileURLWithPath: output))

            if !quiet {
                print("✓ Converted: \(input) → \(output) (\(outputData.count) bytes)")
            }
        }

        // MARK: - Private helpers

        /// Intermediate decoded-image representation.
        private struct DecodedImage {
            let width: Int
            let height: Int
            let bitsPerSample: Int
            /// Pixel data as `[component][row][col]`.
            let componentPixels: [[[Int]]]
            var maxVal: Int { (1 << bitsPerSample) - 1 }
        }

        /// Decode an input file into a `DecodedImage`, supporting all input formats.
        private func loadImage(path: String, data: Data) throws -> DecodedImage {
            if isPNMFile(path: path, data: data) {
                let pnm = try PNMSupport.parse(data)
                return DecodedImage(
                    width: pnm.width,
                    height: pnm.height,
                    bitsPerSample: bitsNeeded(forMaxVal: pnm.maxVal),
                    componentPixels: pnm.componentPixels
                )
            } else if isPNGFile(path: path, data: data) {
                let png = try PNGSupport.decode(data)
                return DecodedImage(
                    width: png.width,
                    height: png.height,
                    bitsPerSample: png.bitDepth,
                    componentPixels: png.componentPixels
                )
            } else if isTIFFFile(path: path, data: data) {
                let tiff = try TIFFSupport.decode(data)
                return DecodedImage(
                    width: tiff.width,
                    height: tiff.height,
                    bitsPerSample: tiff.bitsPerSample,
                    componentPixels: tiff.componentPixels
                )
            } else {
                // Assume JPEG-LS.
                let decoder = JPEGLSDecoder()
                let imageData = try decoder.decode(data)
                return DecodedImage(
                    width: imageData.frameHeader.width,
                    height: imageData.frameHeader.height,
                    bitsPerSample: imageData.frameHeader.bitsPerSample,
                    componentPixels: imageData.components.map { $0.pixels }
                )
            }
        }

        /// Encode a `DecodedImage` to JPEG-LS using the command's encoding options.
        private func encodeJPEGLS(decoded: DecodedImage) throws -> Data {
            let interleaveMode = try parseInterleaveMode(interleave)
            let colorTransformValue = try parseColorTransform(colorTransform)

            // Determine interleave mode (greyscale always uses .none).
            let actualInterleaveMode: JPEGLSInterleaveMode =
                decoded.componentPixels.count == 1 ? .none : interleaveMode

            // Resolve preset parameters.
            let resolvedPreset: JPEGLSPresetParameters?
            if let t1, let t2, let t3, let reset {
                resolvedPreset = try JPEGLSPresetParameters(
                    maxValue: decoded.maxVal,
                    threshold1: t1,
                    threshold2: t2,
                    threshold3: t3,
                    reset: reset
                )
            } else if optimise {
                resolvedPreset = try JPEGLSPresetParameters.defaultParameters(
                    bitsPerSample: decoded.bitsPerSample, near: near
                )
            } else {
                resolvedPreset = nil
            }

            let config = try JPEGLSEncoder.Configuration(
                near: near,
                interleaveMode: actualInterleaveMode,
                presetParameters: resolvedPreset,
                colorTransformation: colorTransformValue
            )

            let imageData: MultiComponentImageData
            switch decoded.componentPixels.count {
            case 1:
                imageData = try MultiComponentImageData.grayscale(
                    pixels: decoded.componentPixels[0],
                    bitsPerSample: decoded.bitsPerSample
                )
            case 3:
                imageData = try MultiComponentImageData.rgb(
                    redPixels:   decoded.componentPixels[0],
                    greenPixels: decoded.componentPixels[1],
                    bluePixels:  decoded.componentPixels[2],
                    bitsPerSample: decoded.bitsPerSample
                )
            default:
                throw ValidationError("Unsupported component count for JPEG-LS output: \(decoded.componentPixels.count)")
            }

            let encoder = JPEGLSEncoder()
            return try encoder.encode(imageData, configuration: config)
        }

        /// Pack pixel data into raw bytes (big-endian for multi-byte samples).
        ///
        /// Samples with `bitsPerSample` ≤ 8 are written as single bytes; samples with
        /// `bitsPerSample` 9–16 (e.g. 12-bit or 16-bit JPEG-LS) are written as 2-byte
        /// big-endian values, matching the raw input format expected by the `encode` command.
        private func encodeRaw(decoded: DecodedImage) -> Data {
            let numComponents = decoded.componentPixels.count
            let bytesPerSample = (decoded.bitsPerSample + 7) / 8  // 1 for ≤8-bit, 2 for 9-16-bit
            var output = Data(capacity: decoded.width * decoded.height * numComponents * bytesPerSample)
            for row in 0..<decoded.height {
                for col in 0..<decoded.width {
                    for comp in 0..<numComponents {
                        let val = decoded.componentPixels[comp][row][col]
                        if bytesPerSample == 2 {
                            output.append(UInt8((val >> 8) & 0xFF))
                            output.append(UInt8(val & 0xFF))
                        } else {
                            output.append(UInt8(val & 0xFF))
                        }
                    }
                }
            }
            return output
        }

        // MARK: - Format detection

        private func isPNMFile(path: String, data: Data) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "pgm" || ext == "ppm" { return true }
            if data.count >= 2 {
                let magic = data.prefix(2)
                return magic[0] == UInt8(ascii: "P")
                    && (magic[1] == UInt8(ascii: "5") || magic[1] == UInt8(ascii: "6"))
            }
            return false
        }

        private func isPNGFile(path: String, data: Data) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "png" { return true }
            return PNGSupport.isPNG(data)
        }

        private func isTIFFFile(path: String, data: Data) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "tiff" || ext == "tif" { return true }
            return TIFFSupport.isTIFF(data)
        }

        // MARK: - Parameter parsing

        private func parseInterleaveMode(_ mode: String) throws -> JPEGLSInterleaveMode {
            switch mode.lowercased() {
            case "none":   return .none
            case "line":   return .line
            case "sample": return .sample
            default:
                throw ValidationError("Invalid interleave mode '\(mode)'. Valid values: none, line, sample. See 'jpegls convert --help' for examples.")
            }
        }

        private func parseColorTransform(_ transform: String) throws -> JPEGLSColorTransformation {
            switch transform.lowercased() {
            case "none": return .none
            case "hp1":  return .hp1
            case "hp2":  return .hp2
            case "hp3":  return .hp3
            default:
                throw ValidationError("Invalid colour transformation '\(transform)'. Valid values: none, hp1, hp2, hp3. See 'jpegls convert --help' for examples.")
            }
        }

        private func bitsNeeded(forMaxVal maxVal: Int) -> Int {
            var bits = 1
            while (1 << bits) - 1 < maxVal { bits += 1 }
            return bits
        }
    }
}
