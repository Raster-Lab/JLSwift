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
    /// When `maxValue` is provided, transformed values are mapped modulo `maxValue + 1`
    /// so they remain in `[0, maxValue]`, matching the JPEG-LS modular arithmetic used
    /// during encoding. This is required when storing the result in a `MultiComponentImageData`
    /// pixel buffer (ITU-T T.870 Annex A §A.2).
    ///
    /// When `maxValue` is `nil` (the default), the raw integer difference is returned
    /// and may be negative.
    ///
    /// - Parameters:
    ///   - components: Original component values [R, G, B] or single component
    ///   - maxValue: Optional maximum sample value for modular reduction (e.g. 255 for 8-bit)
    /// - Returns: Transformed component values
    /// - Throws: `JPEGLSError.invalidComponentCount` if component count doesn't match transformation
    public func transformForward(_ components: [Int], maxValue: Int? = nil) throws -> [Int] {
        guard isValid(forComponentCount: components.count) else {
            throw JPEGLSError.invalidComponentCount(count: components.count)
        }
        
        let mod: (Int) -> Int
        if let mv = maxValue {
            let range = mv + 1
            mod = { v in ((v % range) + range) % range }
        } else {
            mod = { v in v }
        }
        
        switch self {
        case .none:
            return components
            
        case .hp1:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [mod(r - g), g, mod(b - g)]
            
        case .hp2:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [mod(r - g), g, mod(b - ((r + g) >> 1))]
            
        case .hp3:
            let r = components[0]
            let g = components[1]
            let b = components[2]
            return [mod(r - b), mod(g - ((r + b) >> 1)), b]
        }
    }
    
    /// Apply the inverse color transformation to recover original colors
    ///
    /// Transforms encoded components back to original color space during decoding.
    ///
    /// When `maxValue` is provided, intermediate and final values are reduced modulo
    /// `maxValue + 1`. This is required when the input components are the modular-mapped
    /// values produced by JPEG-LS decoding (ITU-T T.870 Annex A §A.2).
    ///
    /// When `maxValue` is `nil` (the default), straight integer arithmetic is used,
    /// which is correct when the input contains the raw (possibly negative) transformed
    /// values from `transformForward`.
    ///
    /// - Parameters:
    ///   - components: Transformed component values
    ///   - maxValue: Optional maximum sample value for modular reduction (e.g. 255 for 8-bit)
    /// - Returns: Original component values [R, G, B] or single component
    /// - Throws: `JPEGLSError.invalidComponentCount` if component count doesn't match transformation
    public func transformInverse(_ components: [Int], maxValue: Int? = nil) throws -> [Int] {
        guard isValid(forComponentCount: components.count) else {
            throw JPEGLSError.invalidComponentCount(count: components.count)
        }
        
        let mod: (Int) -> Int
        if let mv = maxValue {
            let range = mv + 1
            mod = { v in ((v % range) + range) % range }
        } else {
            mod = { v in v }
        }
        
        switch self {
        case .none:
            return components
            
        case .hp1:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            return [mod(rPrime + gPrime), gPrime, mod(bPrime + gPrime)]
            
        case .hp2:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            let r = mod(rPrime + gPrime)
            let g = gPrime
            let b = mod(bPrime + ((r + g) >> 1))
            return [r, g, b]
            
        case .hp3:
            let rPrime = components[0]
            let gPrime = components[1]
            let bPrime = components[2]
            let b = bPrime
            let r = mod(rPrime + b)
            let g = mod(gPrime + ((r + b) >> 1))
            return [r, g, b]
        }
    }
}

extension JPEGLSColorTransformation: CustomStringConvertible {
    /// Human-readable name of the color transformation
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
