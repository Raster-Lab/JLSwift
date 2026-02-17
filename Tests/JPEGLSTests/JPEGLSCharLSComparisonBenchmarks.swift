import Testing
import Foundation
@testable import JPEGLS

/// Benchmark suite for comparing JLSwift performance against CharLS reference implementation.
///
/// These benchmarks measure encoding speed, decoding speed, and memory usage relative to
/// CharLS (https://github.com/team-charls/charls). CharLS is the de-facto reference
/// C++ implementation of JPEG-LS and serves as the performance target.
///
/// **Status**: Deferred — requires CharLS C library integration via Swift Package Manager
/// C-interop target or system library wrapper. All tests are disabled until CharLS is
/// available as a build dependency.
///
/// **Integration Plan**:
/// 1. Add CharLS as a C system library or bundled source target
/// 2. Create Swift wrapper for `JpegLsEncode` / `JpegLsDecode` C APIs
/// 3. Enable these tests to run head-to-head comparisons
/// 4. Integrate into CI for continuous performance tracking
@Suite("CharLS Comparison Benchmarks")
struct JPEGLSCharLSComparisonBenchmarks {

    // MARK: - Benchmark Configuration

    /// Number of iterations for comparison benchmarks
    private static let benchmarkIterations = 10

    /// Image sizes to benchmark (width x height)
    private static let benchmarkSizes: [(width: Int, height: Int)] = [
        (256, 256),
        (512, 512),
        (1024, 1024),
    ]

    // MARK: - Test Image Generation

    /// Generate a synthetic medical-like test image for benchmarking
    private func generateTestImage(
        width: Int,
        height: Int,
        bitsPerSample: Int,
        componentCount: Int
    ) throws -> MultiComponentImageData {
        let maxValue = (1 << bitsPerSample) - 1

        var componentPixels: [[[Int]]] = []

        for component in 0..<componentCount {
            var pixels: [[Int]] = []
            pixels.reserveCapacity(height)

            for row in 0..<height {
                var rowPixels: [Int] = []
                rowPixels.reserveCapacity(width)

                for col in 0..<width {
                    // Simulated medical image with noise
                    let baseValue = maxValue / 2
                    let noise = ((row * 31 + col * 37 + component * 41) % 20) - 10
                    let value = max(0, min(maxValue, baseValue + noise))
                    rowPixels.append(value)
                }
                pixels.append(rowPixels)
            }
            componentPixels.append(pixels)
        }

        if componentCount == 1 {
            return try MultiComponentImageData.grayscale(
                pixels: componentPixels[0],
                bitsPerSample: bitsPerSample
            )
        } else {
            return try MultiComponentImageData.rgb(
                redPixels: componentPixels[0],
                greenPixels: componentPixels[1],
                bluePixels: componentPixels[2],
                bitsPerSample: bitsPerSample
            )
        }
    }

    // MARK: - Encoding Speed vs CharLS

    @Test("CharLS comparison: Encode 512x512 8-bit grayscale",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkEncodeVsCharLS512x512Grayscale() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        // JLSwift encoding
        let jlswiftTimes = try measureJLSwiftEncoding(
            imageData: imageData, near: 0, iterations: Self.benchmarkIterations
        )

        // CharLS encoding (stub — not yet integrated)
        // let charlsTimes = try measureCharLSEncoding(
        //     imageData: imageData, near: 0, iterations: Self.benchmarkIterations
        // )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift encode 512x512 8-bit: \(String(format: "%.2f", avgJLSwift)) ms")
        // print("CharLS  encode 512x512 8-bit: \(String(format: "%.2f", avgCharLS)) ms")
        // print("Ratio (JLSwift/CharLS): \(String(format: "%.2f", avgJLSwift / avgCharLS))x")

        #expect(avgJLSwift > 0)
    }

    @Test("CharLS comparison: Encode 512x512 8-bit RGB sample-interleaved",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkEncodeVsCharLS512x512RGB() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 3
        )

        let jlswiftTimes = try measureJLSwiftEncoding(
            imageData: imageData, near: 0,
            interleaveMode: .sample, iterations: Self.benchmarkIterations
        )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift encode 512x512 RGB: \(String(format: "%.2f", avgJLSwift)) ms")

        #expect(avgJLSwift > 0)
    }

    @Test("CharLS comparison: Encode 512x512 8-bit near-lossless NEAR=3",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkEncodeVsCharLS512x512NearLossless() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let jlswiftTimes = try measureJLSwiftEncoding(
            imageData: imageData, near: 3, iterations: Self.benchmarkIterations
        )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift encode 512x512 NEAR=3: \(String(format: "%.2f", avgJLSwift)) ms")

        #expect(avgJLSwift > 0)
    }

    // MARK: - Decoding Speed vs CharLS

    @Test("CharLS comparison: Decode 512x512 8-bit grayscale",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkDecodeVsCharLS512x512Grayscale() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let jlswiftTimes = try measureJLSwiftDecoding(
            imageData: imageData, near: 0, iterations: Self.benchmarkIterations
        )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift decode 512x512 8-bit: \(String(format: "%.2f", avgJLSwift)) ms")

        #expect(avgJLSwift > 0)
    }

    @Test("CharLS comparison: Decode 512x512 8-bit RGB sample-interleaved",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkDecodeVsCharLS512x512RGB() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 3
        )

        let jlswiftTimes = try measureJLSwiftDecoding(
            imageData: imageData, near: 0,
            interleaveMode: .sample, iterations: Self.benchmarkIterations
        )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift decode 512x512 RGB: \(String(format: "%.2f", avgJLSwift)) ms")

        #expect(avgJLSwift > 0)
    }

    @Test("CharLS comparison: Decode 512x512 8-bit near-lossless NEAR=3",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkDecodeVsCharLS512x512NearLossless() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let jlswiftTimes = try measureJLSwiftDecoding(
            imageData: imageData, near: 3, iterations: Self.benchmarkIterations
        )

        let avgJLSwift = jlswiftTimes.reduce(0, +) / Double(jlswiftTimes.count)
        print("JLSwift decode 512x512 NEAR=3: \(String(format: "%.2f", avgJLSwift)) ms")

        #expect(avgJLSwift > 0)
    }

    // MARK: - Memory Usage vs CharLS

    @Test("CharLS comparison: Memory usage encoding 1024x1024 8-bit grayscale",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkMemoryUsageVsCharLSEncoding() throws {
        let imageData = try generateTestImage(
            width: 1024, height: 1024, bitsPerSample: 8, componentCount: 1
        )

        let jlswiftMemory = try measureJLSwiftEncodingMemory(imageData: imageData, near: 0)

        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let imageDataSizeMB = Double(width * height) / (1024 * 1024)

        print("Memory usage encoding 1024x1024 8-bit grayscale:")
        print("  Image size:         \(String(format: "%.2f", imageDataSizeMB)) MB")
        print("  JLSwift memory:     \(String(format: "%.2f", jlswiftMemory)) MB")
        print("  JLSwift ratio:      \(String(format: "%.2f", jlswiftMemory / imageDataSizeMB))x")
        // print("  CharLS memory:      \(String(format: "%.2f", charlsMemory)) MB")
        // print("  CharLS ratio:       \(String(format: "%.2f", charlsMemory / imageDataSizeMB))x")

        #expect(jlswiftMemory >= 0)
    }

    @Test("CharLS comparison: Memory usage decoding 1024x1024 8-bit grayscale",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkMemoryUsageVsCharLSDecoding() throws {
        let imageData = try generateTestImage(
            width: 1024, height: 1024, bitsPerSample: 8, componentCount: 1
        )

        let jlswiftMemory = try measureJLSwiftDecodingMemory(imageData: imageData, near: 0)

        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let imageDataSizeMB = Double(width * height) / (1024 * 1024)

        print("Memory usage decoding 1024x1024 8-bit grayscale:")
        print("  Image size:         \(String(format: "%.2f", imageDataSizeMB)) MB")
        print("  JLSwift memory:     \(String(format: "%.2f", jlswiftMemory)) MB")
        // print("  CharLS memory:      \(String(format: "%.2f", charlsMemory)) MB")

        #expect(jlswiftMemory >= 0)
    }

    @Test("CharLS comparison: Memory usage encoding 1024x1024 RGB",
          .disabled("Deferred — requires CharLS C library integration"))
    func benchmarkMemoryUsageVsCharLSEncodingRGB() throws {
        let imageData = try generateTestImage(
            width: 1024, height: 1024, bitsPerSample: 8, componentCount: 3
        )

        let jlswiftMemory = try measureJLSwiftEncodingMemory(
            imageData: imageData, near: 0, interleaveMode: .sample
        )

        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let imageDataSizeMB = Double(width * height * 3) / (1024 * 1024)

        print("Memory usage encoding 1024x1024 RGB:")
        print("  Image size:         \(String(format: "%.2f", imageDataSizeMB)) MB")
        print("  JLSwift memory:     \(String(format: "%.2f", jlswiftMemory)) MB")

        #expect(jlswiftMemory >= 0)
    }

    // MARK: - JLSwift Measurement Helpers

    /// Measure JLSwift encoding times across iterations
    private func measureJLSwiftEncoding(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none,
        iterations: Int
    ) throws -> [Double] {
        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(
            near: near, interleaveMode: interleaveMode
        )

        // Warm-up
        _ = try encoder.encode(imageData, configuration: configuration)

        var times: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            _ = try encoder.encode(imageData, configuration: configuration)
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        return times
    }

    /// Measure JLSwift decoding times across iterations
    private func measureJLSwiftDecoding(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none,
        iterations: Int
    ) throws -> [Double] {
        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(
            near: near, interleaveMode: interleaveMode
        )
        let encodedData = try encoder.encode(imageData, configuration: configuration)

        let decoder = JPEGLSDecoder()

        // Warm-up
        _ = try decoder.decode(encodedData)

        var times: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            _ = try decoder.decode(encodedData)
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        return times
    }

    /// Measure JLSwift encoding memory usage (approximate)
    private func measureJLSwiftEncodingMemory(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none
    ) throws -> Double {
        let initialMemory = getCurrentMemoryUsage()

        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(
            near: near, interleaveMode: interleaveMode
        )
        _ = try encoder.encode(imageData, configuration: configuration)

        let peakMemory = getCurrentMemoryUsage()
        return Double(peakMemory - initialMemory) / (1024 * 1024)
    }

    /// Measure JLSwift decoding memory usage (approximate)
    private func measureJLSwiftDecodingMemory(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none
    ) throws -> Double {
        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(
            near: near, interleaveMode: interleaveMode
        )
        let encodedData = try encoder.encode(imageData, configuration: configuration)

        let initialMemory = getCurrentMemoryUsage()

        let decoder = JPEGLSDecoder()
        _ = try decoder.decode(encodedData)

        let peakMemory = getCurrentMemoryUsage()
        return Double(peakMemory - initialMemory) / (1024 * 1024)
    }

    /// Get current memory usage in bytes (approximate)
    private func getCurrentMemoryUsage() -> UInt64 {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard kerr == KERN_SUCCESS else {
            return 0
        }

        return info.resident_size
        #else
        return 0
        #endif
    }
}
