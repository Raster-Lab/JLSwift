import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    /// Command to measure JPEG-LS encoding and decoding performance.
    ///
    /// Runs a configurable number of encode/decode iterations on a synthetic or
    /// user-supplied image and reports timing statistics (min, max, mean, median)
    /// together with throughput figures.
    struct Benchmark: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Measure JPEG-LS encoding and decoding performance",
            discussion: """
            Encodes and/or decodes an image repeatedly and reports timing statistics.

            When no input file is provided a synthetic gradient image is generated
            using --size, --bits-per-sample, and --components.

            Modes:
              encode       — encode only (input image → JPEG-LS bitstream in memory)
              decode       — decode only (requires a JPEG-LS input file)
              roundtrip    — encode then decode (default)

            Examples:
              jpegls benchmark
              jpegls benchmark --size 1024 --iterations 20
              jpegls benchmark input.jls --mode decode --iterations 50
              jpegls benchmark input.png --mode roundtrip --near 3 --json
            """
        )

        // MARK: - Arguments & Options

        @Argument(help: "Optional input file (JPEG-LS, PNG, TIFF, PGM, or PPM); omit to use a synthetic image")
        var input: String?

        @Option(name: .long, help: "Benchmark mode: encode, decode, roundtrip (default: roundtrip)")
        var mode: String = "roundtrip"

        @Option(name: .long, help: "Width and height of the synthetic test image in pixels (default: 512)")
        var size: Int = 512

        @Option(name: .shortAndLong, help: "Bits per sample for the synthetic image (2–16, default: 8)")
        var bitsPerSample: Int = 8

        @Option(name: .shortAndLong, help: "Number of components for the synthetic image: 1 or 3 (default: 1)")
        var components: Int = 1

        @Option(name: .long, help: "NEAR parameter for near-lossless encoding (0=lossless, 1–255, default: 0)")
        var near: Int = 0

        @Option(name: .long, help: "Interleave mode for encoding: none, line, sample (default: none)")
        var interleave: String = "none"

        @Option(name: .long, help: "Number of measurement iterations (default: 10)")
        var iterations: Int = 10

        @Option(name: .long, help: "Number of warm-up iterations before measurement begins (default: 3)")
        var warmup: Int = 3

        @Flag(name: .long, help: "Output results in JSON format")
        var json: Bool = false

        @Flag(name: .long, help: "Enable verbose output")
        var verbose: Bool = false

        @Flag(name: .long, help: "Suppress non-essential output (quiet mode)")
        var quiet: Bool = false

        @Flag(
            name: [.customLong("no-colour"), .customLong("no-color")],
            help: "Disable ANSI colour codes in terminal output. Accepts both --no-colour and --no-color."
        )
        var noColour: Bool = false

        // MARK: - Run

        mutating func run() throws {
            // Validate flag combinations
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            if json && quiet {
                throw ValidationError("Cannot use both --json and --quiet flags")
            }

            // Validate numeric parameters
            guard (0...255).contains(near) else {
                throw ValidationError("NEAR parameter must be between 0 and 255")
            }
            guard (2...16).contains(bitsPerSample) else {
                throw ValidationError("Bits per sample must be between 2 and 16")
            }
            guard [1, 3].contains(components) else {
                throw ValidationError("Components must be 1 (greyscale) or 3 (RGB)")
            }
            guard size >= 1 else {
                throw ValidationError("--size must be at least 1")
            }
            guard iterations >= 1 else {
                throw ValidationError("--iterations must be at least 1")
            }
            guard warmup >= 0 else {
                throw ValidationError("--warmup must be 0 or greater")
            }

            // Parse mode
            let benchmarkMode = try parseBenchmarkMode(mode)

            // Parse interleave mode
            let interleaveMode = try parseInterleaveMode(interleave)

            // --- Resolve image data ---
            // For encode or roundtrip mode we need pixel data.
            // For decode mode we need a JPEG-LS bitstream.
            let imageData: MultiComponentImageData?
            let jlsData: Data?
            let imageWidth: Int
            let imageHeight: Int
            let imageComponents: Int
            let imageBitsPerSample: Int

            if let inputPath = input {
                let rawData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
                let ext = (inputPath as NSString).pathExtension.lowercased()

                if ext == "jls" {
                    // JPEG-LS file: parse header to obtain image dimensions; use for decode benchmark.
                    let parser = JPEGLSParser(data: rawData)
                    let parseResult = try parser.parse()
                    imageWidth         = parseResult.frameHeader.width
                    imageHeight        = parseResult.frameHeader.height
                    imageComponents    = parseResult.frameHeader.componentCount
                    imageBitsPerSample = parseResult.frameHeader.bitsPerSample
                    jlsData            = rawData

                    if benchmarkMode == .encode || benchmarkMode == .roundtrip {
                        // Decode once to obtain pixel data for the encode phase.
                        let decoder = JPEGLSDecoder()
                        imageData = try decoder.decode(rawData)
                    } else {
                        imageData = nil
                    }
                } else {
                    // Non-JPEG-LS input: build MultiComponentImageData from file.
                    let decoded = try loadImageData(path: inputPath, data: rawData)
                    imageWidth         = decoded.frameHeader.width
                    imageHeight        = decoded.frameHeader.height
                    imageComponents    = decoded.frameHeader.componentCount
                    imageBitsPerSample = decoded.frameHeader.bitsPerSample
                    imageData          = decoded

                    if benchmarkMode == .decode || benchmarkMode == .roundtrip {
                        // Pre-encode once so we have a bitstream for the decode phase.
                        let encoder = JPEGLSEncoder()
                        let config = try JPEGLSEncoder.Configuration(
                            near: near,
                            interleaveMode: imageComponents == 1 ? .none : interleaveMode
                        )
                        jlsData = try encoder.encode(decoded, configuration: config)
                    } else {
                        jlsData = nil
                    }
                }
            } else {
                // Synthetic gradient image.
                imageWidth         = size
                imageHeight        = size
                imageComponents    = components
                imageBitsPerSample = bitsPerSample
                let synthetic = try generateSyntheticImage(
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerSample: imageBitsPerSample,
                    components: imageComponents
                )
                imageData = synthetic

                if benchmarkMode == .decode || benchmarkMode == .roundtrip {
                    let encoder = JPEGLSEncoder()
                    let config = try JPEGLSEncoder.Configuration(
                        near: near,
                        interleaveMode: imageComponents == 1 ? .none : interleaveMode
                    )
                    jlsData = try encoder.encode(synthetic, configuration: config)
                } else {
                    jlsData = nil
                }
            }

            if verbose {
                print("JPEG-LS Benchmark")
                print("=================")
                print("Image: \(imageWidth)×\(imageHeight), \(imageBitsPerSample)-bit, \(imageComponents) component(s)")
                print("Mode: \(mode)")
                print("NEAR: \(near)")
                print("Interleave: \(interleave)")
                print("Iterations: \(iterations) (+ \(warmup) warm-up)")
                print()
            }

            // --- Build encoder configuration (used in encode/roundtrip phases) ---
            let encoderConfig = try JPEGLSEncoder.Configuration(
                near: near,
                interleaveMode: imageComponents == 1 ? .none : interleaveMode
            )

            // --- Run benchmarks ---
            var encodeTimings: [Double] = []
            var decodeTimings: [Double] = []
            var encodedSizes:  [Int]    = []

            let measureIterations = warmup + iterations

            for i in 0..<measureIterations {
                let isMeasured = i >= warmup

                if benchmarkMode == .encode || benchmarkMode == .roundtrip {
                    guard let imgData = imageData else {
                        throw ValidationError("Image data is required for encode mode")
                    }
                    let encoder = JPEGLSEncoder()
                    let t0 = Date()
                    let encoded = try encoder.encode(imgData, configuration: encoderConfig)
                    let elapsed = Date().timeIntervalSince(t0)
                    if isMeasured {
                        encodeTimings.append(elapsed)
                        encodedSizes.append(encoded.count)
                    }
                    // For roundtrip, use the freshly encoded data for the decode phase.
                    if benchmarkMode == .roundtrip {
                        let decoder = JPEGLSDecoder()
                        let t1 = Date()
                        _ = try decoder.decode(encoded)
                        let elapsed2 = Date().timeIntervalSince(t1)
                        if isMeasured {
                            decodeTimings.append(elapsed2)
                        }
                    }
                } else {
                    // decode-only
                    guard let jls = jlsData else {
                        throw ValidationError("JPEG-LS data is required for decode mode")
                    }
                    let decoder = JPEGLSDecoder()
                    let t0 = Date()
                    _ = try decoder.decode(jls)
                    let elapsed = Date().timeIntervalSince(t0)
                    if isMeasured {
                        decodeTimings.append(elapsed)
                    }
                }
            }

            // --- Compute statistics ---
            let pixelCount       = imageWidth * imageHeight * imageComponents
            let uncompressedBytes = imageWidth * imageHeight * imageComponents * ((imageBitsPerSample + 7) / 8)
            let avgEncodedSize   = encodedSizes.isEmpty
                ? (jlsData?.count ?? 0)
                : encodedSizes.reduce(0, +) / encodedSizes.count

            let encodeStats = computeStats(timings: encodeTimings)
            let decodeStats = computeStats(timings: decodeTimings)

            if json {
                printJSON(
                    imageWidth: imageWidth, imageHeight: imageHeight,
                    imageBitsPerSample: imageBitsPerSample, imageComponents: imageComponents,
                    uncompressedBytes: uncompressedBytes, avgEncodedSize: avgEncodedSize,
                    pixelCount: pixelCount, iterations: iterations, warmup: warmup,
                    mode: mode, near: near, interleave: interleave,
                    encodeStats: encodeStats, decodeStats: decodeStats
                )
            } else if !quiet {
                printHumanReadable(
                    imageWidth: imageWidth, imageHeight: imageHeight,
                    imageBitsPerSample: imageBitsPerSample, imageComponents: imageComponents,
                    uncompressedBytes: uncompressedBytes, avgEncodedSize: avgEncodedSize,
                    pixelCount: pixelCount, iterations: iterations, warmup: warmup,
                    mode: mode, near: near, interleave: interleave,
                    encodeStats: encodeStats, decodeStats: decodeStats
                )
            }
        }

        // MARK: - Statistics

        private struct TimingStats {
            let min: Double
            let max: Double
            let mean: Double
            let median: Double

            static let empty = TimingStats(min: 0, max: 0, mean: 0, median: 0)
        }

        private func computeStats(timings: [Double]) -> TimingStats {
            guard !timings.isEmpty else { return .empty }
            let sorted = timings.sorted()
            let mean = timings.reduce(0, +) / Double(timings.count)
            let n = sorted.count
            let median: Double
            if n % 2 == 0 {
                median = (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            } else {
                median = sorted[n / 2]
            }
            return TimingStats(min: sorted.first!, max: sorted.last!, mean: mean, median: median)
        }

        // MARK: - Output

        private func printHumanReadable(
            imageWidth: Int, imageHeight: Int,
            imageBitsPerSample: Int, imageComponents: Int,
            uncompressedBytes: Int, avgEncodedSize: Int,
            pixelCount: Int, iterations: Int, warmup: Int,
            mode: String, near: Int, interleave: String,
            encodeStats: TimingStats, decodeStats: TimingStats
        ) {
            print("JPEG-LS Benchmark Results")
            print("=========================")
            print("Image:        \(imageWidth)×\(imageHeight), \(imageBitsPerSample)-bit, \(imageComponents) component(s)")
            print("Mode:         \(mode)")
            print("NEAR:         \(near) (\(near == 0 ? "lossless" : "near-lossless"))")
            print("Interleave:   \(interleave)")
            print("Iterations:   \(iterations) (warm-up: \(warmup))")
            if avgEncodedSize > 0 {
                let ratio = Double(uncompressedBytes) / Double(avgEncodedSize)
                print("Compression:  \(uncompressedBytes) → \(avgEncodedSize) bytes (\(String(format: "%.2f", ratio)):1)")
            }
            print()

            if encodeStats.mean > 0 {
                let encMpps = Double(pixelCount) / encodeStats.mean / 1_000_000
                let encMBps = Double(uncompressedBytes) / encodeStats.mean / (1024 * 1024)
                print("Encode:")
                print("  Min:      \(formatTime(encodeStats.min))")
                print("  Max:      \(formatTime(encodeStats.max))")
                print("  Mean:     \(formatTime(encodeStats.mean))")
                print("  Median:   \(formatTime(encodeStats.median))")
                print("  Throughput (mean): \(String(format: "%.1f", encMpps)) Mpixels/s  (\(String(format: "%.1f", encMBps)) MB/s)")
            }

            if decodeStats.mean > 0 {
                let decMpps = Double(pixelCount) / decodeStats.mean / 1_000_000
                let decMBps = Double(uncompressedBytes) / decodeStats.mean / (1024 * 1024)
                print("Decode:")
                print("  Min:      \(formatTime(decodeStats.min))")
                print("  Max:      \(formatTime(decodeStats.max))")
                print("  Mean:     \(formatTime(decodeStats.mean))")
                print("  Median:   \(formatTime(decodeStats.median))")
                print("  Throughput (mean): \(String(format: "%.1f", decMpps)) Mpixels/s  (\(String(format: "%.1f", decMBps)) MB/s)")
            }
        }

        private func printJSON(
            imageWidth: Int, imageHeight: Int,
            imageBitsPerSample: Int, imageComponents: Int,
            uncompressedBytes: Int, avgEncodedSize: Int,
            pixelCount: Int, iterations: Int, warmup: Int,
            mode: String, near: Int, interleave: String,
            encodeStats: TimingStats, decodeStats: TimingStats
        ) {
            var result: [String: Any] = [
                "image": [
                    "width": imageWidth,
                    "height": imageHeight,
                    "bitsPerSample": imageBitsPerSample,
                    "components": imageComponents,
                    "uncompressedBytes": uncompressedBytes
                ] as [String: Any],
                "configuration": [
                    "mode": mode,
                    "near": near,
                    "interleave": interleave,
                    "iterations": iterations,
                    "warmup": warmup
                ] as [String: Any]
            ]

            if avgEncodedSize > 0 {
                let ratio = Double(uncompressedBytes) / Double(avgEncodedSize)
                result["compression"] = [
                    "encodedBytes": avgEncodedSize,
                    "ratio": ratio
                ]
            }

            if encodeStats.mean > 0 {
                result["encode"] = [
                    "minSeconds": encodeStats.min,
                    "maxSeconds": encodeStats.max,
                    "meanSeconds": encodeStats.mean,
                    "medianSeconds": encodeStats.median,
                    "throughputMpps": Double(pixelCount) / encodeStats.mean / 1_000_000,
                    "throughputMBps": Double(uncompressedBytes) / encodeStats.mean / (1024 * 1024)
                ]
            }

            if decodeStats.mean > 0 {
                result["decode"] = [
                    "minSeconds": decodeStats.min,
                    "maxSeconds": decodeStats.max,
                    "meanSeconds": decodeStats.mean,
                    "medianSeconds": decodeStats.median,
                    "throughputMpps": Double(pixelCount) / decodeStats.mean / 1_000_000,
                    "throughputMBps": Double(uncompressedBytes) / decodeStats.mean / (1024 * 1024)
                ]
            }

            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            } else {
                FileHandle.standardError.write(Data("Error: Failed to serialise JSON output\n".utf8))
            }
        }

        // MARK: - Helpers

        private enum BenchmarkMode: Equatable { case encode, decode, roundtrip }

        private func parseBenchmarkMode(_ s: String) throws -> BenchmarkMode {
            switch s.lowercased() {
            case "encode":    return .encode
            case "decode":    return .decode
            case "roundtrip": return .roundtrip
            default:
                throw ValidationError("Invalid mode '\(s)'. Must be encode, decode, or roundtrip")
            }
        }

        private func parseInterleaveMode(_ s: String) throws -> JPEGLSInterleaveMode {
            switch s.lowercased() {
            case "none":   return .none
            case "line":   return .line
            case "sample": return .sample
            default:
                throw ValidationError("Invalid interleave mode '\(s)'. Must be none, line, or sample")
            }
        }

        /// Generate a synthetic gradient image with `[component][row][col]` layout.
        private func generateSyntheticImage(
            width: Int, height: Int, bitsPerSample: Int, components: Int
        ) throws -> MultiComponentImageData {
            let maxVal = (1 << bitsPerSample) - 1
            let total  = max(width * height - 1, 1)
            var componentPixels: [[[Int]]] = []
            for c in 0..<components {
                let offset = c * (width * height / max(components, 1))
                var rows: [[Int]] = []
                for row in 0..<height {
                    var cols: [Int] = []
                    for col in 0..<width {
                        // Smooth gradient per component, shifted so each channel differs.
                        let val = ((row * width + col + offset) * maxVal) / total
                        cols.append(min(val, maxVal))
                    }
                    rows.append(cols)
                }
                componentPixels.append(rows)
            }
            switch components {
            case 1:
                return try MultiComponentImageData.grayscale(
                    pixels: componentPixels[0], bitsPerSample: bitsPerSample
                )
            case 3:
                return try MultiComponentImageData.rgb(
                    redPixels:   componentPixels[0],
                    greenPixels: componentPixels[1],
                    bluePixels:  componentPixels[2],
                    bitsPerSample: bitsPerSample
                )
            default:
                throw ValidationError("Unsupported component count: \(components)")
            }
        }

        /// Build `MultiComponentImageData` from a supported non-JPEG-LS image file.
        private func loadImageData(path: String, data: Data) throws -> MultiComponentImageData {
            let ext = (path as NSString).pathExtension.lowercased()

            if ext == "png" || PNGSupport.isPNG(data) {
                let png = try PNGSupport.decode(data)
                return try buildImageData(componentPixels: png.componentPixels, bitsPerSample: png.bitDepth)
            } else if ext == "tiff" || ext == "tif" || TIFFSupport.isTIFF(data) {
                let tiff = try TIFFSupport.decode(data)
                return try buildImageData(componentPixels: tiff.componentPixels, bitsPerSample: tiff.bitsPerSample)
            } else if ext == "pgm" || ext == "ppm" ||
                      (data.count >= 2 && data[0] == UInt8(ascii: "P") &&
                       (data[1] == UInt8(ascii: "5") || data[1] == UInt8(ascii: "6"))) {
                let pnm = try PNMSupport.parse(data)
                let bps = bitsNeeded(forMaxVal: pnm.maxVal)
                return try buildImageData(componentPixels: pnm.componentPixels, bitsPerSample: bps)
            }
            throw ValidationError(
                "Unsupported input format for '\(path)'. Supported: .jls, .png, .tiff, .tif, .pgm, .ppm"
            )
        }

        /// Construct `MultiComponentImageData` from a `[component][row][col]` pixel array.
        private func buildImageData(componentPixels: [[[Int]]], bitsPerSample: Int) throws -> MultiComponentImageData {
            switch componentPixels.count {
            case 1:
                return try MultiComponentImageData.grayscale(
                    pixels: componentPixels[0], bitsPerSample: bitsPerSample
                )
            case 3:
                return try MultiComponentImageData.rgb(
                    redPixels:   componentPixels[0],
                    greenPixels: componentPixels[1],
                    bluePixels:  componentPixels[2],
                    bitsPerSample: bitsPerSample
                )
            default:
                throw ValidationError("Unsupported component count: \(componentPixels.count)")
            }
        }

        /// Minimum bits needed to represent values up to `maxVal`.
        private func bitsNeeded(forMaxVal maxVal: Int) -> Int {
            var bits = 1
            while (1 << bits) - 1 < maxVal { bits += 1 }
            return bits
        }

        /// Format a duration in seconds as a human-readable string.
        private func formatTime(_ seconds: Double) -> String {
            if seconds < 0.001 {
                return "\(String(format: "%.1f", seconds * 1_000_000)) µs"
            } else if seconds < 1 {
                return "\(String(format: "%.2f", seconds * 1000)) ms"
            } else {
                return "\(String(format: "%.3f", seconds)) s"
            }
        }
    }
}
