import ArgumentParser
import Foundation
import JPEGLS

/// Validation error for CLI argument validation
struct ValidationError: Error, CustomStringConvertible {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var description: String {
        message
    }
}

/// Command-line tool for JPEG-LS encoding and decoding
struct JPEGLSCLITool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jpegls",
        abstract: "JPEG-LS command-line tool for encoding and decoding",
        version: "0.1.0",
        subcommands: [Encode.self, Decode.self, Info.self, Verify.self, Batch.self, Compare.self, Convert.self, Benchmark.self, Completion.self],
        defaultSubcommand: nil
    )
}

JPEGLSCLITool.main()
