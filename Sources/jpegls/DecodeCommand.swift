import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    struct Decode: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Decode JPEG-LS file to raw pixel data"
        )
        
        @Argument(help: "Input JPEG-LS file path")
        var input: String
        
        @Argument(help: "Output file path for raw pixel data")
        var output: String
        
        @Option(name: .long, help: "Output format: raw, pgm, ppm, png, tiff (default: raw)")
        var format: String = "raw"
        
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
            // Validate flags: verbose and quiet are mutually exclusive
            if verbose && quiet {
                throw ValidationError("Cannot use both --verbose and --quiet flags")
            }
            
            if verbose {
                print("JPEG-LS Decoder")
                print("===============")
                print("Input: \(input)")
                print("Output: \(output)")
                print("Format: \(format)")
                print()
            }
            
            // Read input file
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            
            if verbose {
                print("Input file size: \(inputData.count) bytes")
                print()
                print("Decoding JPEG-LS file...")
            }
            
            // Decode JPEG-LS file
            let decoder = JPEGLSDecoder()
            let imageData = try decoder.decode(inputData)
            
            if verbose {
                print("Decoded successfully!")
                print("  Width: \(imageData.frameHeader.width)")
                print("  Height: \(imageData.frameHeader.height)")
                print("  Bits per sample: \(imageData.frameHeader.bitsPerSample)")
                print("  Components: \(imageData.frameHeader.componentCount)")
                print()
            }
            
            // Write output based on format
            switch format.lowercased() {
            case "raw":
                // Write raw pixel data
                var outputData = Data()
                for component in imageData.components {
                    for row in component.pixels {
                        for pixel in row {
                            // Write pixel value in appropriate byte size
                            if imageData.frameHeader.bitsPerSample <= 8 {
                                outputData.append(UInt8(clamping: pixel))
                            } else {
                                // Write as 16-bit big-endian
                                let value = UInt16(clamping: pixel)
                                outputData.append(UInt8((value >> 8) & 0xFF))
                                outputData.append(UInt8(value & 0xFF))
                            }
                        }
                    }
                }
                
                try outputData.write(to: URL(fileURLWithPath: output))
                
                if !quiet {
                    print("Decoded \(imageData.frameHeader.width)x\(imageData.frameHeader.height) image to \(output) (\(outputData.count) bytes)")
                }
                
            case "pgm", "ppm":
                // Write PGM (grayscale) or PPM (colour) file
                let componentPixels: [[[Int]]] = imageData.components.map { $0.pixels }
                let maxVal = (1 << imageData.frameHeader.bitsPerSample) - 1
                let pnmData = try PNMSupport.encode(
                    componentPixels: componentPixels,
                    width: imageData.frameHeader.width,
                    height: imageData.frameHeader.height,
                    maxVal: maxVal
                )
                try pnmData.write(to: URL(fileURLWithPath: output))
                
                if !quiet {
                    let fmtName = imageData.components.count == 1 ? "PGM" : "PPM"
                    print("Decoded \(imageData.frameHeader.width)x\(imageData.frameHeader.height) image to \(output) as \(fmtName) (\(pnmData.count) bytes)")
                }
                
            case "png":
                // Write PNG file using the pure-Swift PNG encoder.
                let componentPixels: [[[Int]]] = imageData.components.map { $0.pixels }
                let maxVal = (1 << imageData.frameHeader.bitsPerSample) - 1
                let pngData = try PNGSupport.encode(
                    componentPixels: componentPixels,
                    width: imageData.frameHeader.width,
                    height: imageData.frameHeader.height,
                    maxVal: maxVal
                )
                try pngData.write(to: URL(fileURLWithPath: output))

                if !quiet {
                    print("Decoded \(imageData.frameHeader.width)x\(imageData.frameHeader.height) image to \(output) as PNG (\(pngData.count) bytes)")
                }
                
            case "tiff":
                // Write TIFF file using the pure-Swift TIFF encoder.
                let componentPixels: [[[Int]]] = imageData.components.map { $0.pixels }
                let maxVal = (1 << imageData.frameHeader.bitsPerSample) - 1
                let tiffData = try TIFFSupport.encode(
                    componentPixels: componentPixels,
                    width: imageData.frameHeader.width,
                    height: imageData.frameHeader.height,
                    maxVal: maxVal
                )
                try tiffData.write(to: URL(fileURLWithPath: output))

                if !quiet {
                    print("Decoded \(imageData.frameHeader.width)x\(imageData.frameHeader.height) image to \(output) as TIFF (\(tiffData.count) bytes)")
                }
                
            default:
                throw ValidationError("Unknown format '\(format)' — supported formats: raw, pgm, ppm, png, tiff")
            }
        }
    }
}
