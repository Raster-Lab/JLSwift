import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display information about JPEG-LS file"
        )
        
        @Argument(help: "JPEG-LS file path")
        var input: String
        
        @Flag(name: .long, help: "Output in JSON format")
        var json: Bool = false
        
        mutating func run() throws {
            // Read input file
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            
            // Parse JPEG-LS file
            let parser = JPEGLSParser(data: inputData)
            let parseResult = try parser.parse()
            
            if json {
                // Output JSON format
                printJSON(parseResult: parseResult, fileSize: inputData.count)
            } else {
                // Output human-readable format
                printHumanReadable(parseResult: parseResult, fileSize: inputData.count)
            }
        }
        
        private func printHumanReadable(parseResult: JPEGLSParseResult, fileSize: Int) {
            print("JPEG-LS File Information")
            print("========================")
            print()
            
            print("File size: \(fileSize) bytes")
            print()
            
            print("Frame Header:")
            print("  Width: \(parseResult.frameHeader.width) pixels")
            print("  Height: \(parseResult.frameHeader.height) pixels")
            print("  Bits per sample: \(parseResult.frameHeader.bitsPerSample)")
            print("  Component count: \(parseResult.frameHeader.componentCount)")
            
            if parseResult.frameHeader.componentCount > 1 {
                print("  Component specifications:")
                for (index, spec) in parseResult.frameHeader.components.enumerated() {
                    print("    Component \(index + 1): ID=\(spec.id), H=\(spec.horizontalSamplingFactor), V=\(spec.verticalSamplingFactor)")
                }
            }
            print()
            
            print("Scan Headers: \(parseResult.scanHeaders.count)")
            for (index, scanHeader) in parseResult.scanHeaders.enumerated() {
                print("  Scan \(index + 1):")
                print("    Component count: \(scanHeader.componentCount)")
                print("    Component IDs: \(scanHeader.components.map { String($0.id) }.joined(separator: ", "))")
                print("    Interleave mode: \(formatInterleaveMode(scanHeader.interleaveMode))")
                print("    NEAR: \(scanHeader.near) (\(scanHeader.near == 0 ? "lossless" : "near-lossless"))")
                print("    Point transform: \(scanHeader.pointTransform)")
                print()
            }
            
            if let presetParams = parseResult.presetParameters {
                print("Preset Parameters:")
                print("  MAXVAL: \(presetParams.maxValue)")
                print("  T1: \(presetParams.threshold1)")
                print("  T2: \(presetParams.threshold2)")
                print("  T3: \(presetParams.threshold3)")
                print("  RESET: \(presetParams.reset)")
                print()
            }
            
            // Calculate approximate compression ratio
            let uncompressedSize = parseResult.frameHeader.width * 
                                  parseResult.frameHeader.height * 
                                  parseResult.frameHeader.componentCount * 
                                  ((parseResult.frameHeader.bitsPerSample + 7) / 8)
            let compressionRatio = Double(uncompressedSize) / Double(fileSize)
            
            print("Compression:")
            print("  Uncompressed size: \(uncompressedSize) bytes")
            print("  Compressed size: \(fileSize) bytes")
            print("  Compression ratio: \(String(format: "%.2f", compressionRatio)):1")
            print("  Space savings: \(String(format: "%.1f", (1.0 - 1.0/compressionRatio) * 100))%")
        }
        
        private func printJSON(parseResult: JPEGLSParseResult, fileSize: Int) {
            var json: [String: Any] = [:]
            
            json["fileSize"] = fileSize
            
            json["frameHeader"] = [
                "width": parseResult.frameHeader.width,
                "height": parseResult.frameHeader.height,
                "bitsPerSample": parseResult.frameHeader.bitsPerSample,
                "componentCount": parseResult.frameHeader.componentCount,
                "componentSpecifications": parseResult.frameHeader.components.map { spec in
                    [
                        "componentId": spec.id,
                        "horizontalSamplingFactor": spec.horizontalSamplingFactor,
                        "verticalSamplingFactor": spec.verticalSamplingFactor
                    ]
                }
            ]
            
            json["scanHeaders"] = parseResult.scanHeaders.map { scanHeader in
                [
                    "componentCount": scanHeader.componentCount,
                    "componentIds": scanHeader.components.map { $0.id },
                    "interleaveMode": formatInterleaveMode(scanHeader.interleaveMode),
                    "near": scanHeader.near,
                    "pointTransform": scanHeader.pointTransform
                ]
            }
            
            if let presetParams = parseResult.presetParameters {
                json["presetParameters"] = [
                    "maxval": presetParams.maxValue,
                    "t1": presetParams.threshold1,
                    "t2": presetParams.threshold2,
                    "t3": presetParams.threshold3,
                    "reset": presetParams.reset
                ]
            }
            
            let uncompressedSize = parseResult.frameHeader.width * 
                                  parseResult.frameHeader.height * 
                                  parseResult.frameHeader.componentCount * 
                                  ((parseResult.frameHeader.bitsPerSample + 7) / 8)
            let compressionRatio = Double(uncompressedSize) / Double(fileSize)
            
            json["compression"] = [
                "uncompressedSize": uncompressedSize,
                "compressedSize": fileSize,
                "compressionRatio": compressionRatio,
                "spaceSavings": (1.0 - 1.0/compressionRatio) * 100
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                // Fallback: Print error message to stderr
                FileHandle.standardError.write(Data("Error: Failed to serialize JSON output\n".utf8))
            }
        }
        
        private func formatInterleaveMode(_ mode: JPEGLSInterleaveMode) -> String {
            switch mode {
            case .none:
                return "none"
            case .line:
                return "line"
            case .sample:
                return "sample"
            }
        }
    }
}
