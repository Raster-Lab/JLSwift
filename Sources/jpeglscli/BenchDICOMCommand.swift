import ArgumentParser
import Foundation
import JPEGLS

extension JPEGLSCLITool {
    /// Walk a tree of DICOM files, encode each native grayscale frame to
    /// JPEG-LS, decode it back, verify the round-trip is bit-exact, and report
    /// compression ratio and throughput grouped by modality.
    ///
    /// Intended for validating the codec against real medical-imaging data
    /// (the radiology DICOM corpus). It is both a conformance check
    /// (lossless == every reconstructed sample matches the original) and a
    /// performance baseline (MB/s encode / decode per modality).
    struct BenchDICOM: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bench-dicom",
            abstract: "Round-trip & benchmark JPEG-LS over a DICOM image corpus",
            discussion: """
            Recursively scans a directory for .dcm files, groups them by the
            top-level folder (treated as the modality, e.g. CT/DX/MG/MR/PX/US/XA),
            and for every native (uncompressed) unsigned grayscale frame:

              encode (lossless) → decode → verify bit-exact → record ratio + timing

            Non-encodable frames (encapsulated/compressed, signed, or colour)
            are counted and skipped. Results are aggregated per modality.

            Examples:
              jpegls bench-dicom "/path/to/Radiology DICOM Data"
              jpegls bench-dicom CORPUS --limit 5
              jpegls bench-dicom CORPUS --modality CT,DX --max-pixels 4000000
              jpegls bench-dicom CORPUS --limit 10 --json
            """
        )

        @Argument(help: "Root directory to scan recursively for .dcm files")
        var root: String

        @Option(name: .long, help: "Max frames to process per modality (0 = no limit; default 3)")
        var limit: Int = 3

        @Option(name: .long, help: "Skip frames larger than this many pixels (0 = no cap)")
        var maxPixels: Int = 0

        @Option(name: .long, help: "Comma-separated modality filter (e.g. CT,DX); default: all")
        var modality: String?

        @Option(name: .long, help: "Near-lossless parameter (0 = lossless; default 0)")
        var near: Int = 0

        @Flag(name: .long, help: "Emit machine-readable JSON instead of a table")
        var json: Bool = false

        // MARK: - Per-frame / per-modality accumulators

        struct FrameResult {
            var modality: String
            var width: Int
            var height: Int
            var bitsStored: Int
            var originalBytes: Int
            var compressedBytes: Int
            var encodeSeconds: Double
            var decodeSeconds: Double
            var lossless: Bool
        }

        struct ModalityStats {
            var processed = 0   // encoded + decoded
            var skipped = 0     // parsed, but not a native unsigned grayscale frame
            var errors = 0      // could not read / parse the DICOM file at all
            var failures = 0    // encoded but the round-trip was NOT bit-exact
            var originalBytes = 0
            var compressedBytes = 0
            var encodeSeconds = 0.0
            var decodeSeconds = 0.0
            var pixels = 0
        }

        mutating func run() throws {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("Not a directory: \(root)")
            }

            let modalityFilter: Set<String>? = modality.map {
                Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }

            // Collect .dcm paths grouped by modality (first path component under root).
            var byModality: [String: [URL]] = [:]
            let rootComponents = rootURL.standardizedFileURL.pathComponents
            guard let walker = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                throw ValidationError("Cannot enumerate \(root)")
            }
            for case let url as URL in walker {
                guard url.pathExtension.lowercased() == "dcm" else { continue }
                let comps = url.standardizedFileURL.pathComponents
                let mod = comps.count > rootComponents.count ? comps[rootComponents.count] : "(root)"
                if let f = modalityFilter, !f.contains(mod) { continue }
                byModality[mod, default: []].append(url)
            }

            if byModality.isEmpty {
                throw ValidationError("No .dcm files found under \(root)")
            }

            var stats: [String: ModalityStats] = [:]
            var frames: [FrameResult] = []
            let encoder = JPEGLSEncoder()
            let decoder = JPEGLSDecoder()

            for mod in byModality.keys.sorted() {
                let urls = byModality[mod]!.sorted { $0.path < $1.path }
                var s = ModalityStats()
                if !json { FileHandle.standardError.write(Data("Scanning \(mod) (\(urls.count) files)…\n".utf8)) }

                for url in urls {
                    if limit > 0 && s.processed >= limit { break }

                    guard let data = try? Data(contentsOf: url),
                          let img = try? DICOMSupport.parse(data) else {
                        s.errors += 1
                        continue
                    }

                    guard let (pixels, bps) = DICOMSupport.grayscaleFrame(img) else {
                        s.skipped += 1
                        continue
                    }

                    let pixelCount = img.columns * img.rows
                    if maxPixels > 0 && pixelCount > maxPixels {
                        s.skipped += 1
                        continue
                    }

                    do {
                        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bps)
                        let config = try JPEGLSEncoder.Configuration(near: near)

                        let t0 = DispatchTime.now().uptimeNanoseconds
                        let encoded = try encoder.encode(imageData, configuration: config)
                        let t1 = DispatchTime.now().uptimeNanoseconds
                        let decoded = try decoder.decode(encoded)
                        let t2 = DispatchTime.now().uptimeNanoseconds

                        let lossless = (near == 0) && pixelsEqual(decoded.components.first?.pixels, pixels)
                        let originalBytes = img.columns * img.rows * img.bytesPerSample
                        let encS = Double(t1 - t0) / 1e9
                        let decS = Double(t2 - t1) / 1e9

                        s.processed += 1
                        s.originalBytes += originalBytes
                        s.compressedBytes += encoded.count
                        s.encodeSeconds += encS
                        s.decodeSeconds += decS
                        s.pixels += pixelCount
                        if near == 0 && !lossless {
                            s.failures += 1
                            let where_ = firstMismatch(decoded.components.first?.pixels, pixels)
                            FileHandle.standardError.write(Data(
                                "FAIL lossless: \(url.path)  \(img.columns)x\(img.rows) \(bps)-bit\(where_)\n".utf8))
                        }

                        frames.append(FrameResult(
                            modality: mod, width: img.columns, height: img.rows,
                            bitsStored: img.bitsStored, originalBytes: originalBytes,
                            compressedBytes: encoded.count, encodeSeconds: encS,
                            decodeSeconds: decS, lossless: lossless
                        ))
                    } catch {
                        s.failures += 1
                        FileHandle.standardError.write(Data(
                            "FAIL error: \(url.path)  \(error)\n".utf8))
                    }
                }
                stats[mod] = s
            }

            if json {
                printJSON(stats: stats, frames: frames)
            } else {
                printTable(stats: stats)
            }
        }

        // MARK: - Helpers

        private func pixelsEqual(_ a: [[Int]]?, _ b: [[Int]]) -> Bool {
            guard let a = a, a.count == b.count else { return false }
            for r in 0..<a.count where a[r] != b[r] { return false }
            return true
        }

        /// Describe the first differing sample between decoded and original
        /// pixels, for actionable failure reports. Empty string if identical.
        private func firstMismatch(_ a: [[Int]]?, _ b: [[Int]]) -> String {
            guard let a = a else { return "  (decoded image had no component)" }
            if a.count != b.count { return "  (decoded \(a.count) rows != original \(b.count))" }
            for r in 0..<a.count where a[r] != b[r] {
                let cols = min(a[r].count, b[r].count)
                for c in 0..<cols where a[r][c] != b[r][c] {
                    return "  first mismatch at (row \(r), col \(c)): decoded \(a[r][c]) != original \(b[r][c])"
                }
                return "  row \(r) length differs (decoded \(a[r].count) vs original \(b[r].count))"
            }
            return ""
        }

        private func printTable(stats: [String: ModalityStats]) {
            print("")
            print("JPEG-LS DICOM round-trip  (near=\(near))")
            print(String(repeating: "─", count: 90))
            print(String(format: "%-8@ %7@ %6@ %6@ %6@ %9@ %8@ %10@ %10@",
                         "MOD" as NSString, "frames" as NSString, "skip" as NSString, "err" as NSString,
                         "fail" as NSString, "ratio" as NSString, "MP" as NSString,
                         "enc MB/s" as NSString, "dec MB/s" as NSString))
            print(String(repeating: "─", count: 90))

            var t = ModalityStats()
            for mod in stats.keys.sorted() {
                let s = stats[mod]!
                printRow(mod, s)
                t.originalBytes += s.originalBytes; t.compressedBytes += s.compressedBytes
                t.processed += s.processed; t.skipped += s.skipped; t.errors += s.errors
                t.failures += s.failures
                t.encodeSeconds += s.encodeSeconds; t.decodeSeconds += s.decodeSeconds; t.pixels += s.pixels
            }
            print(String(repeating: "─", count: 90))
            printRow("ALL", t)
            print("")
            if t.failures > 0 {
                print("⚠️  \(t.failures) frame(s) failed the lossless round-trip.")
            } else if t.processed > 0 {
                print("✓ All \(t.processed) processed frame(s) round-tripped losslessly.")
            }
            print("(skip = non-grayscale/encapsulated frames; err = unreadable DICOM)")
        }

        private func printRow(_ mod: String, _ s: ModalityStats) {
            let ratio = s.compressedBytes > 0 ? Double(s.originalBytes) / Double(s.compressedBytes) : 0
            let encMBs = s.encodeSeconds > 0 ? (Double(s.originalBytes) / 1_000_000.0) / s.encodeSeconds : 0
            let decMBs = s.decodeSeconds > 0 ? (Double(s.originalBytes) / 1_000_000.0) / s.decodeSeconds : 0
            let mp = Double(s.pixels) / 1_000_000.0
            print(String(format: "%-8@ %7d %6d %6d %6d %8.2f:1 %8.1f %10.1f %10.1f",
                         mod as NSString, s.processed, s.skipped, s.errors, s.failures, ratio, mp, encMBs, decMBs))
        }

        private func printJSON(stats: [String: ModalityStats], frames: [FrameResult]) {
            var modObjs: [String] = []
            for mod in stats.keys.sorted() {
                let s = stats[mod]!
                let ratio = s.compressedBytes > 0 ? Double(s.originalBytes) / Double(s.compressedBytes) : 0
                modObjs.append("""
                    {"modality":"\(mod)","frames":\(s.processed),"skipped":\(s.skipped),"errors":\(s.errors),"failures":\(s.failures),"originalBytes":\(s.originalBytes),"compressedBytes":\(s.compressedBytes),"ratio":\(String(format: "%.4f", ratio)),"encodeSeconds":\(String(format: "%.4f", s.encodeSeconds)),"decodeSeconds":\(String(format: "%.4f", s.decodeSeconds))}
                    """)
            }
            print("{\"near\":\(near),\"modalities\":[\(modObjs.joined(separator: ","))]}")
        }
    }
}
