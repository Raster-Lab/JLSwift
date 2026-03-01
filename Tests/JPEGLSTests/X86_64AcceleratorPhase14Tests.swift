/// Tests for the Phase 14.1 x86-64 SSE/AVX enhancements.
///
/// These tests cover the Golomb-Rice parameter computation, run-length
/// detection, and byte stuffing detection added to X86_64Accelerator as
/// part of Milestone 14 Phase 14.1.
///
/// All tests are compiled and run only on x86-64 architectures where
/// the X86_64Accelerator is available.

#if arch(x86_64)

import Testing
import Foundation
@testable import JPEGLS

@Suite("X86_64 Accelerator Phase 14.1 Tests")
struct X86_64AcceleratorPhase14Tests {

    // MARK: - Golomb-Rice Parameter Computation

    @Test("Golomb-Rice parameter is zero when a is zero")
    func golombRiceParamZeroA() {
        let acc = X86_64Accelerator()
        #expect(acc.computeGolombRiceParameter(a: 0, n: 64) == 0)
    }

    @Test("Golomb-Rice parameter is zero when n is zero")
    func golombRiceParamZeroN() {
        let acc = X86_64Accelerator()
        #expect(acc.computeGolombRiceParameter(a: 100, n: 0) == 0)
    }

    @Test("Golomb-Rice parameter is zero when a <= n (small error accumulator)")
    func golombRiceParamSmallA() {
        let acc = X86_64Accelerator()
        // When a <= n, k should be 0 (threshold n*1 >= a)
        #expect(acc.computeGolombRiceParameter(a: 10, n: 64) == 0)
    }

    @Test("Golomb-Rice parameter increases with larger a relative to n")
    func golombRiceParamIncreases() {
        let acc = X86_64Accelerator()
        let k1 = acc.computeGolombRiceParameter(a: 64, n: 64)   // a/n = 1
        let k2 = acc.computeGolombRiceParameter(a: 128, n: 64)  // a/n = 2
        let k3 = acc.computeGolombRiceParameter(a: 512, n: 64)  // a/n = 8
        // k should be non-decreasing as a grows
        #expect(k1 <= k2)
        #expect(k2 <= k3)
    }

    @Test("Golomb-Rice parameter satisfies 2^k * n >= a")
    func golombRiceParamSatisfiesCondition() {
        let acc = X86_64Accelerator()
        let n = 64
        for a in [64, 128, 256, 512, 1024, 2048] {
            let k = acc.computeGolombRiceParameter(a: a, n: n)
            // Primary condition: 2^k * n >= a
            #expect((n << k) >= a, "k=\(k) for a=\(a) n=\(n): 2^k*n should be >= a")
            // Minimality: if k > 0, then 2^(k-1) * n < a
            if k > 0 {
                #expect((n << (k - 1)) < a, "k=\(k) should be minimal for a=\(a) n=\(n)")
            }
        }
    }

    @Test("Golomb-Rice parameter is bounded within [0, 31]")
    func golombRiceParamBounded() {
        let acc = X86_64Accelerator()
        let k = acc.computeGolombRiceParameter(a: Int.max / 2, n: 1)
        #expect(k >= 0)
        #expect(k <= 31)
    }

    // MARK: - Run-Length Detection

    @Test("Run-length detection returns 0 for empty slice")
    func runLengthEmpty() {
        let acc = X86_64Accelerator()
        #expect(acc.detectRunLength(in: [], startIndex: 0, runValue: 0, maxLength: 100) == 0)
    }

    @Test("Run-length detection with maxLength 0 returns 0")
    func runLengthMaxLengthZero() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [10, 10, 10]
        #expect(acc.detectRunLength(in: pixels, startIndex: 0, runValue: 10, maxLength: 0) == 0)
    }

    @Test("Run-length detection counts full run of equal pixels")
    func runLengthFullRun() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [5, 5, 5, 5, 5]
        let length = acc.detectRunLength(in: pixels, startIndex: 0, runValue: 5, maxLength: 100)
        #expect(length == 5)
    }

    @Test("Run-length detection stops at first mismatch")
    func runLengthStopsAtMismatch() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [10, 10, 10, 20, 10]
        let length = acc.detectRunLength(in: pixels, startIndex: 0, runValue: 10, maxLength: 100)
        #expect(length == 3)
    }

    @Test("Run-length detection respects maxLength")
    func runLengthRespectMaxLength() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [7, 7, 7, 7, 7, 7, 7, 7]
        let length = acc.detectRunLength(in: pixels, startIndex: 0, runValue: 7, maxLength: 4)
        #expect(length == 4)
    }

    @Test("Run-length detection can start from non-zero index")
    func runLengthStartIndex() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [1, 2, 3, 3, 3, 3, 4]
        let length = acc.detectRunLength(in: pixels, startIndex: 2, runValue: 3, maxLength: 100)
        #expect(length == 4)
    }

    @Test("Run-length detection with single matching element")
    func runLengthSingleMatch() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [99]
        #expect(acc.detectRunLength(in: pixels, startIndex: 0, runValue: 99, maxLength: 100) == 1)
    }

    @Test("Run-length detection returns 0 when first element mismatches")
    func runLengthFirstMismatch() {
        let acc = X86_64Accelerator()
        let pixels: [Int32] = [5, 5, 5]
        #expect(acc.detectRunLength(in: pixels, startIndex: 0, runValue: 9, maxLength: 100) == 0)
    }

    @Test("Run-length detection across SIMD vector boundary")
    func runLengthAcrossVectorBoundary() {
        let acc = X86_64Accelerator()
        // 8 matching + 2 more = run of 10, crossing the 8-element SIMD boundary
        let pixels = [Int32](repeating: 42, count: 10) + [Int32](repeating: 0, count: 5)
        let length = acc.detectRunLength(in: pixels, startIndex: 0, runValue: 42, maxLength: 100)
        #expect(length == 10)
    }

    // MARK: - Byte Stuffing Detection

    @Test("Byte stuffing detection returns empty for non-0xFF data")
    func byteStuffingNone() {
        let acc = X86_64Accelerator()
        let data: [UInt8] = [0x00, 0x01, 0x7F, 0xFE, 0x80, 0x55]
        #expect(acc.detectByteStuffingPositions(in: data).isEmpty)
    }

    @Test("Byte stuffing detection finds single 0xFF")
    func byteStuffingSingle() {
        let acc = X86_64Accelerator()
        let data: [UInt8] = [0x00, 0xFF, 0x01]
        let positions = acc.detectByteStuffingPositions(in: data)
        #expect(positions == [1])
    }

    @Test("Byte stuffing detection finds multiple 0xFF bytes")
    func byteStuffingMultiple() {
        let acc = X86_64Accelerator()
        let data: [UInt8] = [0xFF, 0x00, 0xFF, 0x7F, 0xFF]
        let positions = acc.detectByteStuffingPositions(in: data)
        #expect(positions == [0, 2, 4])
    }

    @Test("Byte stuffing detection handles empty data")
    func byteStuffingEmpty() {
        let acc = X86_64Accelerator()
        #expect(acc.detectByteStuffingPositions(in: []).isEmpty)
    }

    @Test("Byte stuffing detection handles all-0xFF data")
    func byteStuffingAllFF() {
        let acc = X86_64Accelerator()
        let data = [UInt8](repeating: 0xFF, count: 16)
        let positions = acc.detectByteStuffingPositions(in: data)
        #expect(positions == Array(0..<16))
    }

    @Test("Byte stuffing detection crosses SIMD boundary")
    func byteStuffingCrossesVectorBoundary() {
        let acc = X86_64Accelerator()
        // 0xFF at index 7 (last of first SIMD chunk) and 8 (first of second)
        var data = [UInt8](repeating: 0x00, count: 16)
        data[7] = 0xFF
        data[8] = 0xFF
        let positions = acc.detectByteStuffingPositions(in: data)
        #expect(positions == [7, 8])
    }

    @Test("Byte stuffing detection in tail (count not multiple of 8)")
    func byteStuffingInTail() {
        let acc = X86_64Accelerator()
        // 9 bytes: 0xFF is at index 8 (the tail byte after the first SIMD chunk)
        var data = [UInt8](repeating: 0x00, count: 9)
        data[8] = 0xFF
        let positions = acc.detectByteStuffingPositions(in: data)
        #expect(positions == [8])
    }
}

#endif // arch(x86_64)
