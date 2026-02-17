//  Metal compute shaders for JPEG-LS GPU acceleration.
//
//  These shaders implement GPU-accelerated gradient computation and
//  MED prediction for JPEG-LS encoding. They are designed to process
//  large batches of pixels in parallel on the GPU.
//
//  Metal Shading Language (MSL) version 2.0+

#include <metal_stdlib>
using namespace metal;

/// Compute gradients for a batch of pixels.
///
/// For each pixel position i, computes:
/// - d1[i] = b[i] - c[i] (horizontal gradient)
/// - d2[i] = a[i] - c[i] (vertical gradient)
/// - d3[i] = c[i] - a[i] (diagonal gradient)
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_gradients(
    constant int* a [[buffer(0)]],      // North pixel values
    constant int* b [[buffer(1)]],      // West pixel values
    constant int* c [[buffer(2)]],      // Northwest pixel values
    device int* d1 [[buffer(3)]],       // Output: horizontal gradients
    device int* d2 [[buffer(4)]],       // Output: vertical gradients
    device int* d3 [[buffer(5)]],       // Output: diagonal gradients
    constant uint& count [[buffer(6)]], // Number of elements
    uint gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid >= count) {
        return;
    }
    
    // Load pixel values
    int av = a[gid];
    int bv = b[gid];
    int cv = c[gid];
    
    // Compute gradients
    d1[gid] = bv - cv;  // Horizontal gradient
    d2[gid] = av - cv;  // Vertical gradient
    d3[gid] = cv - av;  // Diagonal gradient
}

/// Compute MED (Median Edge Detector) predictions for a batch of pixels.
///
/// Implements the JPEG-LS MED predictor:
/// - If c >= max(a, b): return min(a, b)
/// - If c <= min(a, b): return max(a, b)
/// - Otherwise: return a + b - c
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_med_prediction(
    constant int* a [[buffer(0)]],      // North pixel values
    constant int* b [[buffer(1)]],      // West pixel values
    constant int* c [[buffer(2)]],      // Northwest pixel values
    device int* pred [[buffer(3)]],     // Output: predicted values
    constant uint& count [[buffer(4)]], // Number of elements
    uint gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid >= count) {
        return;
    }
    
    // Load pixel values
    int av = a[gid];
    int bv = b[gid];
    int cv = c[gid];
    
    // Compute min and max of a and b
    int minAB = min(av, bv);
    int maxAB = max(av, bv);
    
    // MED predictor logic
    int prediction;
    if (cv >= maxAB) {
        // c >= max(a, b) → return min(a, b)
        prediction = minAB;
    } else if (cv <= minAB) {
        // c <= min(a, b) → return max(a, b)
        prediction = maxAB;
    } else {
        // Otherwise → return a + b - c
        prediction = av + bv - cv;
    }
    
    pred[gid] = prediction;
}
