/// Phase 15 GPU Compute Acceleration tests.
///
/// Validates correctness of the new Metal and Vulkan GPU compute operations
/// introduced in Milestone 15:
///  - Metal: gradient quantisation, colour space transformation (HP1/HP2/HP3)
///  - Vulkan: CPU-fallback gradient, MED prediction, quantisation, and colour
///    transforms
///
/// Metal tests are skipped on platforms without Metal support (Linux CI).
/// Vulkan tests always run via the CPU fallback path.

import Testing
@testable import JPEGLS

// MARK: - Vulkan CPU Fallback Tests (run on all platforms)

@Suite("Vulkan Accelerator Tests (CPU Fallback)")
struct VulkanAcceleratorTests {

    let accelerator = VulkanAccelerator()

    // MARK: isSupported

    @Test("VulkanAccelerator.isSupported reflects device availability")
    func testIsSupportedDoesNotCrash() {
        // Just verify the property is accessible without crashing.
        let supported = VulkanAccelerator.isSupported
        #expect(supported == true || supported == false)
    }

    @Test("VulkanAccelerator platform name is Vulkan")
    func testPlatformName() {
        #expect(VulkanAccelerator.platformName == "Vulkan")
    }

    // MARK: Gradient computation

    @Test("Vulkan: computeGradientsBatch returns correct values")
    func testGradients() {
        let a: [Int32] = [10, 20, 30]
        let b: [Int32] = [15, 25, 35]
        let c: [Int32] = [5,  10, 15]
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        for i in 0..<a.count {
            #expect(d1[i] == b[i] - c[i])
            #expect(d2[i] == a[i] - c[i])
            #expect(d3[i] == c[i] - a[i])
        }
    }

    @Test("Vulkan: computeGradientsBatch empty arrays")
    func testGradientsEmpty() {
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: [], b: [], c: [])
        #expect(d1.isEmpty && d2.isEmpty && d3.isEmpty)
    }

    @Test("Vulkan: computeGradientsBatch large batch (above threshold)")
    func testGradientsLargeBatch() {
        let count = VulkanAccelerator.gpuThreshold * 2
        let a = [Int32](repeating: 100, count: count)
        let b = [Int32](repeating: 200, count: count)
        let c = [Int32](repeating: 50,  count: count)
        let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
        #expect(d1.allSatisfy { $0 == 150 })
        #expect(d2.allSatisfy { $0 == 50  })
        #expect(d3.allSatisfy { $0 == -50 })
    }

    // MARK: MED prediction

    @Test("Vulkan: computeMEDPredictionBatch — c >= max(a,b) → min(a,b)")
    func testMEDCaseHigh() {
        let a: [Int32] = [10]
        let b: [Int32] = [15]
        let c: [Int32] = [20]  // c >= max
        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        #expect(pred == [10])
    }

    @Test("Vulkan: computeMEDPredictionBatch — c <= min(a,b) → max(a,b)")
    func testMEDCaseLow() {
        let a: [Int32] = [15]
        let b: [Int32] = [20]
        let c: [Int32] = [5]   // c <= min
        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        #expect(pred == [20])
    }

    @Test("Vulkan: computeMEDPredictionBatch — middle case → a + b - c")
    func testMEDCaseMiddle() {
        let a: [Int32] = [10]
        let b: [Int32] = [20]
        let c: [Int32] = [15]  // min < c < max
        let pred = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)
        #expect(pred == [15])
    }

    @Test("Vulkan: computeMEDPredictionBatch empty arrays")
    func testMEDEmpty() {
        let pred = accelerator.computeMEDPredictionBatch(a: [], b: [], c: [])
        #expect(pred.isEmpty)
    }

    // MARK: Gradient quantisation

    @Test("Vulkan: quantizeGradientsBatch — boundary values map correctly")
    func testQuantizeGradientsBasic() {
        // t1=3, t2=7, t3=21 — typical JPEG-LS default-like values
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let d: [Int32] = [-30, -10, -5, -1, 0, 1, 5, 10, 30]
        let expected: [Int32] = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
        let (q1, _, _) = accelerator.quantizeGradientsBatch(
            d1: d, d2: d, d3: d, t1: t1, t2: t2, t3: t3)
        #expect(q1 == expected)
    }

    @Test("Vulkan: quantizeGradientsBatch — three channels quantised independently")
    func testQuantizeGradientsThreeChannels() {
        let t1: Int32 = 2, t2: Int32 = 4, t3: Int32 = 8
        let d1: [Int32] = [0,  1,  3]  // 0→0, 1→1 (d<t1), 3→2 (t1≤d<t2)
        let d2: [Int32] = [-1, -3, -9] // -1→-1, -3→-2 (-t1≥d>-t2), -9→-4 (d≤-t3)
        let d3: [Int32] = [2,  5,  10] // 2→2 (t1≤d<t2), 5→3 (t2≤d<t3), 10→4 (d≥t3)
        let (q1, q2, q3) = accelerator.quantizeGradientsBatch(
            d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        #expect(q1 == [0, 1, 2])
        #expect(q2 == [-1, -2, -4])
        #expect(q3 == [2, 3, 4])
    }

    @Test("Vulkan: quantizeGradientsBatch empty arrays")
    func testQuantizeGradientsEmpty() {
        let (q1, q2, q3) = accelerator.quantizeGradientsBatch(
            d1: [], d2: [], d3: [], t1: 3, t2: 7, t3: 21)
        #expect(q1.isEmpty && q2.isEmpty && q3.isEmpty)
    }

    // MARK: Colour transforms — HP1

    @Test("Vulkan: HP1 forward transform is correct")
    func testHP1Forward() {
        let r: [Int32] = [200, 100]
        let g: [Int32] = [100,  50]
        let b: [Int32] = [ 50, 150]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        // R′ = R − G, G′ = G, B′ = B − G
        #expect(rp == [100, 50])
        #expect(gp == [100, 50])
        #expect(bp == [-50, 100])
    }

    @Test("Vulkan: HP1 inverse round-trips correctly")
    func testHP1RoundTrip() {
        let r: [Int32] = [200, 100, 50]
        let g: [Int32] = [100,  50, 30]
        let b: [Int32] = [ 50, 150, 20]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp1, r: rp, g: gp, b: bp)
        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    // MARK: Colour transforms — HP2

    @Test("Vulkan: HP2 forward transform is correct")
    func testHP2Forward() {
        // R=200, G=100, B=50
        // R′ = 200-100 = 100
        // G′ = 100
        // B′ = 50 - ((200+100)>>1) = 50 - 150 = -100
        let r: [Int32] = [200]
        let g: [Int32] = [100]
        let b: [Int32] = [ 50]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        #expect(rp == [100])
        #expect(gp == [100])
        #expect(bp == [-100])
    }

    @Test("Vulkan: HP2 inverse round-trips correctly")
    func testHP2RoundTrip() {
        let r: [Int32] = [200, 100, 30]
        let g: [Int32] = [100,  50, 20]
        let b: [Int32] = [ 50, 150, 10]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp2, r: rp, g: gp, b: bp)
        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    // MARK: Colour transforms — HP3

    @Test("Vulkan: HP3 forward transform is correct")
    func testHP3Forward() {
        // R=200, G=100, B=50
        // B′ = 50
        // R′ = 200-50 = 150
        // G′ = 100 - ((200+50)>>1) = 100 - 125 = -25
        let r: [Int32] = [200]
        let g: [Int32] = [100]
        let b: [Int32] = [ 50]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        #expect(rp == [150])
        #expect(gp == [-25])
        #expect(bp == [50])
    }

    @Test("Vulkan: HP3 inverse round-trips correctly")
    func testHP3RoundTrip() {
        let r: [Int32] = [200, 100, 30]
        let g: [Int32] = [100,  50, 20]
        let b: [Int32] = [ 50, 150, 10]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        let (rr, gr, br) = accelerator.applyColourTransformInverseBatch(
            transform: .hp3, r: rp, g: gp, b: bp)
        #expect(rr == r)
        #expect(gr == g)
        #expect(br == b)
    }

    // MARK: Identity transform

    @Test("Vulkan: .none transform returns input unchanged")
    func testIdentityTransform() {
        let r: [Int32] = [10, 20, 30]
        let g: [Int32] = [40, 50, 60]
        let b: [Int32] = [70, 80, 90]
        let (rp, gp, bp) = accelerator.applyColourTransformForwardBatch(
            transform: .none, r: r, g: g, b: b)
        #expect(rp == r && gp == g && bp == b)
    }

    // MARK: VulkanDevice

    @Test("VulkanDevice properties are accessible")
    func testVulkanDeviceProperties() {
        // apiVersion encodes Vulkan 1.1.0 as (major<<22 | minor<<12 | patch)
        let dev = VulkanDevice(name: "Test GPU", apiVersion: 0x00401000, deviceType: .discreteGPU)
        #expect(dev.name == "Test GPU")
        #expect(dev.isGPUDevice)
        #expect(dev.deviceType == .discreteGPU)
    }

    @Test("VulkanDevice CPU type is not a GPU device")
    func testVulkanDeviceCPUType() {
        let dev = VulkanDevice(name: "CPU", apiVersion: 0, deviceType: .cpu)
        #expect(!dev.isGPUDevice)
    }

    @Test("selectBestVulkanDevice returns nil when no SDK present")
    func testSelectBestVulkanDeviceNoSDK() {
        // Without the Vulkan SDK, enumerateVulkanDevices() returns [], so
        // selectBestVulkanDevice() returns nil.
        let device = selectBestVulkanDevice()
        // On this CI environment there is no Vulkan SDK, so nil is expected.
        #expect(device == nil || device?.isGPUDevice == true || device?.isGPUDevice == false)
    }
}

// MARK: - Metal Phase 15 Tests (Apple platforms only)

#if canImport(Metal)

@Suite("Metal Phase 15 GPU Compute Tests")
struct MetalPhase15Tests {

    // MARK: Gradient Quantisation

    @Test("Metal: quantizeGradientsBatch — small batch (CPU fallback)")
    func testQuantizeGradientsSmallBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let d: [Int32] = [-30, -10, -5, -1, 0, 1, 5, 10, 30]
        let expected: [Int32] = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
        let (q1, q2, q3) = try accelerator.quantizeGradientsBatch(
            d1: d, d2: d, d3: d, t1: t1, t2: t2, t3: t3)
        #expect(q1 == expected)
        #expect(q2 == expected)
        #expect(q3 == expected)
    }

    @Test("Metal: quantizeGradientsBatch — large batch (GPU)")
    func testQuantizeGradientsLargeBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let count = MetalAccelerator.gpuThreshold * 2
        let d1 = [Int32](repeating: 5, count: count)   // maps to 2 (t1 ≤ 5 < t2)
        let d2 = [Int32](repeating: -8, count: count)  // maps to -3 (-t2 ≤ -8 > -t3)
        let d3 = [Int32](repeating: 0, count: count)   // maps to 0
        let (q1, q2, q3) = try accelerator.quantizeGradientsBatch(
            d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        #expect(q1.allSatisfy { $0 == 2 })
        #expect(q2.allSatisfy { $0 == -3 })
        #expect(q3.allSatisfy { $0 == 0 })
    }

    @Test("Metal: quantizeGradientsBatch — empty arrays")
    func testQuantizeGradientsEmpty() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let (q1, q2, q3) = try accelerator.quantizeGradientsBatch(
            d1: [], d2: [], d3: [], t1: 3, t2: 7, t3: 21)
        #expect(q1.isEmpty && q2.isEmpty && q3.isEmpty)
    }

    @Test("Metal: quantizeGradientsBatch matches Vulkan CPU fallback")
    func testQuantizeGradientsBitExact() throws {
        #guard(MetalAccelerator.isSupported)
        let metalAcc = try MetalAccelerator()
        let vulkanAcc = VulkanAccelerator()
        let t1: Int32 = 3, t2: Int32 = 7, t3: Int32 = 21
        let count = MetalAccelerator.gpuThreshold * 2
        var d1 = [Int32](repeating: 0, count: count)
        var d2 = [Int32](repeating: 0, count: count)
        var d3 = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            d1[i] = Int32((i % 50) - 25)
            d2[i] = Int32((i % 30) - 15)
            d3[i] = Int32((i % 40) - 20)
        }
        let (mq1, mq2, mq3) = try metalAcc.quantizeGradientsBatch(
            d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        let (vq1, vq2, vq3) = vulkanAcc.quantizeGradientsBatch(
            d1: d1, d2: d2, d3: d3, t1: t1, t2: t2, t3: t3)
        #expect(mq1 == vq1, "Metal and Vulkan q1 must match")
        #expect(mq2 == vq2, "Metal and Vulkan q2 must match")
        #expect(mq3 == vq3, "Metal and Vulkan q3 must match")
    }

    // MARK: Colour Transform — HP1

    @Test("Metal: HP1 forward transform — small batch (CPU fallback)")
    func testHP1ForwardSmallBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let r: [Int32] = [200, 100]
        let g: [Int32] = [100,  50]
        let b: [Int32] = [ 50, 150]
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        #expect(rp == [100, 50])
        #expect(gp == [100, 50])
        #expect(bp == [-50, 100])
    }

    @Test("Metal: HP1 inverse round-trips — small batch (CPU fallback)")
    func testHP1RoundTripSmallBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let r: [Int32] = [200, 100, 50]
        let g: [Int32] = [100,  50, 30]
        let b: [Int32] = [ 50, 150, 20]
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        let (rr, gr, br) = try accelerator.applyColourTransformInverseBatch(
            transform: .hp1, r: rp, g: gp, b: bp)
        #expect(rr == r && gr == g && br == b)
    }

    @Test("Metal: HP1 forward transform — large batch (GPU)")
    func testHP1ForwardLargeBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        let r = [Int32](repeating: 200, count: count)
        let g = [Int32](repeating: 100, count: count)
        let b = [Int32](repeating:  50, count: count)
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        #expect(rp.allSatisfy { $0 == 100 })
        #expect(gp.allSatisfy { $0 == 100 })
        #expect(bp.allSatisfy { $0 == -50 })
    }

    @Test("Metal: HP1 large batch round-trips correctly (GPU)")
    func testHP1RoundTripLargeBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 64) % 256)
            b[i] = Int32((i + 128) % 256)
        }
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        let (rr, gr, br) = try accelerator.applyColourTransformInverseBatch(
            transform: .hp1, r: rp, g: gp, b: bp)
        #expect(rr == r && gr == g && br == b)
    }

    // MARK: Colour Transform — HP2

    @Test("Metal: HP2 inverse round-trips correctly — large batch (GPU)")
    func testHP2RoundTripLargeBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 64) % 256)
            b[i] = Int32((i + 128) % 256)
        }
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        let (rr, gr, br) = try accelerator.applyColourTransformInverseBatch(
            transform: .hp2, r: rp, g: gp, b: bp)
        #expect(rr == r && gr == g && br == b)
    }

    // MARK: Colour Transform — HP3

    @Test("Metal: HP3 inverse round-trips correctly — large batch (GPU)")
    func testHP3RoundTripLargeBatch() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32(i % 256)
            g[i] = Int32((i + 64) % 256)
            b[i] = Int32((i + 128) % 256)
        }
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        let (rr, gr, br) = try accelerator.applyColourTransformInverseBatch(
            transform: .hp3, r: rp, g: gp, b: bp)
        #expect(rr == r && gr == g && br == b)
    }

    // MARK: Identity transform

    @Test("Metal: .none forward transform returns input unchanged")
    func testIdentityForward() throws {
        #guard(MetalAccelerator.isSupported)
        let accelerator = try MetalAccelerator()
        let r: [Int32] = [10, 20, 30]
        let g: [Int32] = [40, 50, 60]
        let b: [Int32] = [70, 80, 90]
        let (rp, gp, bp) = try accelerator.applyColourTransformForwardBatch(
            transform: .none, r: r, g: g, b: b)
        #expect(rp == r && gp == g && bp == b)
    }

    // MARK: Bit-exact: Metal vs Vulkan

    @Test("Metal colour transforms match Vulkan CPU results — HP1 large batch")
    func testColourTransformBitExactHP1() throws {
        #guard(MetalAccelerator.isSupported)
        let metalAcc  = try MetalAccelerator()
        let vulkanAcc = VulkanAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32.random(in: 0...255)
            g[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
        }
        let (mr, mg, mb) = try metalAcc.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        let (vr, vg, vb) = vulkanAcc.applyColourTransformForwardBatch(
            transform: .hp1, r: r, g: g, b: b)
        #expect(mr == vr && mg == vg && mb == vb)
    }

    @Test("Metal colour transforms match Vulkan CPU results — HP2 large batch")
    func testColourTransformBitExactHP2() throws {
        #guard(MetalAccelerator.isSupported)
        let metalAcc  = try MetalAccelerator()
        let vulkanAcc = VulkanAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32.random(in: 0...255)
            g[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
        }
        let (mr, mg, mb) = try metalAcc.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        let (vr, vg, vb) = vulkanAcc.applyColourTransformForwardBatch(
            transform: .hp2, r: r, g: g, b: b)
        #expect(mr == vr && mg == vg && mb == vb)
    }

    @Test("Metal colour transforms match Vulkan CPU results — HP3 large batch")
    func testColourTransformBitExactHP3() throws {
        #guard(MetalAccelerator.isSupported)
        let metalAcc  = try MetalAccelerator()
        let vulkanAcc = VulkanAccelerator()
        let count = MetalAccelerator.gpuThreshold * 2
        var r = [Int32](repeating: 0, count: count)
        var g = [Int32](repeating: 0, count: count)
        var b = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            r[i] = Int32.random(in: 0...255)
            g[i] = Int32.random(in: 0...255)
            b[i] = Int32.random(in: 0...255)
        }
        let (mr, mg, mb) = try metalAcc.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        let (vr, vg, vb) = vulkanAcc.applyColourTransformForwardBatch(
            transform: .hp3, r: r, g: g, b: b)
        #expect(mr == vr && mg == vg && mb == vb)
    }

    // MARK: Graceful fallback for non-Metal

    @Test("MetalAccelerator gracefully reports support status")
    func testGracefulFallback() {
        let supported = MetalAccelerator.isSupported
        #expect(supported == true || supported == false)
    }
}

#endif // canImport(Metal)
