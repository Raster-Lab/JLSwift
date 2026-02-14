/// Color transformation types for JPEG-LS multi-component images
///
/// JPEG-LS supports color space transformations to improve compression of
/// correlated color components (e.g., RGB images).

import Foundation

/// Color transformation type
///
/// Defines the transformation applied to multi-component images before encoding.
/// The decoder must apply the inverse transformation to recover the original colors.
public enum JPEGLSColorTransformation: UInt8, Sendable, Equatable {
    /// No color transformation (components encoded independently)
    case none = 0
    
    /// HP1 transformation: For RGB images
    /// - G' = G
    /// - R' = R - G
    /// - B' = B - G
    case hp1 = 1
    
    /// HP2 transformation: For RGB images with better correlation
    /// - G' = G
    /// - R' = R - G
    /// - B' = B - ((R + G) >> 1)
    case hp2 = 2
    
    /// HP3 transformation: For RGB images (alternative)
    /// - B' = B
    /// - R' = R - B
    /// - G' = G - ((R + B) >> 1)
    case hp3 = 3
    
    /// Returns true if this transformation is applicable for the given component count
    ///
    /// - Parameter componentCount: Number of image components
    /// - Returns: True if transformation can be applied
    public func isValid(forComponentCount componentCount: Int) -> Bool {
        switch self {
        case .none:
            // No transformation is always valid
            return true
        case .hp1, .hp2, .hp3:
            // HP transformations require exactly 3 components (RGB)
            return componentCount == 3
        }
    }
    
    /// Apply the forward color transformation to a pixel
    ///
    /// Transforms RGB components before encoding. The transformation is lossless
    /// and reversible.
    ///
    /// - Parameter components: Original component values [R, G, B] or single component
    /// - Returns: Transformed component values
    /// - Throws: `JPEGLSError.invalidComponentCount` if component count doesn't match transformation
    public func transformForward(_ components: [Int]) throws -> [Int] {
        guard isValid(forComponentCount: components.count) else {
            throw JPEGLSError.invalidComponentCount(count: components.count)
        }
        
        switch self {
        case .none:
            return components
            
        case .hp1:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [r - g, g, b - g]
            
        case .hp2:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [r - g, g, b - ((r + g) >> 1)]
            
        case .hp3:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [r - b, g - ((r + b) >> 1), b]
        }
    }
    
    /// Apply the inverse color transformation to recover original colors
    ///
    /// Transforms encoded components back to original color space during decoding.
    ///
    /// - Parameter components: Transformed component values
    /// - Returns: Original component values [R, G, B] or single component
    /// - Throws: `JPEGLSError.invalidComponentCount` if component count doesn't match transformation
    public func transformInverse(_ components: [Int]) throws -> [Int] {
        guard isValid(forComponentCount: components.count) else {
            throw JPEGLSError.invalidComponentCount(count: components.count)
        }
        
        switch self {
        case .none:
            return components
            
        case .hp1:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            return [rPrime + gPrime, gPrime, bPrime + gPrime]
            
        case .hp2:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            let r = rPrime + gPrime
            let g = gPrime
            let b = bPrime + ((r + g) >> 1)
            return [r, g, b]
            
        case .hp3:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            let b = bPrime
            let r = rPrime + b
            let g = gPrime + ((r + b) >> 1)
            return [r, g, b]
        }
    }
}

extension JPEGLSColorTransformation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:
            return "None"
        case .hp1:
            return "HP1"
        case .hp2:
            return "HP2"
        case .hp3:
            return "HP3"
        }
    }
}
