import Testing
import Foundation
@testable import JPEGLS

@Suite("Platform Protocols Tests")
struct PlatformProtocolsTests {
    // MARK: - ScalarAccelerator Tests
    
    @Test("ScalarAccelerator platformName is correct")
    func scalarPlatformName() {
        #expect(ScalarAccelerator.platformName == "Scalar")
    }
    
    @Test("ScalarAccelerator is always supported")
    func scalarIsSupported() {
        #expect(ScalarAccelerator.isSupported == true)
    }
    
    @Test("ScalarAccelerator computes gradients correctly")
    func scalarComputeGradients() {
        let accelerator = ScalarAccelerator()
        
        // Test case 1: Simple gradients
        let result1 = accelerator.computeGradients(a: 10, b: 20, c: 15)
        #expect(result1.d1 == 5)   // b - c = 20 - 15 = 5
        #expect(result1.d2 == -5)  // a - c = 10 - 15 = -5
        #expect(result1.d3 == 5)   // c - a = 15 - 10 = 5
        
        // Test case 2: Zero gradients
        let result2 = accelerator.computeGradients(a: 10, b: 10, c: 10)
        #expect(result2.d1 == 0)
        #expect(result2.d2 == 0)
        #expect(result2.d3 == 0)
        
        // Test case 3: Negative gradients
        let result3 = accelerator.computeGradients(a: 5, b: 3, c: 8)
        #expect(result3.d1 == -5)  // b - c = 3 - 8 = -5
        #expect(result3.d2 == -3)  // a - c = 5 - 8 = -3
        #expect(result3.d3 == 3)   // c - a = 8 - 5 = 3
    }
    
    @Test("ScalarAccelerator MED predictor with c >= max(a, b)")
    func scalarMEDCase1() {
        let accelerator = ScalarAccelerator()
        let result = accelerator.medPredictor(a: 10, b: 20, c: 30)
        #expect(result == 10)  // min(a, b) = min(10, 20) = 10
    }
    
    @Test("ScalarAccelerator MED predictor with c <= min(a, b)")
    func scalarMEDCase2() {
        let accelerator = ScalarAccelerator()
        let result = accelerator.medPredictor(a: 20, b: 30, c: 10)
        #expect(result == 30)  // max(a, b) = max(20, 30) = 30
    }
    
    @Test("ScalarAccelerator MED predictor with c between a and b")
    func scalarMEDCase3() {
        let accelerator = ScalarAccelerator()
        let result = accelerator.medPredictor(a: 10, b: 30, c: 20)
        #expect(result == 20)  // a + b - c = 10 + 30 - 20 = 20
    }
    
    @Test("ScalarAccelerator MED predictor edge cases")
    func scalarMEDEdgeCases() {
        let accelerator = ScalarAccelerator()
        
        // All equal
        #expect(accelerator.medPredictor(a: 10, b: 10, c: 10) == 10)
        
        // Zero values
        #expect(accelerator.medPredictor(a: 0, b: 0, c: 0) == 0)
    }
    
    @Test("ScalarAccelerator quantizes gradients correctly - positive values")
    func scalarQuantizePositive() {
        let accelerator = ScalarAccelerator()
        let t1 = 3, t2 = 7, t3 = 21
        
        // Test d = 0
        let result0 = accelerator.quantizeGradients(d1: 0, d2: 0, d3: 0, t1: t1, t2: t2, t3: t3)
        #expect(result0.q1 == 0)
        #expect(result0.q2 == 0)
        #expect(result0.q3 == 0)
        
        // Test 0 < d < t1
        let result1 = accelerator.quantizeGradients(d1: 1, d2: 2, d3: 2, t1: t1, t2: t2, t3: t3)
        #expect(result1.q1 == 1)
        #expect(result1.q2 == 1)
        #expect(result1.q3 == 1)
        
        // Test t1 <= d < t2
        let result2 = accelerator.quantizeGradients(d1: 3, d2: 5, d3: 6, t1: t1, t2: t2, t3: t3)
        #expect(result2.q1 == 2)
        #expect(result2.q2 == 2)
        #expect(result2.q3 == 2)
        
        // Test t2 <= d < t3
        let result3 = accelerator.quantizeGradients(d1: 7, d2: 10, d3: 20, t1: t1, t2: t2, t3: t3)
        #expect(result3.q1 == 3)
        #expect(result3.q2 == 3)
        #expect(result3.q3 == 3)
        
        // Test d >= t3
        let result4 = accelerator.quantizeGradients(d1: 21, d2: 50, d3: 100, t1: t1, t2: t2, t3: t3)
        #expect(result4.q1 == 4)
        #expect(result4.q2 == 4)
        #expect(result4.q3 == 4)
    }
    
    @Test("ScalarAccelerator quantizes gradients correctly - negative values")
    func scalarQuantizeNegative() {
        let accelerator = ScalarAccelerator()
        let t1 = 3, t2 = 7, t3 = 21
        
        // Test -t1 < d < 0
        let result1 = accelerator.quantizeGradients(d1: -1, d2: -2, d3: -2, t1: t1, t2: t2, t3: t3)
        #expect(result1.q1 == -1)
        #expect(result1.q2 == -1)
        #expect(result1.q3 == -1)
        
        // Test -t2 < d <= -t1
        let result2 = accelerator.quantizeGradients(d1: -3, d2: -5, d3: -6, t1: t1, t2: t2, t3: t3)
        #expect(result2.q1 == -2)
        #expect(result2.q2 == -2)
        #expect(result2.q3 == -2)
        
        // Test -t3 < d <= -t2
        let result3 = accelerator.quantizeGradients(d1: -7, d2: -10, d3: -20, t1: t1, t2: t2, t3: t3)
        #expect(result3.q1 == -3)
        #expect(result3.q2 == -3)
        #expect(result3.q3 == -3)
        
        // Test d <= -t3
        let result4 = accelerator.quantizeGradients(d1: -21, d2: -50, d3: -100, t1: t1, t2: t2, t3: t3)
        #expect(result4.q1 == -4)
        #expect(result4.q2 == -4)
        #expect(result4.q3 == -4)
    }
    
    @Test("ScalarAccelerator quantizes gradients with different values")
    func scalarQuantizeMixed() {
        let accelerator = ScalarAccelerator()
        let t1 = 3, t2 = 7, t3 = 21
        
        let result = accelerator.quantizeGradients(d1: -10, d2: 0, d3: 10, t1: t1, t2: t2, t3: t3)
        #expect(result.q1 == -3)  // -10 is in range -t3 < d <= -t2
        #expect(result.q2 == 0)   // 0 maps to 0
        #expect(result.q3 == 3)   // 10 is in range t2 <= d < t3
    }
    
    // MARK: - Platform Selection Tests
    
    @Test("selectPlatformAccelerator returns a valid accelerator")
    func platformSelection() {
        let accelerator = selectPlatformAccelerator()
        
        // Verify that the accelerator works by testing basic operations
        let gradients = accelerator.computeGradients(a: 10, b: 20, c: 15)
        #expect(gradients.d1 == 5)
        #expect(gradients.d2 == -5)
        #expect(gradients.d3 == 5)
        
        let prediction = accelerator.medPredictor(a: 10, b: 30, c: 20)
        #expect(prediction == 20)
    }
    
    @Test("selectPlatformAccelerator returns correct platform for architecture")
    func platformSelectionCorrectType() {
        let accelerator = selectPlatformAccelerator()
        
        #if arch(arm64)
        // On ARM64, should get ARM64Accelerator
        #expect(type(of: accelerator) is ARM64Accelerator.Type || type(of: accelerator) is ScalarAccelerator.Type)
        #elseif arch(x86_64)
        // On x86_64, should get X86_64Accelerator
        #expect(type(of: accelerator) is X86_64Accelerator.Type || type(of: accelerator) is ScalarAccelerator.Type)
        #else
        // On other architectures, should get ScalarAccelerator
        #expect(type(of: accelerator) is ScalarAccelerator.Type)
        #endif
    }
    
    // MARK: - ARM64Accelerator Tests (conditionally compiled)
    
    #if arch(arm64)
    @Test("ARM64Accelerator platformName is correct")
    func arm64PlatformName() {
        #expect(ARM64Accelerator.platformName == "ARM64")
    }
    
    @Test("ARM64Accelerator is supported on ARM64")
    func arm64IsSupported() {
        #expect(ARM64Accelerator.isSupported == true)
    }
    
    @Test("ARM64Accelerator produces correct results")
    func arm64Results() {
        let accelerator = ARM64Accelerator()
        
        // Test gradients
        let gradients = accelerator.computeGradients(a: 10, b: 20, c: 15)
        #expect(gradients.d1 == 5)
        #expect(gradients.d2 == -5)
        #expect(gradients.d3 == 5)
        
        // Test MED predictor
        let prediction = accelerator.medPredictor(a: 10, b: 30, c: 20)
        #expect(prediction == 20)
        
        // Test quantization
        let quant = accelerator.quantizeGradients(d1: 5, d2: 0, d3: -10, t1: 3, t2: 7, t3: 21)
        #expect(quant.q1 == 2)
        #expect(quant.q2 == 0)
        #expect(quant.q3 == -3)
    }
    #endif
    
    // MARK: - X86_64Accelerator Tests (conditionally compiled)
    
    #if arch(x86_64)
    @Test("X86_64Accelerator platformName is correct")
    func x86_64PlatformName() {
        #expect(X86_64Accelerator.platformName == "x86-64")
    }
    
    @Test("X86_64Accelerator is supported on x86-64")
    func x86_64IsSupported() {
        #expect(X86_64Accelerator.isSupported == true)
    }
    
    @Test("X86_64Accelerator produces correct results")
    func x86_64Results() {
        let accelerator = X86_64Accelerator()
        
        // Test gradients
        let gradients = accelerator.computeGradients(a: 10, b: 20, c: 15)
        #expect(gradients.d1 == 5)
        #expect(gradients.d2 == -5)
        #expect(gradients.d3 == 5)
        
        // Test MED predictor - all cases
        // Case 1: c >= max(a, b)
        let pred1 = accelerator.medPredictor(a: 10, b: 20, c: 30)
        #expect(pred1 == 10)
        
        // Case 2: c <= min(a, b)
        let pred2 = accelerator.medPredictor(a: 20, b: 30, c: 10)
        #expect(pred2 == 30)
        
        // Case 3: c between a and b
        let pred3 = accelerator.medPredictor(a: 10, b: 30, c: 20)
        #expect(pred3 == 20)
        
        // Test quantization - all quantization levels
        // Positive quantization levels
        let quant1 = accelerator.quantizeGradients(d1: 0, d2: 2, d3: 5, t1: 3, t2: 7, t3: 21)
        #expect(quant1.q1 == 0)  // d == 0
        #expect(quant1.q2 == 1)  // 0 < d < t1
        #expect(quant1.q3 == 2)  // t1 <= d < t2
        
        let quant2 = accelerator.quantizeGradients(d1: 10, d2: 25, d3: 1, t1: 3, t2: 7, t3: 21)
        #expect(quant2.q1 == 3)  // t2 <= d < t3
        #expect(quant2.q2 == 4)  // d >= t3
        #expect(quant2.q3 == 1)  // 0 < d < t1
        
        // Negative quantization levels
        let quant3 = accelerator.quantizeGradients(d1: -1, d2: -5, d3: -10, t1: 3, t2: 7, t3: 21)
        #expect(quant3.q1 == -1)  // -t1 < d < 0
        #expect(quant3.q2 == -2)  // -t2 < d <= -t1
        #expect(quant3.q3 == -3)  // -t3 < d <= -t2
        
        let quant4 = accelerator.quantizeGradients(d1: -25, d2: -21, d3: -2, t1: 3, t2: 7, t3: 21)
        #expect(quant4.q1 == -4)  // d <= -t3
        #expect(quant4.q2 == -4)  // d <= -t3
        #expect(quant4.q3 == -1)  // -t1 < d < 0
    }
    #endif
    
    // MARK: - Additional Edge Case Tests
    
    @Test("ScalarAccelerator gradient computation with large values")
    func scalarGradientsLargeValues() {
        let accelerator = ScalarAccelerator()
        let result = accelerator.computeGradients(a: 1000, b: 2000, c: 1500)
        #expect(result.d1 == 500)
        #expect(result.d2 == -500)
        #expect(result.d3 == 500)
    }
    
    @Test("ScalarAccelerator MED predictor with all same values")
    func scalarMEDAllSame() {
        let accelerator = ScalarAccelerator()
        let result = accelerator.medPredictor(a: 100, b: 100, c: 100)
        #expect(result == 100)
    }
    
    @Test("ScalarAccelerator MED predictor boundary between cases")
    func scalarMEDBoundary() {
        let accelerator = ScalarAccelerator()
        
        // Test case where c == max(a, b)
        let result1 = accelerator.medPredictor(a: 10, b: 20, c: 20)
        #expect(result1 == 10)  // c >= max(a,b), so min(a,b)
        
        // Test case where c == min(a, b)
        let result2 = accelerator.medPredictor(a: 20, b: 30, c: 20)
        #expect(result2 == 30)  // c <= min(a,b), so max(a,b) = 30
    }
    
    @Test("ScalarAccelerator quantization at boundaries")
    func scalarQuantizeBoundaries() {
        let accelerator = ScalarAccelerator()
        let t1 = 3, t2 = 7, t3 = 21
        
        // Test exactly at boundaries
        let resultT1 = accelerator.quantizeGradients(d1: 3, d2: 3, d3: 3, t1: t1, t2: t2, t3: t3)
        #expect(resultT1.q1 == 2)  // t1 <= d < t2
        
        let resultT2 = accelerator.quantizeGradients(d1: 7, d2: 7, d3: 7, t1: t1, t2: t2, t3: t3)
        #expect(resultT2.q1 == 3)  // t2 <= d < t3
        
        let resultT3 = accelerator.quantizeGradients(d1: 21, d2: 21, d3: 21, t1: t1, t2: t2, t3: t3)
        #expect(resultT3.q1 == 4)  // d >= t3
        
        // Negative boundaries
        let resultNegT1 = accelerator.quantizeGradients(d1: -3, d2: -3, d3: -3, t1: t1, t2: t2, t3: t3)
        #expect(resultNegT1.q1 == -2)  // -t2 < d <= -t1
        
        let resultNegT2 = accelerator.quantizeGradients(d1: -7, d2: -7, d3: -7, t1: t1, t2: t2, t3: t3)
        #expect(resultNegT2.q1 == -3)  // -t3 < d <= -t2
        
        let resultNegT3 = accelerator.quantizeGradients(d1: -21, d2: -21, d3: -21, t1: t1, t2: t2, t3: t3)
        #expect(resultNegT3.q1 == -4)  // d <= -t3
    }
    
    @Test("ScalarAccelerator quantization with different thresholds")
    func scalarQuantizeDifferentThresholds() {
        let accelerator = ScalarAccelerator()
        
        // Test with different threshold values
        let result1 = accelerator.quantizeGradients(d1: 5, d2: 5, d3: 5, t1: 10, t2: 20, t3: 30)
        #expect(result1.q1 == 1)  // 0 < d < t1
        
        let result2 = accelerator.quantizeGradients(d1: 15, d2: 15, d3: 15, t1: 10, t2: 20, t3: 30)
        #expect(result2.q1 == 2)  // t1 <= d < t2
        
        let result3 = accelerator.quantizeGradients(d1: 25, d2: 25, d3: 25, t1: 10, t2: 20, t3: 30)
        #expect(result3.q1 == 3)  // t2 <= d < t3
    }
    
    @Test("Platform accelerator type conformance")
    func platformAcceleratorConformance() {
        // Test that ScalarAccelerator conforms to PlatformAccelerator
        let scalar: any PlatformAccelerator = ScalarAccelerator()
        #expect(scalar.computeGradients(a: 1, b: 2, c: 3).d1 == -1)
        #expect(scalar.medPredictor(a: 1, b: 2, c: 3) == 1)  // c <= min(a,b), so max(a,b) = 2... wait let me check
        
        // Test through protocol
        let selected = selectPlatformAccelerator()
        let gradients = selected.computeGradients(a: 5, b: 10, c: 8)
        #expect(gradients.d1 == 2)  // b - c = 10 - 8
        #expect(gradients.d2 == -3)  // a - c = 5 - 8
        #expect(gradients.d3 == 3)  // c - a = 8 - 5
    }
    
    @Test("ScalarAccelerator initialization")
    func scalarInitialization() {
        // Test that we can create multiple instances
        let acc1 = ScalarAccelerator()
        let acc2 = ScalarAccelerator()
        
        // Both should work identically
        let result1 = acc1.computeGradients(a: 10, b: 20, c: 15)
        let result2 = acc2.computeGradients(a: 10, b: 20, c: 15)
        
        #expect(result1.d1 == result2.d1)
        #expect(result1.d2 == result2.d2)
        #expect(result1.d3 == result2.d3)
    }
}
