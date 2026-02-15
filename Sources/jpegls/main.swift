import ArgumentParser
import Foundation
import JPEGLS

/// Command-line tool for JPEG-LS encoding and decoding
struct JPEGLSCLITool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jpegls",
        abstract: "JPEG-LS command-line tool for encoding and decoding",
        version: "0.1.0",
        subcommands: [Encode.self, Decode.self, Info.self, Verify.self],
        defaultSubcommand: nil
    )
}

JPEGLSCLITool.main()
