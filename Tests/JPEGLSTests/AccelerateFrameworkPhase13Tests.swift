/// Tests for Phase 13.2 Accelerate Framework deep-integration additions.
///
/// These tests cover the vDSP-accelerated error computation, context-state
/// update helpers, vImage format conversion utilities, and the HP1/HP2/HP3
/// colour space transform batch methods added to AccelerateFrameworkAccelerator
/// as part of Milestone 13 Phase 13.2.

#if canImport(Accelerate)

import Testing
import Foundation
@testable import JPEGLS

@Suite("Accelerate Framework Phase 13.2 Tests")
struct AccelerateFrameworkPhase13Tests {

    // MARK: - Prediction Error Computation

    @Test("computePredictionErrors returns correct signed differences")
    func predictionErrors() {
        let acc = AccelerateFrameworkAccelerator()
        let actual    = [10, 20, 30, 40]
        let predicted = [12, 18, 35, 38]
        let errors = acc.computePredictionErrors(actual: actual, predicted: predicted)
        #expect(errors == [-2, 2, -5, 2])
    }

    @Test("computePredictionErrors with identical arrays returns zeros")
    func predictionErrorsZero() {
        let acc = AccelerateFrameworkAccelerator()
        let values = [5, 10, 15]
        #expect(acc.computePredictionErrors(actual: values, predicted: values) == [0, 0, 0])
    }

    @Test("computePredictionErrors with empty arrays returns empty")
    func predictionErrorsEmpty() {
        let acc = AccelerateFrameworkAccelerator()
        #expect(acc.computePredictionErrors(actual: [], predicted: []).isEmpty)
    }

    @Test("computeAbsolutePredictionErrors returns non-negative values")
    func absolutePredictionErrors() {
        let acc = AccelerateFrameworkAccelerator()
        let actual    = [10, 20, 30]
        let predicted = [15, 15, 35]
        let absErrors = acc.computeAbsolutePredictionErrors(actual: actual, predicted: predicted)
        #expect(absErrors == [5, 5, 5])
    }

    @Test("computeAbsolutePredictionErrors with empty arrays returns empty")
    func absolutePredictionErrorsEmpty() {
        let acc = AccelerateFrameworkAccelerator()
        #expect(acc.computeAbsolutePredictionErrors(actual: [], predicted: []).isEmpty)
    }

    @Test("computeAbsolutePredictionErrors with zero errors returns zeros")
    func absolutePredictionErrorsZero() {
        let acc = AccelerateFrameworkAccelerator()
        let values = [100, 200, 50]
        #expect(acc.computeAbsolutePredictionErrors(actual: values, predicted: values) == [0, 0, 0])
    }

    // MARK: - Context State Updates

    @Test("updateAccumulatorA accumulates absolute errors correctly")
    func updateAccumulatorA() {
        let acc = AccelerateFrameworkAccelerator()
        var aArray = [Int](repeating: 0, count: 4)
        let errors          = [3, -2, 4, -1]
        let contextIndices  = [0, 1, 2, 3]
        acc.updateAccumulatorA(aArray: &aArray, errors: errors, contextIndices: contextIndices)
        #expect(aArray == [3, 2, 4, 1])
    }

    @Test("updateAccumulatorA accumulates into same context")
    func updateAccumulatorASameContext() {
        let acc = AccelerateFrameworkAccelerator()
        var aArray = [Int](repeating: 0, count: 2)
        let errors         = [-5, 3, -7]
        let contextIndices = [0, 0, 0]
        acc.updateAccumulatorA(aArray: &aArray, errors: errors, contextIndices: contextIndices)
        // All three errors go into context 0: |−5|+|3|+|−7| = 15
        #expect(aArray[0] == 15)
        #expect(aArray[1] == 0)
    }

    @Test("updateAccumulatorA with empty errors leaves array unchanged")
    func updateAccumulatorAEmpty() {
        let acc = AccelerateFrameworkAccelerator()
        var aArray = [10, 20, 30]
        acc.updateAccumulatorA(aArray: &aArray, errors: [], contextIndices: [])
        #expect(aArray == [10, 20, 30])
    }

    @Test("updateAccumulatorB accumulates signed errors correctly")
    func updateAccumulatorB() {
        let acc = AccelerateFrameworkAccelerator()
        var bArray = [Int](repeating: 0, count: 4)
        let errors         = [3, -2, 4, -1]
        let contextIndices = [0, 1, 2, 3]
        acc.updateAccumulatorB(bArray: &bArray, errors: errors, contextIndices: contextIndices)
        #expect(bArray == [3, -2, 4, -1])
    }

    @Test("updateAccumulatorB accumulates signed errors into same context")
    func updateAccumulatorBSameContext() {
        let acc = AccelerateFrameworkAccelerator()
        var bArray = [Int](repeating: 0, count: 2)
        let errors         = [5, -3, 2]
        let contextIndices = [1, 1, 1]
        acc.updateAccumulatorB(bArray: &bArray, errors: errors, contextIndices: contextIndices)
        #expect(bArray[0] == 0)
        #expect(bArray[1] == 4)  // 5 − 3 + 2
    }

    // MARK: - vImage Format Conversions

    @Test("planesToInterleaved with single component returns same array")
    func planesSingleComponent() {
        let acc = AccelerateFrameworkAccelerator()
        let plane: [UInt8] = [1, 2, 3, 4, 5, 6]
        let result = acc.planesToInterleaved(planes: [plane], width: 3, height: 2)
        #expect(result == plane)
    }

    @Test("planesToInterleaved with two components interleaves correctly")
    func planesTwoComponents() {
        let acc = AccelerateFrameworkAccelerator()
        // 2 pixels × 2 components
        let p0: [UInt8] = [10, 20]  // component 0
        let p1: [UInt8] = [11, 21]  // component 1
        let result = acc.planesToInterleaved(planes: [p0, p1], width: 2, height: 1)
        // Expected interleaving: [p0[0], p1[0], p0[1], p1[1]]
        #expect(result == [10, 11, 20, 21])
    }

    @Test("planesToInterleaved with three components interleaves correctly")
    func planesThreeComponents() {
        let acc = AccelerateFrameworkAccelerator()
        let r: [UInt8] = [255, 128]
        let g: [UInt8] = [0,   64]
        let b: [UInt8] = [100, 200]
        let result = acc.planesToInterleaved(planes: [r, g, b], width: 2, height: 1)
        #expect(result == [255, 0, 100, 128, 64, 200])
    }

    @Test("planesToInterleaved with empty planes returns empty")
    func planesEmpty() {
        let acc = AccelerateFrameworkAccelerator()
        #expect(acc.planesToInterleaved(planes: [], width: 0, height: 0).isEmpty)
    }

    @Test("interleavedToPlanes with single component returns same data")
    func interleavedSingleComponent() {
        let acc = AccelerateFrameworkAccelerator()
        let data: [UInt8] = [1, 2, 3, 4]
        let planes = acc.interleavedToPlanes(interleaved: data, componentCount: 1, width: 4, height: 1)
        #expect(planes.count == 1)
        #expect(planes[0] == data)
    }

    @Test("interleavedToPlanes with three components splits correctly")
    func interleavedThreeComponents() {
        let acc = AccelerateFrameworkAccelerator()
        // 2 pixels × 3 components
        let data: [UInt8] = [255, 0, 100, 128, 64, 200]
        let planes = acc.interleavedToPlanes(interleaved: data, componentCount: 3, width: 2, height: 1)
        #expect(planes.count == 3)
        #expect(planes[0] == [255, 128])  // R
        #expect(planes[1] == [0,   64])   // G
        #expect(planes[2] == [100, 200])  // B
    }

    @Test("planesToInterleaved and interleavedToPlanes are inverses")
    func planesRoundTrip() {
        let acc = AccelerateFrameworkAccelerator()
        let r: [UInt8] = [10, 20, 30, 40]
        let g: [UInt8] = [50, 60, 70, 80]
        let b: [UInt8] = [90, 100, 110, 120]
        let original = [r, g, b]
        
        let interleaved = acc.planesToInterleaved(planes: original, width: 4, height: 1)
        let recovered   = acc.interleavedToPlanes(interleaved: interleaved, componentCount: 3, width: 4, height: 1)
        
        #expect(recovered[0] == r)
        #expect(recovered[1] == g)
        #expect(recovered[2] == b)
    }

    // MARK: - HP1 Colour Transform

    @Test("applyHP1Forward transforms correctly")
    func hp1Forward() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP1Forward(r: r, g: g, b: b)
        // R′ = R−G = 100, G′ = 100 (unchanged), B′ = B−G = −50
        #expect(rP == [100])
        #expect(gP == [100])
        #expect(bP == [-50])
    }

    @Test("applyHP1Inverse recovers original values")
    func hp1Inverse() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200, 128, 0], g = [100, 64, 255], b = [50, 200, 100]
        let (rP, gP, bP) = acc.applyHP1Forward(r: r, g: g, b: b)
        let (rRec, gRec, bRec) = acc.applyHP1Inverse(rPrime: rP, gPrime: gP, bPrime: bP)
        #expect(rRec == r)
        #expect(gRec == g)
        #expect(bRec == b)
    }

    @Test("applyHP1Forward and Inverse are consistent with scalar transform for batch")
    func hp1BatchConsistency() {
        let acc = AccelerateFrameworkAccelerator()
        
        let r = [10, 50, 200, 0]
        let g = [20, 60, 100, 255]
        let b = [30, 70, 150, 128]
        
        let (rP, gP, bP) = acc.applyHP1Forward(r: r, g: g, b: b)
        
        // Verify each pixel against the scalar formula
        for i in 0..<r.count {
            #expect(rP[i] == r[i] - g[i], "HP1 R′ mismatch at index \(i)")
            #expect(gP[i] == g[i],         "HP1 G′ should be unchanged at index \(i)")
            #expect(bP[i] == b[i] - g[i], "HP1 B′ mismatch at index \(i)")
        }
    }

    @Test("applyHP1 with empty arrays returns empty")
    func hp1Empty() {
        let acc = AccelerateFrameworkAccelerator()
        let (rP, gP, bP) = acc.applyHP1Forward(r: [], g: [], b: [])
        #expect(rP.isEmpty && gP.isEmpty && bP.isEmpty)
    }

    // MARK: - HP2 Colour Transform

    @Test("applyHP2Forward transforms correctly")
    func hp2Forward() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP2Forward(r: r, g: g, b: b)
        // R′ = 200−100 = 100
        // G′ = 100 (unchanged)
        // B′ = 50 − ((200+100) >> 1) = 50 − 150 = −100
        #expect(rP == [100])
        #expect(gP == [100])
        #expect(bP == [-100])
    }

    @Test("applyHP2Inverse recovers original values")
    func hp2Inverse() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200, 100, 50], g = [100, 200, 150], b = [50, 75, 200]
        let (rP, gP, bP) = acc.applyHP2Forward(r: r, g: g, b: b)
        let (rRec, gRec, bRec) = acc.applyHP2Inverse(rPrime: rP, gPrime: gP, bPrime: bP)
        #expect(rRec == r)
        #expect(gRec == g)
        #expect(bRec == b)
    }

    @Test("applyHP2Forward and Inverse are consistent with scalar transform")
    func hp2BatchConsistency() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [10, 200, 0,   128]
        let g = [20, 100, 255, 64]
        let b = [30, 150, 100, 32]
        
        let (rP, gP, bP) = acc.applyHP2Forward(r: r, g: g, b: b)
        
        for i in 0..<r.count {
            #expect(rP[i] == r[i] - g[i],                          "HP2 R′ mismatch at index \(i)")
            #expect(gP[i] == g[i],                                  "HP2 G′ should be unchanged at index \(i)")
            #expect(bP[i] == b[i] - ((r[i] + g[i]) >> 1),         "HP2 B′ mismatch at index \(i)")
        }
    }

    @Test("applyHP2 with empty arrays returns empty")
    func hp2Empty() {
        let acc = AccelerateFrameworkAccelerator()
        let (rP, gP, bP) = acc.applyHP2Forward(r: [], g: [], b: [])
        #expect(rP.isEmpty && gP.isEmpty && bP.isEmpty)
    }

    // MARK: - HP3 Colour Transform

    @Test("applyHP3Forward transforms correctly")
    func hp3Forward() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP3Forward(r: r, g: g, b: b)
        // R′ = R−B = 150
        // G′ = G − ((R+B) >> 1) = 100 − 125 = −25
        // B′ = B = 50 (unchanged)
        #expect(rP == [150])
        #expect(gP == [-25])
        #expect(bP == [50])
    }

    @Test("applyHP3Inverse recovers original values")
    func hp3Inverse() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200, 100, 50], g = [100, 200, 150], b = [50, 75, 200]
        let (rP, gP, bP) = acc.applyHP3Forward(r: r, g: g, b: b)
        let (rRec, gRec, bRec) = acc.applyHP3Inverse(rPrime: rP, gPrime: gP, bPrime: bP)
        #expect(rRec == r)
        #expect(gRec == g)
        #expect(bRec == b)
    }

    @Test("applyHP3Forward and Inverse are consistent with scalar transform")
    func hp3BatchConsistency() {
        let acc = AccelerateFrameworkAccelerator()
        let r = [10, 200, 0,   128]
        let g = [20, 100, 255, 64]
        let b = [30, 150, 100, 32]
        
        let (rP, gP, bP) = acc.applyHP3Forward(r: r, g: g, b: b)
        
        for i in 0..<r.count {
            #expect(rP[i] == r[i] - b[i],                          "HP3 R′ mismatch at index \(i)")
            #expect(gP[i] == g[i] - ((r[i] + b[i]) >> 1),         "HP3 G′ mismatch at index \(i)")
            #expect(bP[i] == b[i],                                  "HP3 B′ should be unchanged at index \(i)")
        }
    }

    @Test("applyHP3 with empty arrays returns empty")
    func hp3Empty() {
        let acc = AccelerateFrameworkAccelerator()
        let (rP, gP, bP) = acc.applyHP3Forward(r: [], g: [], b: [])
        #expect(rP.isEmpty && gP.isEmpty && bP.isEmpty)
    }

    // MARK: - Consistency with JPEGLSColorTransformation

    @Test("HP1 batch transform matches JPEGLSColorTransformation scalar for single pixel")
    func hp1ConsistencyWithScalar() throws {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP1Forward(r: r, g: g, b: b)
        
        let scalarResult = try JPEGLSColorTransformation.hp1.transformForward([r[0], g[0], b[0]])
        #expect(rP[0] == scalarResult[0])
        #expect(gP[0] == scalarResult[1])
        #expect(bP[0] == scalarResult[2])
    }

    @Test("HP2 batch transform matches JPEGLSColorTransformation scalar for single pixel")
    func hp2ConsistencyWithScalar() throws {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP2Forward(r: r, g: g, b: b)
        
        let scalarResult = try JPEGLSColorTransformation.hp2.transformForward([r[0], g[0], b[0]])
        #expect(rP[0] == scalarResult[0])
        #expect(gP[0] == scalarResult[1])
        #expect(bP[0] == scalarResult[2])
    }

    @Test("HP3 batch transform matches JPEGLSColorTransformation scalar for single pixel")
    func hp3ConsistencyWithScalar() throws {
        let acc = AccelerateFrameworkAccelerator()
        let r = [200], g = [100], b = [50]
        let (rP, gP, bP) = acc.applyHP3Forward(r: r, g: g, b: b)
        
        let scalarResult = try JPEGLSColorTransformation.hp3.transformForward([r[0], g[0], b[0]])
        #expect(rP[0] == scalarResult[0])
        #expect(gP[0] == scalarResult[1])
        #expect(bP[0] == scalarResult[2])
    }
}

#endif // canImport(Accelerate)
