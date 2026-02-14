import Foundation

/// Command-line tool for JPEG-LS encoding and decoding
@main
struct JPEGLSCLITool {
    static func main() {
        print("jpegls - JPEG-LS command-line tool")
        print("Version: 0.1.0")
        print()
        print("Usage: jpegls <command> [options]")
        print()
        print("Commands:")
        print("  encode    Encode image to JPEG-LS format")
        print("  decode    Decode JPEG-LS file")
        print("  info      Display information about JPEG-LS file")
        print("  verify    Verify JPEG-LS file integrity")
        print()
        print("Run 'jpegls <command> --help' for more information on a command.")
    }
}
