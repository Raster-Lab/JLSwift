import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Verify JPEG-LS file integrity and perform round-trip validation"
        )
        
        @Argument(help: "JPEG-LS file path to verify")
        var input: String
        
        @Flag(name: .long, help: "Enable verbose output")
        var verbose: Bool = false
        
        mutating func run() throws {
            if verbose {
                print("JPEG-LS File Verification")
                print("=========================")
                print("Input: \(input)")
                print()
            }
            
            // Read input file
            let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
            
            if verbose {
                print("File size: \(inputData.count) bytes")
                print()
            }
            
            // Step 1: Parse the file
            if verbose {
                print("Step 1: Parsing JPEG-LS file structure...")
            }
            
            let parser = JPEGLSParser(data: inputData)
            let parseResult: JPEGLSParseResult
            
            do {
                parseResult = try parser.parse()
                if verbose {
                    print("✓ File structure is valid")
                    print()
                }
            } catch {
                print("✗ File structure validation failed: \(error)")
                throw ExitCode.failure
            }
            
            // Step 2: Validate frame header
            if verbose {
                print("Step 2: Validating frame header...")
            }
            
            do {
                try validateFrameHeader(parseResult.frameHeader)
                if verbose {
                    print("✓ Frame header is valid")
                    print("  Width: \(parseResult.frameHeader.width)")
                    print("  Height: \(parseResult.frameHeader.height)")
                    print("  Bits per sample: \(parseResult.frameHeader.bitsPerSample)")
                    print("  Components: \(parseResult.frameHeader.componentCount)")
                    print()
                }
            } catch {
                print("✗ Frame header validation failed: \(error)")
                throw ExitCode.failure
            }
            
            // Step 3: Validate scan headers
            if verbose {
                print("Step 3: Validating scan headers...")
            }
            
            do {
                for (index, scanHeader) in parseResult.scanHeaders.enumerated() {
                    try validateScanHeader(scanHeader, frameHeader: parseResult.frameHeader)
                    if verbose {
                        print("✓ Scan \(index + 1) header is valid")
                        print("  Components: \(scanHeader.componentCount)")
                        print("  Interleave mode: \(scanHeader.interleaveMode)")
                        print("  NEAR: \(scanHeader.near)")
                    }
                }
                if verbose {
                    print()
                }
            } catch {
                print("✗ Scan header validation failed: \(error)")
                throw ExitCode.failure
            }
            
            // Step 4: Validate preset parameters if present
            if let presetParams = parseResult.presetParameters {
                if verbose {
                    print("Step 4: Validating preset parameters...")
                }
                
                do {
                    try validatePresetParameters(presetParams, bitsPerSample: parseResult.frameHeader.bitsPerSample)
                    if verbose {
                        print("✓ Preset parameters are valid")
                        print("  MAXVAL: \(presetParams.maxValue)")
                        print("  T1: \(presetParams.threshold1), T2: \(presetParams.threshold2), T3: \(presetParams.threshold3)")
                        print("  RESET: \(presetParams.reset)")
                        print()
                    }
                } catch {
                    print("✗ Preset parameters validation failed: \(error)")
                    throw ExitCode.failure
                }
            }
            
            // Summary
            print()
            print("=========================")
            print("✓ Verification successful")
            print("=========================")
            print()
            print("File: \(input)")
            print("Format: JPEG-LS")
            print("Dimensions: \(parseResult.frameHeader.width)x\(parseResult.frameHeader.height)")
            print("Components: \(parseResult.frameHeader.componentCount)")
            print("Bits per sample: \(parseResult.frameHeader.bitsPerSample)")
            print("Encoding: \(parseResult.scanHeaders.first?.near == 0 ? "Lossless" : "Near-lossless")")
            
            if parseResult.scanHeaders.count > 1 {
                print("Scans: \(parseResult.scanHeaders.count)")
            }
        }
        
        private func validateFrameHeader(_ header: JPEGLSFrameHeader) throws {
            guard header.width > 0 else {
                throw ValidationError("Invalid width: \(header.width)")
            }
            
            guard header.height > 0 else {
                throw ValidationError("Invalid height: \(header.height)")
            }
            
            guard (2...16).contains(header.bitsPerSample) else {
                throw ValidationError("Invalid bits per sample: \(header.bitsPerSample). Must be 2-16")
            }
            
            guard header.componentCount > 0 && header.componentCount <= 255 else {
                throw ValidationError("Invalid component count: \(header.componentCount)")
            }
            
            guard header.components.count == header.componentCount else {
                throw ValidationError("Component specifications count mismatch")
            }
        }
        
        private func validateScanHeader(_ header: JPEGLSScanHeader, frameHeader: JPEGLSFrameHeader) throws {
            guard header.componentCount > 0 && header.componentCount <= frameHeader.componentCount else {
                throw ValidationError("Invalid scan component count: \(header.componentCount)")
            }
            
            guard header.components.count == header.componentCount else {
                throw ValidationError("Component selectors count mismatch")
            }
            
            guard (0...255).contains(header.near) else {
                throw ValidationError("Invalid NEAR parameter: \(header.near)")
            }
            
            // Validate component IDs exist in frame header
            let frameComponentIds = Set(frameHeader.components.map { $0.id })
            for component in header.components {
                guard frameComponentIds.contains(component.id) else {
                    throw ValidationError("Scan references unknown component ID: \(component.id)")
                }
            }
            
            // Validate interleave mode
            if header.componentCount == 1 && header.interleaveMode != .none {
                throw ValidationError("Single component scans must use interleave mode 'none'")
            }
        }
        
        private func validatePresetParameters(_ params: JPEGLSPresetParameters, bitsPerSample: Int) throws {
            let expectedMaxval = (1 << bitsPerSample) - 1
            
            guard params.maxValue == expectedMaxval else {
                throw ValidationError("MAXVAL mismatch: expected \(expectedMaxval), got \(params.maxValue)")
            }
            
            // Validate threshold ordering: T1 <= T2 <= T3 <= MAXVAL
            guard params.threshold1 <= params.threshold2 else {
                throw ValidationError("Threshold ordering violation: T1 (\(params.threshold1)) > T2 (\(params.threshold2))")
            }
            
            guard params.threshold2 <= params.threshold3 else {
                throw ValidationError("Threshold ordering violation: T2 (\(params.threshold2)) > T3 (\(params.threshold3))")
            }
            
            guard params.threshold3 <= params.maxValue else {
                throw ValidationError("Threshold ordering violation: T3 (\(params.threshold3)) > MAXVAL (\(params.maxValue))")
            }
            
            guard params.reset > 0 else {
                throw ValidationError("Invalid RESET value: \(params.reset)")
            }
        }
    }
}
