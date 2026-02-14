/// Tests for JPEG-LS color transformation

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Color Transformation Tests")
struct JPEGLSColorTransformationTests {
    @Test("None transformation leaves components unchanged")
    func testNoneTransformation() throws {
        let transform = JPEGLSColorTransformation.none
        
        // Single component
        let single = [128]
        let forwardSingle = try transform.transformForward(single)
        let inverseSingle = try transform.transformInverse(forwardSingle)
        #expect(forwardSingle == single)
        #expect(inverseSingle == single)
        
        // RGB components
        let rgb = [100, 150, 200]
        let forwardRGB = try transform.transformForward(rgb)
        let inverseRGB = try transform.transformInverse(forwardRGB)
        #expect(forwardRGB == rgb)
        #expect(inverseRGB == rgb)
    }
    
    @Test("HP1 transformation is reversible")
    func testHP1TransformationReversible() throws {
        let transform = JPEGLSColorTransformation.hp1
        let original = [100, 150, 200]
        
        let transformed = try transform.transformForward(original)
        let recovered = try transform.transformInverse(transformed)
        
        #expect(recovered == original)
    }
    
    @Test("HP1 transformation formula")
    func testHP1Formula() throws {
        let transform = JPEGLSColorTransformation.hp1
        let r = 100
        let g = 150
        let b = 200
        
        let transformed = try transform.transformForward([r, g, b])
        
        // HP1: R' = R - G, G' = G, B' = B - G
        #expect(transformed[0] == r - g)  // R'
        #expect(transformed[1] == g)      // G'
        #expect(transformed[2] == b - g)  // B'
    }
    
    @Test("HP2 transformation is reversible")
    func testHP2TransformationReversible() throws {
        let transform = JPEGLSColorTransformation.hp2
        let original = [100, 150, 200]
        
        let transformed = try transform.transformForward(original)
        let recovered = try transform.transformInverse(transformed)
        
        #expect(recovered == original)
    }
    
    @Test("HP2 transformation formula")
    func testHP2Formula() throws {
        let transform = JPEGLSColorTransformation.hp2
        let r = 100
        let g = 150
        let b = 200
        
        let transformed = try transform.transformForward([r, g, b])
        
        // HP2: R' = R - G, G' = G, B' = B - ((R + G) >> 1)
        #expect(transformed[0] == r - g)          // R'
        #expect(transformed[1] == g)              // G'
        #expect(transformed[2] == b - ((r + g) >> 1))  // B'
    }
    
    @Test("HP3 transformation is reversible")
    func testHP3TransformationReversible() throws {
        let transform = JPEGLSColorTransformation.hp3
        let original = [100, 150, 200]
        
        let transformed = try transform.transformForward(original)
        let recovered = try transform.transformInverse(transformed)
        
        #expect(recovered == original)
    }
    
    @Test("HP3 transformation formula")
    func testHP3Formula() throws {
        let transform = JPEGLSColorTransformation.hp3
        let r = 100
        let g = 150
        let b = 200
        
        let transformed = try transform.transformForward([r, g, b])
        
        // HP3: R' = R - B, G' = G - ((R + B) >> 1), B' = B
        #expect(transformed[0] == r - b)              // R'
        #expect(transformed[1] == g - ((r + b) >> 1)) // G'
        #expect(transformed[2] == b)                  // B'
    }
    
    @Test("HP transformations work with edge values")
    func testEdgeValues() throws {
        let transforms: [JPEGLSColorTransformation] = [.hp1, .hp2, .hp3]
        
        // Test with zeros
        for transform in transforms {
            let zeros = [0, 0, 0]
            let transformed = try transform.transformForward(zeros)
            let recovered = try transform.transformInverse(transformed)
            #expect(recovered == zeros)
        }
        
        // Test with max 8-bit values
        for transform in transforms {
            let maxValues = [255, 255, 255]
            let transformed = try transform.transformForward(maxValues)
            let recovered = try transform.transformInverse(transformed)
            #expect(recovered == maxValues)
        }
        
        // Test with mixed values
        for transform in transforms {
            let mixed = [0, 128, 255]
            let transformed = try transform.transformForward(mixed)
            let recovered = try transform.transformInverse(transformed)
            #expect(recovered == mixed)
        }
    }
    
    @Test("None is valid for all component counts")
    func testNoneValidForAllCounts() {
        let transform = JPEGLSColorTransformation.none
        #expect(transform.isValid(forComponentCount: 1))
        #expect(transform.isValid(forComponentCount: 2))
        #expect(transform.isValid(forComponentCount: 3))
        #expect(transform.isValid(forComponentCount: 4))
    }
    
    @Test("HP transformations require 3 components")
    func testHPRequires3Components() {
        let transforms: [JPEGLSColorTransformation] = [.hp1, .hp2, .hp3]
        
        for transform in transforms {
            #expect(!transform.isValid(forComponentCount: 1))
            #expect(!transform.isValid(forComponentCount: 2))
            #expect(transform.isValid(forComponentCount: 3))
            #expect(!transform.isValid(forComponentCount: 4))
        }
    }
    
    @Test("HP transformations throw for wrong component count")
    func testHPThrowsForWrongCount() {
        let transforms: [JPEGLSColorTransformation] = [.hp1, .hp2, .hp3]
        
        for transform in transforms {
            #expect(throws: JPEGLSError.self) {
                try transform.transformForward([128])
            }
            #expect(throws: JPEGLSError.self) {
                try transform.transformForward([128, 128])
            }
            #expect(throws: JPEGLSError.self) {
                try transform.transformForward([128, 128, 128, 128])
            }
        }
    }
    
    @Test("Description strings are correct")
    func testDescriptions() {
        #expect(JPEGLSColorTransformation.none.description == "None")
        #expect(JPEGLSColorTransformation.hp1.description == "HP1")
        #expect(JPEGLSColorTransformation.hp2.description == "HP2")
        #expect(JPEGLSColorTransformation.hp3.description == "HP3")
    }
    
    @Test("Raw values are correct")
    func testRawValues() {
        #expect(JPEGLSColorTransformation.none.rawValue == 0)
        #expect(JPEGLSColorTransformation.hp1.rawValue == 1)
        #expect(JPEGLSColorTransformation.hp2.rawValue == 2)
        #expect(JPEGLSColorTransformation.hp3.rawValue == 3)
    }
}
