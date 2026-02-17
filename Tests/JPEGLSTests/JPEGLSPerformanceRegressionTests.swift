import Testing
import Foundation
@testable import JPEGLS

/// Performance regression tests with baseline metrics.
///
/// These tests establish baseline performance metrics for JLSwift encoding and decoding
/// operations and verify that performance does not regress beyond a configurable threshold.
///
/// **Baseline Metrics**: Established on x86_64 Linux (CI environment). Baselines are
/// intentionally generous (10x multiplier) to avoid flaky failures due to environment
/// variance while still catching catastrophic regressions.
///
/// **Automated Detection**: Tests fail if measured time exceeds the baseline threshold,
/// providing an early warning for performance regressions introduced by code changes.
///
/// **Note**: Precise regression detection (e.g., 1.2x threshold) requires dedicated
/// benchmark hardware with consistent performance characteristics. The current thresholds
/// are designed for CI environments where timing can vary significantly.
@Suite("Performance Regression Tests")
struct JPEGLSPerformanceRegressionTests {

    // MARK: - Regression Threshold Configuration

    /// Multiplier for regression detection threshold.
    ///
    /// A value of 10.0 means the test fails only if performance is 10x slower than
    /// the baseline. This generous threshold avoids flaky failures in CI while still
    /// catching catastrophic regressions (e.g., O(n²) → O(n³) algorithmic changes).
    private static let regressionThresholdMultiplier: Double = 10.0

    /// Number of iterations for regression benchmarks
    private static let iterations = 5

    // MARK: - Baseline Metrics (x86_64 Linux CI)
    //
    // These baselines were established from benchmark runs on x86_64 Linux.
    // They represent typical encoding/decoding times and throughput values.
    // Update these values when the CI environment changes significantly.

    /// Baseline: 256x256 8-bit grayscale encode (ms)
    private static let baselineEncode256x256_8bit: Double = 50.0

    /// Baseline: 512x512 8-bit grayscale encode (ms)
    private static let baselineEncode512x512_8bit: Double = 200.0

    /// Baseline: 512x512 16-bit grayscale encode (ms)
    private static let baselineEncode512x512_16bit: Double = 250.0

    /// Baseline: 512x512 8-bit RGB sample-interleaved encode (ms)
    private static let baselineEncode512x512_RGB: Double = 600.0

    /// Baseline: 256x256 8-bit grayscale decode (ms)
    private static let baselineDecode256x256_8bit: Double = 50.0

    /// Baseline: 512x512 8-bit grayscale decode (ms)
    private static let baselineDecode512x512_8bit: Double = 200.0

    /// Baseline: 512x512 8-bit RGB sample-interleaved decode (ms)
    private static let baselineDecode512x512_RGB: Double = 600.0

    /// Baseline: round-trip encode+decode 256x256 8-bit (ms)
    private static let baselineRoundTrip256x256_8bit: Double = 100.0

    /// Minimum throughput baseline: 512x512 8-bit encode (Mpixels/s)
    /// Conservative for CI environments with variable CPU availability.
    private static let baselineThroughputMpixels: Double = 0.1

    // MARK: - Test Image Generation

    /// Generate a synthetic medical-like test image
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

    // MARK: - Encoding Regression Tests

    @Test("Regression: Encode 256x256 8-bit grayscale within baseline threshold")
    func regressionEncode256x256Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 256, height: 256, bitsPerSample: 8, componentCount: 1
        )

        let averageMs = try measureEncodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let threshold = Self.baselineEncode256x256_8bit * Self.regressionThresholdMultiplier
        print("Regression: Encode 256x256 8-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineEncode256x256_8bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Encoding 256x256 8-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    @Test("Regression: Encode 512x512 8-bit grayscale within baseline threshold")
    func regressionEncode512x512Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let averageMs = try measureEncodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let threshold = Self.baselineEncode512x512_8bit * Self.regressionThresholdMultiplier
        print("Regression: Encode 512x512 8-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineEncode512x512_8bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Encoding 512x512 8-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    @Test("Regression: Encode 512x512 16-bit grayscale within baseline threshold")
    func regressionEncode512x512Grayscale16bit() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 16, componentCount: 1
        )

        let averageMs = try measureEncodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let threshold = Self.baselineEncode512x512_16bit * Self.regressionThresholdMultiplier
        print("Regression: Encode 512x512 16-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineEncode512x512_16bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Encoding 512x512 16-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    @Test("Regression: Encode 512x512 8-bit RGB sample-interleaved within baseline threshold")
    func regressionEncode512x512RGB() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 3
        )

        let averageMs = try measureEncodingAverage(
            imageData: imageData, near: 0,
            interleaveMode: .sample, iterations: Self.iterations
        )

        let threshold = Self.baselineEncode512x512_RGB * Self.regressionThresholdMultiplier
        print("Regression: Encode 512x512 8-bit RGB sample-interleaved")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineEncode512x512_RGB)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Encoding 512x512 RGB took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    // MARK: - Decoding Regression Tests

    @Test("Regression: Decode 256x256 8-bit grayscale within baseline threshold")
    func regressionDecode256x256Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 256, height: 256, bitsPerSample: 8, componentCount: 1
        )

        let averageMs = try measureDecodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let threshold = Self.baselineDecode256x256_8bit * Self.regressionThresholdMultiplier
        print("Regression: Decode 256x256 8-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineDecode256x256_8bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Decoding 256x256 8-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    @Test("Regression: Decode 512x512 8-bit grayscale within baseline threshold")
    func regressionDecode512x512Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let averageMs = try measureDecodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let threshold = Self.baselineDecode512x512_8bit * Self.regressionThresholdMultiplier
        print("Regression: Decode 512x512 8-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineDecode512x512_8bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Decoding 512x512 8-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    @Test("Regression: Decode 512x512 8-bit RGB sample-interleaved within baseline threshold")
    func regressionDecode512x512RGB() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 3
        )

        let averageMs = try measureDecodingAverage(
            imageData: imageData, near: 0,
            interleaveMode: .sample, iterations: Self.iterations
        )

        let threshold = Self.baselineDecode512x512_RGB * Self.regressionThresholdMultiplier
        print("Regression: Decode 512x512 8-bit RGB sample-interleaved")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineDecode512x512_RGB)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Decoding 512x512 RGB took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    // MARK: - Round-Trip Regression Tests

    @Test("Regression: Round-trip 256x256 8-bit grayscale within baseline threshold")
    func regressionRoundTrip256x256Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 256, height: 256, bitsPerSample: 8, componentCount: 1
        )

        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let decoder = JPEGLSDecoder()

        // Warm-up
        let encoded = try encoder.encode(imageData, configuration: configuration)
        _ = try decoder.decode(encoded)

        var times: [Double] = []
        for _ in 0..<Self.iterations {
            let start = DispatchTime.now()
            let encoded = try encoder.encode(imageData, configuration: configuration)
            _ = try decoder.decode(encoded)
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }

        let averageMs = times.reduce(0, +) / Double(times.count)
        let threshold = Self.baselineRoundTrip256x256_8bit * Self.regressionThresholdMultiplier
        print("Regression: Round-trip 256x256 8-bit grayscale")
        print("  Average:   \(String(format: "%.2f", averageMs)) ms")
        print("  Baseline:  \(String(format: "%.2f", Self.baselineRoundTrip256x256_8bit)) ms")
        print("  Threshold: \(String(format: "%.2f", threshold)) ms (\(Self.regressionThresholdMultiplier)x)")

        #expect(
            averageMs < threshold,
            "Round-trip 256x256 8-bit took \(String(format: "%.2f", averageMs)) ms, exceeding \(String(format: "%.2f", threshold)) ms threshold"
        )
    }

    // MARK: - Throughput Regression Tests

    @Test("Regression: Encoding throughput above minimum baseline")
    func regressionEncodingThroughput() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let averageMs = try measureEncodingAverage(
            imageData: imageData, near: 0, iterations: Self.iterations
        )

        let totalPixels = Double(512 * 512)
        let throughputMpixels = totalPixels / (averageMs / 1000) / 1_000_000

        print("Regression: Encoding throughput")
        print("  Throughput: \(String(format: "%.2f", throughputMpixels)) Mpixels/s")
        print("  Baseline:   \(String(format: "%.2f", Self.baselineThroughputMpixels)) Mpixels/s")

        #expect(
            throughputMpixels > Self.baselineThroughputMpixels,
            "Encoding throughput \(String(format: "%.2f", throughputMpixels)) Mpixels/s below \(String(format: "%.2f", Self.baselineThroughputMpixels)) Mpixels/s baseline"
        )
    }

    // MARK: - Compression Ratio Regression Tests

    @Test("Regression: Compression ratio for medical-like content")
    func regressionCompressionRatio() throws {
        let imageData = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let encoder = JPEGLSEncoder()
        let configuration = try JPEGLSEncoder.Configuration(near: 0, interleaveMode: .none)
        let encoded = try encoder.encode(imageData, configuration: configuration)

        let uncompressedSize = Double(512 * 512)
        let compressedSize = Double(encoded.count)
        let compressionRatio = uncompressedSize / compressedSize

        print("Regression: Compression ratio for medical-like content")
        print("  Uncompressed: \(Int(uncompressedSize)) bytes")
        print("  Compressed:   \(encoded.count) bytes")
        print("  Ratio:        \(String(format: "%.2f", compressionRatio)):1")

        // JPEG-LS lossless compression ratio varies with content entropy.
        // For synthetic test content with small noise patterns, verify the encoder
        // produces output (ratio > 0) and doesn't have catastrophic expansion (> 0.5:1).
        #expect(
            compressionRatio > 0.5,
            "Compression ratio \(String(format: "%.2f", compressionRatio)):1 below minimum 0.5:1 (catastrophic expansion)"
        )
    }

    // MARK: - Scaling Regression Tests

    @Test("Regression: Encoding time scales linearly with image size")
    func regressionEncodingScaling() throws {
        let smallImage = try generateTestImage(
            width: 256, height: 256, bitsPerSample: 8, componentCount: 1
        )
        let largeImage = try generateTestImage(
            width: 512, height: 512, bitsPerSample: 8, componentCount: 1
        )

        let smallAvgMs = try measureEncodingAverage(
            imageData: smallImage, near: 0, iterations: Self.iterations
        )
        let largeAvgMs = try measureEncodingAverage(
            imageData: largeImage, near: 0, iterations: Self.iterations
        )

        // 512x512 is 4x the pixels of 256x256
        // With linear scaling, expect roughly 4x the time
        // Allow up to 8x to account for cache effects and measurement noise
        let scalingFactor = largeAvgMs / smallAvgMs
        let pixelRatio = Double(512 * 512) / Double(256 * 256) // 4.0

        print("Regression: Encoding scaling")
        print("  256x256 average: \(String(format: "%.2f", smallAvgMs)) ms")
        print("  512x512 average: \(String(format: "%.2f", largeAvgMs)) ms")
        print("  Scaling factor:  \(String(format: "%.2f", scalingFactor))x (expected ~\(String(format: "%.1f", pixelRatio))x)")

        #expect(
            scalingFactor < pixelRatio * 2.0,
            "Scaling factor \(String(format: "%.2f", scalingFactor))x exceeds \(String(format: "%.1f", pixelRatio * 2.0))x (super-linear regression detected)"
        )
    }

    // MARK: - Measurement Helpers

    /// Measure average encoding time across iterations
    private func measureEncodingAverage(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none,
        iterations: Int
    ) throws -> Double {
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

        return times.reduce(0, +) / Double(times.count)
    }

    /// Measure average decoding time across iterations
    private func measureDecodingAverage(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode = .none,
        iterations: Int
    ) throws -> Double {
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

        return times.reduce(0, +) / Double(times.count)
    }
}
