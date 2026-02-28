import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    /// Command to compare two image files pixel-by-pixel.
    ///
    /// Both inputs may be JPEG-LS (`.jls`) files or PGM/PPM reference images.
    /// Decoded pixel data is compared component-by-component; differences are
    /// reported as max error, mean absolute error, and mismatch count.
    ///
    /// Exit code 0 indicates the images are identical (or within `--near`
    /// tolerance); exit code 1 indicates they differ.
    struct Compare: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compare two image files pixel-by-pixel",
            discussion: """
            Decodes both input files and compares their pixel data component-by-component.

            Inputs can be JPEG-LS (.jls) files or PGM/PPM reference images (.pgm/.ppm).

            Exit codes:
              0  Images are identical (or within --near tolerance for every pixel)
              1  Images differ, or an error occurred
            """
        )

        @Argument(help: "First input file (JPEG-LS, PGM, or PPM)")
        var first: String

        @Argument(help: "Second input file (JPEG-LS, PGM, or PPM)")
        var second: String

        @Option(
            name: .long,
            help: "Maximum per-pixel error tolerance (0 = exact match, default: 0)"
        )
        var near: Int = 0

        @Flag(name: .long, help: "Output comparison statistics in JSON format")
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

        mutating func run() throws {
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            if json && quiet {
                throw ValidationError("Cannot use both --json and --quiet flags")
            }
            guard (0...255).contains(near) else {
                throw ValidationError("--near must be between 0 and 255")
            }

            if verbose {
                print("JPEG-LS Compare")
                print("===============")
                print("First:  \(first)")
                print("Second: \(second)")
                print("NEAR tolerance: \(near)")
                print()
            }

            // Decode both inputs
            let img1 = try loadImage(path: first)
            let img2 = try loadImage(path: second)

            if verbose {
                print("First image:  \(img1.width)×\(img1.height), \(img1.bitsPerSample)-bit, \(img1.components.count) component(s)")
                print("Second image: \(img2.width)×\(img2.height), \(img2.bitsPerSample)-bit, \(img2.components.count) component(s)")
                print()
            }

            // Dimension / component check
            guard img1.components.count == img2.components.count else {
                if !quiet {
                    print("✗ Component count mismatch: \(img1.components.count) vs \(img2.components.count)")
                }
                throw ExitCode.failure
            }
            guard img1.width == img2.width && img1.height == img2.height else {
                if !quiet {
                    print("✗ Dimension mismatch: \(img1.width)×\(img1.height) vs \(img2.width)×\(img2.height)")
                }
                throw ExitCode.failure
            }

            // Compare pixel data
            var maxError = 0
            var totalError: Int64 = 0
            var mismatchCount = 0
            let numComponents = img1.components.count
            let totalPixels = img1.width * img1.height * numComponents

            for c in 0..<numComponents {
                for row in 0..<img1.height {
                    for col in 0..<img1.width {
                        let v1 = img1.components[c][row][col]
                        let v2 = img2.components[c][row][col]
                        let err = abs(v1 - v2)
                        if err > maxError { maxError = err }
                        totalError += Int64(err)
                        if err > near { mismatchCount += 1 }
                    }
                }
            }

            let meanAbsoluteError = totalPixels > 0
                ? Double(totalError) / Double(totalPixels)
                : 0.0
            let matches = mismatchCount == 0

            if json {
                printJSON(
                    matches: matches,
                    maxError: maxError,
                    meanAbsoluteError: meanAbsoluteError,
                    mismatchCount: mismatchCount,
                    totalPixels: totalPixels,
                    width: img1.width,
                    height: img1.height,
                    components: numComponents,
                    near: near
                )
            } else if !quiet {
                printHumanReadable(
                    matches: matches,
                    maxError: maxError,
                    meanAbsoluteError: meanAbsoluteError,
                    mismatchCount: mismatchCount,
                    totalPixels: totalPixels,
                    width: img1.width,
                    height: img1.height,
                    components: numComponents
                )
            }

            if !matches {
                throw ExitCode.failure
            }
        }

        // MARK: - Private helpers

        /// Intermediate representation of a decoded image.
        private struct DecodedImage {
            let width: Int
            let height: Int
            let bitsPerSample: Int
            /// Pixel data as `[component][row][col]`.
            let components: [[[Int]]]
        }

        /// Loads and decodes an image from `path`.  Supports JPEG-LS, PGM/PPM, PNG, and TIFF formats.
        private func loadImage(path: String) throws -> DecodedImage {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if isPNMFile(path: path, data: data) {
                let pnm = try PNMSupport.parse(data)
                return DecodedImage(
                    width: pnm.width,
                    height: pnm.height,
                    bitsPerSample: bitsNeeded(forMaxVal: pnm.maxVal),
                    components: pnm.componentPixels
                )
            } else if isPNGFile(path: path, data: data) {
                let png = try PNGSupport.decode(data)
                return DecodedImage(
                    width: png.width,
                    height: png.height,
                    bitsPerSample: png.bitDepth,
                    components: png.componentPixels
                )
            } else if isTIFFFile(path: path, data: data) {
                let tiff = try TIFFSupport.decode(data)
                return DecodedImage(
                    width: tiff.width,
                    height: tiff.height,
                    bitsPerSample: tiff.bitsPerSample,
                    components: tiff.componentPixels
                )
            } else {
                // Assume JPEG-LS
                let decoder = JPEGLSDecoder()
                let imageData = try decoder.decode(data)
                let components = imageData.components.map { $0.pixels }
                return DecodedImage(
                    width: imageData.frameHeader.width,
                    height: imageData.frameHeader.height,
                    bitsPerSample: imageData.frameHeader.bitsPerSample,
                    components: components
                )
            }
        }

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
            let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            return data.count >= 8 && Array(data.prefix(8)) == sig
        }

        private func isTIFFFile(path: String, data: Data) -> Bool {
            let ext = (path as NSString).pathExtension.lowercased()
            if ext == "tiff" || ext == "tif" { return true }
            if data.count >= 4 {
                let isLE = data[0] == 0x49 && data[1] == 0x49
                let isBE = data[0] == 0x4D && data[1] == 0x4D
                if isLE || isBE {
                    let magic = isLE
                        ? (UInt16(data[2]) | UInt16(data[3]) << 8)
                        : (UInt16(data[2]) << 8 | UInt16(data[3]))
                    return magic == 42
                }
            }
            return false
        }

        private func bitsNeeded(forMaxVal maxVal: Int) -> Int {
            var bits = 1
            while (1 << bits) - 1 < maxVal { bits += 1 }
            return bits
        }

        // MARK: - Output formatting

        private func printHumanReadable(
            matches: Bool,
            maxError: Int,
            meanAbsoluteError: Double,
            mismatchCount: Int,
            totalPixels: Int,
            width: Int,
            height: Int,
            components: Int
        ) {
            print("Image Comparison")
            print("================")
            print()
            print("Dimensions:  \(width)×\(height), \(components) component(s), \(totalPixels) total sample(s)")
            print("Max error:   \(maxError)")
            print("Mean error:  \(String(format: "%.4f", meanAbsoluteError))")
            print("Mismatches:  \(mismatchCount) / \(totalPixels) sample(s)")
            if near > 0 {
                print("Tolerance:   NEAR=\(near)")
            }
            print()
            if matches {
                let label = near > 0 ? "✓ Images match within NEAR=\(near) tolerance" : "✓ Images are identical"
                print(label)
            } else {
                print("✗ Images differ: \(mismatchCount) sample(s) exceed tolerance (max error \(maxError))")
            }
        }

        private func printJSON(
            matches: Bool,
            maxError: Int,
            meanAbsoluteError: Double,
            mismatchCount: Int,
            totalPixels: Int,
            width: Int,
            height: Int,
            components: Int,
            near: Int
        ) {
            let result: [String: Any] = [
                "match": matches,
                "width": width,
                "height": height,
                "components": components,
                "totalSamples": totalPixels,
                "maxError": maxError,
                "meanAbsoluteError": meanAbsoluteError,
                "mismatchCount": mismatchCount,
                "near": near
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                FileHandle.standardError.write(Data("Error: Failed to serialize JSON output\n".utf8))
            }
        }
    }
}
