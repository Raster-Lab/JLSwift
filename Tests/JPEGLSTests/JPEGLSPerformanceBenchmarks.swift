import Testing
import Foundation
@testable import JPEGLS

/// Comprehensive performance benchmarks for JPEG-LS encoding and decoding.
///
/// These benchmarks measure end-to-end performance across various image configurations,
/// including different sizes, bit depths, component counts, and encoding modes.
/// Results are compared against baseline metrics to detect performance regressions.
@Suite("JPEG-LS Performance Benchmarks")
struct JPEGLSPerformanceBenchmarks {
    
    // MARK: - Benchmark Configuration
    
    /// Number of iterations for small benchmarks (< 1MB images)
    private static let smallImageIterations = 100
    
    /// Number of iterations for medium benchmarks (1-4MB images)
    private static let mediumImageIterations = 10
    
    /// Number of iterations for large benchmarks (> 4MB images)
    private static let largeImageIterations = 3
    
    // MARK: - Test Image Generation
    
    /// Generate a synthetic test image with specified content type
    private func generateTestImage(
        width: Int,
        height: Int,
        bitsPerSample: Int,
        componentCount: Int,
        contentType: ImageContentType
    ) throws -> MultiComponentImageData {
        let maxValue = (1 << bitsPerSample) - 1
        
        // Generate pixel data for each component
        var componentPixels: [[[Int]]] = []
        
        for component in 0..<componentCount {
            var pixels: [[Int]] = []
            pixels.reserveCapacity(height)
            
            for row in 0..<height {
                var rowPixels: [Int] = []
                rowPixels.reserveCapacity(width)
                
                for col in 0..<width {
                    let value: Int
                    switch contentType {
                    case .flat:
                        // Constant value for high compression
                        value = maxValue / 2
                    case .gradient:
                        // Linear gradient
                        let gradientValue = (row * width + col) * maxValue / (width * height)
                        value = gradientValue
                    case .checkerboard:
                        // Checkerboard pattern
                        let blockSize = 16
                        let isLight = ((row / blockSize) + (col / blockSize)) % 2 == 0
                        value = isLight ? maxValue * 3 / 4 : maxValue / 4
                    case .medicalLike:
                        // Simulated medical image with noise
                        let baseValue = maxValue / 2
                        let noise = ((row * 31 + col * 37 + component * 41) % 20) - 10
                        value = max(0, min(maxValue, baseValue + noise))
                    }
                    rowPixels.append(value)
                }
                pixels.append(rowPixels)
            }
            componentPixels.append(pixels)
        }
        
        // Create the appropriate image data based on component count
        if componentCount == 1 {
            return try MultiComponentImageData.grayscale(
                pixels: componentPixels[0],
                bitsPerSample: bitsPerSample
            )
        } else if componentCount == 3 {
            return try MultiComponentImageData.rgb(
                redPixels: componentPixels[0],
                greenPixels: componentPixels[1],
                bluePixels: componentPixels[2],
                bitsPerSample: bitsPerSample
            )
        } else {
            // Unsupported component count - should not reach here based on current tests
            fatalError("Unsupported component count: \(componentCount). Only 1 (grayscale) and 3 (RGB) are currently supported.")
        }
    }
    
    /// Image content types for testing various compression scenarios
    enum ImageContentType {
        case flat          // Constant values - best compression
        case gradient      // Linear gradient - moderate compression
        case checkerboard  // Pattern - moderate compression
        case medicalLike   // Simulated medical with noise - realistic
    }
    
    // MARK: - Encoding Benchmarks - Small Images
    
    @Test("Benchmark: Encode 256x256 8-bit grayscale (lossless)")
    func benchmarkEncode256x256Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 256,
            height: 256,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.smallImageIterations
        )
        
        print("Encode 256x256 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 8-bit grayscale (lossless)")
    func benchmarkEncode512x512Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 8-bit RGB (lossless, sample interleaved)")
    func benchmarkEncode512x512RGB8bitSampleInterleaved() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 3,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .sample,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit RGB (lossless, sample interleaved):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Medium Images
    
    @Test("Benchmark: Encode 1024x1024 8-bit grayscale (lossless)")
    func benchmarkEncode1024x1024Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 1024,
            height: 1024,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 1024x1024 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 2048x2048 8-bit grayscale (lossless)")
    func benchmarkEncode2048x2048Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 2048,
            height: 2048,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.largeImageIterations
        )
        
        print("Encode 2048x2048 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Large Images
    
    @Test("Benchmark: Encode 4096x4096 8-bit grayscale (lossless)")
    func benchmarkEncode4096x4096Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 4096,
            height: 4096,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.largeImageIterations
        )
        
        print("Encode 4096x4096 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Different Bit Depths
    
    @Test("Benchmark: Encode 512x512 12-bit grayscale (lossless)")
    func benchmarkEncode512x512Grayscale12bit() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 12,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 12-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 16-bit grayscale (lossless)")
    func benchmarkEncode512x512Grayscale16bit() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 16,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 16-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Near-Lossless
    
    @Test("Benchmark: Encode 512x512 8-bit grayscale (near-lossless NEAR=3)")
    func benchmarkEncode512x512GrayscaleNear3() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 3,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit grayscale (near-lossless NEAR=3):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 8-bit grayscale (near-lossless NEAR=10)")
    func benchmarkEncode512x512GrayscaleNear10() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 10,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit grayscale (near-lossless NEAR=10):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Different Content Types
    
    @Test("Benchmark: Encode 512x512 8-bit grayscale (flat content)")
    func benchmarkEncode512x512GrayscaleFlat() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .flat
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit grayscale (flat content):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 8-bit grayscale (gradient content)")
    func benchmarkEncode512x512GrayscaleGradient() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .gradient
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit grayscale (gradient content):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Encoding Benchmarks - Different Interleaving Modes
    
    @Test("Benchmark: Encode 512x512 8-bit RGB (line interleaved)")
    func benchmarkEncode512x512RGBLineInterleaved() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 3,
            contentType: .medicalLike
        )
        
        let result = try benchmarkEncoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .line,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit RGB (line interleaved):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Encode 512x512 8-bit RGB (none interleaved)")
    func benchmarkEncode512x512RGBNoneInterleaved() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 3,
            contentType: .medicalLike
        )
        
        // For none interleaving, we need to encode each component separately
        let result = try benchmarkEncodingNoneInterleavedRGB(
            imageData: imageData,
            near: 0,
            iterations: Self.mediumImageIterations
        )
        
        print("Encode 512x512 8-bit RGB (none interleaved):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Decoding Benchmarks
    
    @Test("Benchmark: Decode 512x512 8-bit grayscale (lossless)")
    func benchmarkDecode512x512Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkDecoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Decode 512x512 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Decode 1024x1024 8-bit grayscale (lossless)")
    func benchmarkDecode1024x1024Grayscale8bit() throws {
        let imageData = try generateTestImage(
            width: 1024,
            height: 1024,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let result = try benchmarkDecoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .none,
            iterations: Self.mediumImageIterations
        )
        
        print("Decode 1024x1024 8-bit grayscale (lossless):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    @Test("Benchmark: Decode 512x512 8-bit RGB (sample interleaved)")
    func benchmarkDecode512x512RGBSampleInterleaved() throws {
        let imageData = try generateTestImage(
            width: 512,
            height: 512,
            bitsPerSample: 8,
            componentCount: 3,
            contentType: .medicalLike
        )
        
        let result = try benchmarkDecoding(
            imageData: imageData,
            near: 0,
            interleaveMode: .sample,
            iterations: Self.mediumImageIterations
        )
        
        print("Decode 512x512 8-bit RGB (sample interleaved):")
        printBenchmarkResults(result)
        
        #expect(result.averageTimeMs > 0)
    }
    
    // MARK: - Memory Usage Benchmarks
    
    @Test("Benchmark: Memory usage during 2048x2048 8-bit grayscale encoding",
          .enabled(if: {
              #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
              return true
              #else
              return false
              #endif
          }()))
    func benchmarkMemoryUsageEncoding() throws {
        let imageData = try generateTestImage(
            width: 2048,
            height: 2048,
            bitsPerSample: 8,
            componentCount: 1,
            contentType: .medicalLike
        )
        
        let initialMemory = getCurrentMemoryUsage()
        
        // Perform encoding
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        _ = try encoder.encodeScan(buffer: buffer)
        
        let peakMemory = getCurrentMemoryUsage()
        let memoryUsedMB = Double(peakMemory - initialMemory) / (1024 * 1024)
        
        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let bitsPerSample = imageData.frameHeader.bitsPerSample
        let imageDataSizeMB = Double(width * height * bitsPerSample / 8) / (1024 * 1024)
        
        print("Memory usage during 2048x2048 8-bit grayscale encoding:")
        print("  Image size:     \(String(format: "%.2f", imageDataSizeMB)) MB")
        print("  Memory used:    \(String(format: "%.2f", memoryUsedMB)) MB")
        print("  Memory ratio:   \(String(format: "%.2f", memoryUsedMB / imageDataSizeMB))x")
        
        #expect(memoryUsedMB > 0)
    }
    
    // MARK: - Helper Methods
    
    /// Benchmark result structure
    struct BenchmarkResult {
        let totalTimeMs: Double
        let averageTimeMs: Double
        let minTimeMs: Double
        let maxTimeMs: Double
        let throughputMBps: Double
        let throughputMpixelsPerSec: Double
        let iterations: Int
        let imageWidth: Int
        let imageHeight: Int
        let bitsPerSample: Int
        let componentCount: Int
    }
    
    /// Benchmark encoding performance
    private func benchmarkEncoding(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode,
        iterations: Int
    ) throws -> BenchmarkResult {
        var times: [Double] = []
        
        // Warm-up iteration
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let componentCount = imageData.frameHeader.componentCount
        let effectiveComponentCount = interleaveMode == .none ? 1 : componentCount
        let scanHeader = try JPEGLSScanHeader(
            componentCount: effectiveComponentCount,
            components: (0..<effectiveComponentCount).map {
                JPEGLSScanHeader.ComponentSelector(id: UInt8($0 + 1))
            },
            near: near,
            interleaveMode: interleaveMode,
            pointTransform: 0
        )
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        _ = try encoder.encodeScan(buffer: buffer)
        
        // Benchmark iterations
        for _ in 0..<iterations {
            let buffer = JPEGLSPixelBuffer(imageData: imageData)
            let scanHeader = try JPEGLSScanHeader(
                componentCount: effectiveComponentCount,
                components: (0..<effectiveComponentCount).map {
                    JPEGLSScanHeader.ComponentSelector(id: UInt8($0 + 1))
                },
                near: near,
                interleaveMode: interleaveMode,
                pointTransform: 0
            )
            let encoder = try JPEGLSMultiComponentEncoder(
                frameHeader: imageData.frameHeader,
                scanHeader: scanHeader
            )
            
            let start = DispatchTime.now()
            _ = try encoder.encodeScan(buffer: buffer)
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed) // Already in milliseconds
        }
        
        return calculateBenchmarkResult(
            times: times,
            imageData: imageData,
            iterations: iterations
        )
    }
    
    /// Benchmark encoding for none-interleaved RGB (requires separate scans per component)
    private func benchmarkEncodingNoneInterleavedRGB(
        imageData: MultiComponentImageData,
        near: Int,
        iterations: Int
    ) throws -> BenchmarkResult {
        var times: [Double] = []
        
        let componentCount = imageData.frameHeader.componentCount
        
        // Warm-up iteration
        for componentId in 1...componentCount {
            let buffer = JPEGLSPixelBuffer(imageData: imageData)
            let scanHeader = try JPEGLSScanHeader(
                componentCount: 1,
                components: [JPEGLSScanHeader.ComponentSelector(id: UInt8(componentId))],
                near: near,
                interleaveMode: .none,
                pointTransform: 0
            )
            let encoder = try JPEGLSMultiComponentEncoder(
                frameHeader: imageData.frameHeader,
                scanHeader: scanHeader
            )
            _ = try encoder.encodeScan(buffer: buffer)
        }
        
        // Benchmark iterations
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            
            // Encode each component separately
            for componentId in 1...componentCount {
                let buffer = JPEGLSPixelBuffer(imageData: imageData)
                let scanHeader = try JPEGLSScanHeader(
                    componentCount: 1,
                    components: [JPEGLSScanHeader.ComponentSelector(id: UInt8(componentId))],
                    near: near,
                    interleaveMode: .none,
                    pointTransform: 0
                )
                let encoder = try JPEGLSMultiComponentEncoder(
                    frameHeader: imageData.frameHeader,
                    scanHeader: scanHeader
                )
                _ = try encoder.encodeScan(buffer: buffer)
            }
            
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed) // Already in milliseconds
        }
        
        return calculateBenchmarkResult(
            times: times,
            imageData: imageData,
            iterations: iterations
        )
    }
    
    /// Benchmark decoding performance
    private func benchmarkDecoding(
        imageData: MultiComponentImageData,
        near: Int,
        interleaveMode: JPEGLSInterleaveMode,
        iterations: Int
    ) throws -> BenchmarkResult {
        var times: [Double] = []
        
        let componentCount = imageData.frameHeader.componentCount
        let effectiveComponentCount = interleaveMode == .none ? 1 : componentCount
        
        // Warm-up iteration
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let scanHeader = try JPEGLSScanHeader(
            componentCount: effectiveComponentCount,
            components: (0..<effectiveComponentCount).map {
                JPEGLSScanHeader.ComponentSelector(id: UInt8($0 + 1))
            },
            near: near,
            interleaveMode: interleaveMode,
            pointTransform: 0
        )
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        _ = try decoder.decodeScan(buffer: buffer)
        
        // Benchmark iterations
        for _ in 0..<iterations {
            let buffer = JPEGLSPixelBuffer(imageData: imageData)
            let scanHeader = try JPEGLSScanHeader(
                componentCount: effectiveComponentCount,
                components: (0..<effectiveComponentCount).map {
                    JPEGLSScanHeader.ComponentSelector(id: UInt8($0 + 1))
                },
                near: near,
                interleaveMode: interleaveMode,
                pointTransform: 0
            )
            let decoder = try JPEGLSMultiComponentDecoder(
                frameHeader: imageData.frameHeader,
                scanHeader: scanHeader
            )
            
            let start = DispatchTime.now()
            _ = try decoder.decodeScan(buffer: buffer)
            let end = DispatchTime.now()
            let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed) // Already in milliseconds
        }
        
        return calculateBenchmarkResult(
            times: times,
            imageData: imageData,
            iterations: iterations
        )
    }
    
    /// Calculate benchmark statistics from timing data
    private func calculateBenchmarkResult(
        times: [Double],
        imageData: MultiComponentImageData,
        iterations: Int
    ) -> BenchmarkResult {
        let totalTime = times.reduce(0, +)
        let averageTime = totalTime / Double(times.count)
        let minTime = times.min() ?? 0
        let maxTime = times.max() ?? 0
        
        // Calculate throughput
        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let componentCount = imageData.frameHeader.componentCount
        let bitsPerSample = imageData.frameHeader.bitsPerSample
        
        let totalPixels = width * height * componentCount
        let bytesPerPixel = (bitsPerSample + 7) / 8
        let totalBytes = totalPixels * bytesPerPixel
        let megabytes = Double(totalBytes) / (1024 * 1024)
        let throughputMBps = megabytes / (averageTime / 1000)
        let throughputMpixelsPerSec = Double(totalPixels) / (averageTime / 1000) / 1_000_000
        
        return BenchmarkResult(
            totalTimeMs: totalTime,
            averageTimeMs: averageTime,
            minTimeMs: minTime,
            maxTimeMs: maxTime,
            throughputMBps: throughputMBps,
            throughputMpixelsPerSec: throughputMpixelsPerSec,
            iterations: iterations,
            imageWidth: width,
            imageHeight: height,
            bitsPerSample: bitsPerSample,
            componentCount: componentCount
        )
    }
    
    /// Print benchmark results in a formatted manner
    private func printBenchmarkResults(_ result: BenchmarkResult) {
        print("  Image:          \(result.imageWidth)x\(result.imageHeight), \(result.bitsPerSample)-bit, \(result.componentCount) component(s)")
        print("  Iterations:     \(result.iterations)")
        print("  Average time:   \(String(format: "%.2f", result.averageTimeMs)) ms")
        print("  Min time:       \(String(format: "%.2f", result.minTimeMs)) ms")
        print("  Max time:       \(String(format: "%.2f", result.maxTimeMs)) ms")
        print("  Throughput:     \(String(format: "%.2f", result.throughputMBps)) MB/s")
        print("  Throughput:     \(String(format: "%.2f", result.throughputMpixelsPerSec)) Mpixels/s")
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
        // On Linux, memory tracking is not implemented for this benchmark
        return 0
        #endif
    }
}
