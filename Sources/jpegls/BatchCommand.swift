import ArgumentParser
import Foundation
import JPEGLS

/// Batch processing command for multiple JPEG-LS files
struct Batch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch",
        abstract: "Process multiple JPEG-LS files in batch",
        discussion: """
        Process multiple JPEG-LS files with encode, decode, info, or verify operations.
        Supports glob patterns for input file selection and parallel processing.
        """
    )
    
    // MARK: - Arguments
    
    @Argument(help: "Operation to perform: encode, decode, info, verify")
    var operation: String
    
    @Argument(help: "Input glob pattern (e.g., '*.jls', 'images/*.raw') or directory path")
    var inputPattern: String
    
    @Option(name: .shortAndLong, help: "Output directory for processed files")
    var outputDir: String?
    
    // MARK: - Encoding Options
    
    @Option(name: .shortAndLong, help: "Image width in pixels (required for encode)")
    var width: Int?
    
    @Option(name: .shortAndLong, help: "Image height in pixels (required for encode)")
    var height: Int?
    
    @Option(name: .shortAndLong, help: "Bits per sample, 2-16 (default: 8)")
    var bitsPerSample: Int = 8
    
    @Option(name: .shortAndLong, help: "Number of components - 1 (grayscale) or 3 (RGB) (default: 1)")
    var components: Int = 1
    
    @Option(help: "NEAR parameter, 0=lossless, 1-255=lossy (default: 0)")
    var near: Int = 0
    
    @Option(help: "Interleave mode: none, line, sample (default: none)")
    var interleave: String = "none"
    
    @Option(
        name: [.customLong("color-transform"), .customLong("colour-transform")],
        help: "Colour transformation: none, hp1, hp2, hp3 (default: none). Accepts both --color-transform and --colour-transform."
    )
    var colorTransform: String = "none"
    
    // MARK: - Processing Options
    
    @Option(name: .shortAndLong, help: "Maximum number of parallel operations (default: system processor count)")
    var parallelism: Int?
    
    @Flag(name: .shortAndLong, help: "Show detailed progress for each file")
    var verbose: Bool = false
    
    @Flag(name: .shortAndLong, help: "Suppress all output except errors")
    var quiet: Bool = false
    
    @Flag(help: "Stop processing on first error (default: continue processing all files)")
    var failFast: Bool = false
    
    @Flag(
        name: [.customLong("summarise"), .customLong("summarize")],
        help: "Print a detailed summary table after batch processing (shown even in quiet mode). Accepts both --summarise and --summarize."
    )
    var summarise: Bool = false
    
    @Flag(
        name: [.customLong("no-colour"), .customLong("no-color")],
        help: "Disable ANSI colour codes in terminal output. Accepts both --no-colour and --no-color."
    )
    var noColour: Bool = false
    
    // MARK: - Validation
    
    mutating func validate() throws {
        // Validate operation type
        let validOperations = ["encode", "decode", "info", "verify"]
        guard validOperations.contains(operation.lowercased()) else {
            throw ValidationError("Invalid operation '\(operation)'. Must be one of: \(validOperations.joined(separator: ", "))")
        }
        
        // Validate mutually exclusive flags
        if verbose && quiet {
            throw ValidationError("Cannot specify both --verbose and --quiet")
        }
        
        // Validate encode-specific requirements
        if operation.lowercased() == "encode" {
            guard let width = width, width > 0 else {
                throw ValidationError("--width is required and must be positive for encode operation")
            }
            guard let height = height, height > 0 else {
                throw ValidationError("--height is required and must be positive for encode operation")
            }
            guard (2...16).contains(bitsPerSample) else {
                throw ValidationError("--bits-per-sample must be between 2 and 16")
            }
            guard components == 1 || components == 3 else {
                throw ValidationError("--components must be 1 (grayscale) or 3 (RGB)")
            }
            guard (0...255).contains(near) else {
                throw ValidationError("--near must be between 0 and 255")
            }
        }
        
        // Validate output directory for encode/decode operations
        if operation.lowercased() == "encode" || operation.lowercased() == "decode" {
            guard outputDir != nil else {
                throw ValidationError("--output-dir is required for \(operation) operation")
            }
        }
        
        // Validate parallelism
        if let parallelism = parallelism, parallelism < 1 {
            throw ValidationError("--parallelism must be at least 1")
        }
    }
    
    // MARK: - Execution
    
    func run() throws {
        let processor = BatchProcessor(
            operation: operation.lowercased(),
            inputPattern: inputPattern,
            outputDir: outputDir,
            encodeOptions: EncodeOptions(
                width: width ?? 0,
                height: height ?? 0,
                bitsPerSample: bitsPerSample,
                components: components,
                near: near,
                interleave: interleave,
                colorTransform: colorTransform
            ),
            parallelism: parallelism ?? ProcessInfo.processInfo.processorCount,
            verbose: verbose,
            quiet: quiet,
            failFast: failFast,
            summarise: summarise,
            noColour: noColour
        )
        
        try processor.process()
    }
}

// MARK: - Encode Options

struct EncodeOptions: Sendable {
    let width: Int
    let height: Int
    let bitsPerSample: Int
    let components: Int
    let near: Int
    let interleave: String
    let colorTransform: String
}

// MARK: - Batch Processor

struct BatchProcessor: Sendable {
    let operation: String
    let inputPattern: String
    let outputDir: String?
    let encodeOptions: EncodeOptions
    let parallelism: Int
    let verbose: Bool
    let quiet: Bool
    let failFast: Bool
    let summarise: Bool
    let noColour: Bool
    
    func process() throws {
        // Find input files matching pattern
        let inputFiles = try findInputFiles()
        
        if inputFiles.isEmpty {
            if !quiet {
                print("No files found matching pattern: \(inputPattern)")
            }
            return
        }
        
        if !quiet {
            print("Found \(inputFiles.count) file(s) to process")
            if verbose {
                print("Operation: \(operation)")
                print("Parallelism: \(parallelism)")
            }
        }
        
        // Create output directory if needed
        if let outputDir = outputDir {
            try createOutputDirectory(outputDir)
        }
        
        // Process files concurrently using DispatchQueue
        let results = processFilesConcurrently(inputFiles)
        
        // Print summary: always when summarise is set; also when not quiet
        if !quiet || summarise {
            printSummary(results: results)
        }
        
        // Exit with error if any files failed
        if results.failures > 0 {
            throw ExitCode.failure
        }
    }
    
    private func findInputFiles() throws -> [String] {
        let fileManager = FileManager.default
        
        // Check if input pattern is a directory
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: inputPattern, isDirectory: &isDirectory), isDirectory.boolValue {
            // List all files in directory
            let contents = try fileManager.contentsOfDirectory(atPath: inputPattern)
            return contents.map { (inputPattern as NSString).appendingPathComponent($0) }
        }
        
        // Handle glob pattern
        return try expandGlobPattern(inputPattern)
    }
    
    private func expandGlobPattern(_ pattern: String) throws -> [String] {
        let fileManager = FileManager.default
        
        // Split pattern into directory and file pattern
        let patternURL = URL(fileURLWithPath: pattern)
        let directory = patternURL.deletingLastPathComponent().path
        let filePattern = patternURL.lastPathComponent
        
        // If directory doesn't exist, try current directory
        let searchDirectory = fileManager.fileExists(atPath: directory) ? directory : FileManager.default.currentDirectoryPath
        
        // Get all files in directory
        guard let contents = try? fileManager.contentsOfDirectory(atPath: searchDirectory) else {
            return []
        }
        
        // Filter files matching pattern
        let matchingFiles = contents.filter { filename in
            matchesGlobPattern(filename: filename, pattern: filePattern)
        }
        
        return matchingFiles.map { (searchDirectory as NSString).appendingPathComponent($0) }
    }
    
    private func matchesGlobPattern(filename: String, pattern: String) -> Bool {
        // Simple glob pattern matching (* and ?)
        var patternIndex = pattern.startIndex
        var filenameIndex = filename.startIndex
        
        while patternIndex < pattern.endIndex && filenameIndex < filename.endIndex {
            let patternChar = pattern[patternIndex]
            
            if patternChar == "*" {
                // Match any sequence of characters
                if patternIndex == pattern.index(before: pattern.endIndex) {
                    // * at end matches everything
                    return true
                }
                
                // Try to match rest of pattern
                let nextPatternIndex = pattern.index(after: patternIndex)
                while filenameIndex <= filename.endIndex {
                    if matchesGlobPattern(
                        filename: String(filename[filenameIndex...]),
                        pattern: String(pattern[nextPatternIndex...])
                    ) {
                        return true
                    }
                    if filenameIndex == filename.endIndex {
                        break
                    }
                    filenameIndex = filename.index(after: filenameIndex)
                }
                return false
            } else if patternChar == "?" {
                // Match any single character
                filenameIndex = filename.index(after: filenameIndex)
                patternIndex = pattern.index(after: patternIndex)
            } else {
                // Match exact character
                if filename[filenameIndex] != patternChar {
                    return false
                }
                filenameIndex = filename.index(after: filenameIndex)
                patternIndex = pattern.index(after: patternIndex)
            }
        }
        
        // Check if both strings are fully consumed
        return patternIndex == pattern.endIndex && filenameIndex == filename.endIndex
    }
    
    private func createOutputDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            if verbose && !quiet {
                print("Created output directory: \(path)")
            }
        }
    }
    
    /// Process files concurrently using DispatchQueue with a parallelism limit.
    ///
    /// Uses a concurrent dispatch queue with a semaphore to limit the number
    /// of in-flight tasks to `parallelism`.
    private func processFilesConcurrently(_ files: [String]) -> BatchResults {
        let queue = DispatchQueue(label: "jpegls.batch", attributes: .concurrent)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: parallelism)
        let aggregator = ResultsAggregator()

        let total = files.count
        for (index, file) in files.enumerated() {
            // Check cancellation before waiting on the semaphore
            if aggregator.isCancelled { break }

            semaphore.wait()

            group.enter()
            queue.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }

                let result = self.processFile(file, index: index, total: total)
                aggregator.record(result)

                if self.failFast && !result.success {
                    aggregator.cancel()
                }
            }
        }
        
        group.wait()
        
        return aggregator.results
    }
    
    private func processFile(_ inputFile: String, index: Int, total: Int) -> FileResult {
        let startTime = Date()
        
        do {
            if verbose && !quiet {
                print("[\(index + 1)/\(total)] Processing: \(inputFile)")
            }
            
            let outputFile = try generateOutputFile(for: inputFile)
            
            switch operation {
            case "encode":
                try processEncode(input: inputFile, output: outputFile)
            case "decode":
                try processDecode(input: inputFile, output: outputFile)
            case "info":
                try processInfo(input: inputFile)
            case "verify":
                try processVerify(input: inputFile)
            default:
                throw ValidationError("Unknown operation: \(operation)")
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            if verbose && !quiet {
                print("  ✓ Success (\(String(format: "%.2f", duration))s)")
            } else if !quiet {
                print(".", terminator: "")
            }
            
            return FileResult(file: inputFile, success: true, duration: duration, error: nil)
            
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            
            if !quiet {
                print("  ✗ Failed: \(error.localizedDescription)")
            }
            
            return FileResult(file: inputFile, success: false, duration: duration, error: error)
        }
    }
    
    private func generateOutputFile(for inputFile: String) throws -> String {
        guard let outputDir = outputDir else {
            return "" // Not needed for info/verify operations
        }
        
        let inputURL = URL(fileURLWithPath: inputFile)
        let inputBasename = inputURL.deletingPathExtension().lastPathComponent
        
        let outputExtension: String
        switch operation {
        case "encode":
            outputExtension = "jls"
        case "decode":
            outputExtension = "raw"
        default:
            outputExtension = inputURL.pathExtension
        }
        
        let outputFilename = inputBasename + "." + outputExtension
        return (outputDir as NSString).appendingPathComponent(outputFilename)
    }
    
    private func processEncode(input: String, output: String) throws {
        // Placeholder for encode implementation
        // TODO: Integrate with actual encoder when bitstream writer is complete
        throw ValidationError("Encode operation requires bitstream writer integration (not yet implemented)")
    }
    
    private func processDecode(input: String, output: String) throws {
        // Placeholder for decode implementation
        // TODO: Integrate with actual decoder when bitstream reader is complete
        throw ValidationError("Decode operation requires bitstream reader integration (not yet implemented)")
    }
    
    private func processInfo(input: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        if verbose && !quiet {
            let frame = parseResult.frameHeader
            print("  Frame: \(frame.width)x\(frame.height), \(frame.bitsPerSample)-bit, \(frame.componentCount) components")
        }
    }
    
    private func processVerify(input: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let parser = JPEGLSParser(data: data)
        _ = try parser.parse()
        
        // Validation is performed during parsing
        // If we get here, the file is valid
        if verbose && !quiet {
            print("  Valid JPEG-LS file")
        }
    }
    
    private func printSummary(results: BatchResults) {
        print("\n\nBatch Processing Summary:")
        print("  Total files: \(results.total)")
        print("  Successful: \(results.successes)")
        print("  Failed: \(results.failures)")
        
        if results.total > 0 {
            let totalDuration = results.totalDuration
            let avgDuration = totalDuration / Double(results.total)
            print("  Total time: \(String(format: "%.2f", totalDuration))s")
            print("  Average time: \(String(format: "%.2f", avgDuration))s per file")
        }
        
        if !results.failedFiles.isEmpty && verbose {
            print("\nFailed files:")
            for file in results.failedFiles {
                print("  - \(file)")
            }
        }
    }
}

// MARK: - Results Aggregator

/// Thread-safe aggregator for collecting batch processing results.
final class ResultsAggregator: @unchecked Sendable {
    private let lock = NSLock()
    private var successes = 0
    private var failures = 0
    private var totalDuration: TimeInterval = 0
    private var failedFiles: [String] = []
    private var _cancelled = false
    
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }
    
    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }
    
    func record(_ result: FileResult) {
        lock.lock()
        if result.success {
            successes += 1
        } else {
            failures += 1
            failedFiles.append(result.file)
        }
        totalDuration += result.duration
        lock.unlock()
    }
    
    var results: BatchResults {
        lock.lock()
        defer { lock.unlock() }
        return BatchResults(
            successes: successes,
            failures: failures,
            totalDuration: totalDuration,
            failedFiles: failedFiles
        )
    }
}

// MARK: - Results Tracking

struct FileResult: Sendable {
    let file: String
    let success: Bool
    let duration: TimeInterval
    let error: Error?
}

struct BatchResults: Sendable {
    let successes: Int
    let failures: Int
    let totalDuration: TimeInterval
    let failedFiles: [String]
    
    var total: Int {
        successes + failures
    }
}
