//  Metal compute shaders for JPEG-LS GPU acceleration.
//
//  These shaders implement GPU-accelerated gradient computation,
//  MED prediction, colour space transformation, and gradient
//  quantisation for JPEG-LS encoding. They are designed to process
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

// MARK: - Gradient Quantisation

/// Quantise a single gradient value to a context index in [-4, 4].
///
/// Applies the JPEG-LS threshold quantisation mapping:
/// d <= -t3 → -4,  d <= -t2 → -3,  d <= -t1 → -2,  d < 0 → -1,
/// d == 0 → 0,  d < t1 → 1,  d < t2 → 2,  d < t3 → 3,  else → 4
static inline int quantise_gradient(int d, int t1, int t2, int t3) {
    if (d <= -t3) return -4;
    if (d <= -t2) return -3;
    if (d <= -t1) return -2;
    if (d < 0)    return -1;
    if (d == 0)   return  0;
    if (d < t1)   return  1;
    if (d < t2)   return  2;
    if (d < t3)   return  3;
    return 4;
}

/// Quantise a gradient value with NEAR-lossless awareness (ITU-T.87 §4.3.1).
///
/// Extends the basic quantisation to support the NEAR parameter:
/// d < -near → -1,  -near <= d <= near → 0,  d < t1 → 1, …
/// When near == 0 this is identical to `quantise_gradient`.
static inline int quantise_gradient_near(int d, int t1, int t2, int t3, int near) {
    if (d <= -t3)   return -4;
    if (d <= -t2)   return -3;
    if (d <= -t1)   return -2;
    if (d < -near)  return -1;
    if (d <= near)  return  0;
    if (d < t1)     return  1;
    if (d < t2)     return  2;
    if (d < t3)     return  3;
    return 4;
}

/// Compute the MED (Median Edge Detector) prediction from three neighbours.
///
/// - a: north (top) pixel
/// - b: west (left) pixel
/// - c: northwest (top-left) pixel
static inline int med_predict(int a, int b, int c) {
    int minAB = min(a, b);
    int maxAB = max(a, b);
    if (c >= maxAB) return minAB;
    if (c <= minAB) return maxAB;
    return a + b - c;
}

/// Quantise a batch of gradients to context indices using JPEG-LS thresholds.
///
/// For each element i, applies threshold quantisation to d1, d2, and d3,
/// mapping each gradient to a value in [-4, 4].
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_quantize_gradients(
    constant int* d1 [[buffer(0)]],     // Input: first gradients
    constant int* d2 [[buffer(1)]],     // Input: second gradients
    constant int* d3 [[buffer(2)]],     // Input: third gradients
    device int* q1 [[buffer(3)]],       // Output: first quantised gradients
    device int* q2 [[buffer(4)]],       // Output: second quantised gradients
    device int* q3 [[buffer(5)]],       // Output: third quantised gradients
    constant uint& count [[buffer(6)]], // Number of elements
    constant int& t1 [[buffer(7)]],     // Quantisation threshold 1
    constant int& t2 [[buffer(8)]],     // Quantisation threshold 2
    constant int& t3 [[buffer(9)]],     // Quantisation threshold 3
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    q1[gid] = quantise_gradient(d1[gid], t1, t2, t3);
    q2[gid] = quantise_gradient(d2[gid], t1, t2, t3);
    q3[gid] = quantise_gradient(d3[gid], t1, t2, t3);
}

// MARK: - Colour Space Transformations

/// Apply HP1 forward colour transform to a batch of RGB pixels.
///
/// HP1 forward transform (lossless, reversible):
///   R′ = R − G
///   G′ = G
///   B′ = B − G
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp1_forward(
    constant int* r [[buffer(0)]],          // Input: red component
    constant int* g [[buffer(1)]],          // Input: green component
    constant int* b [[buffer(2)]],          // Input: blue component
    device int* rPrime [[buffer(3)]],       // Output: transformed red
    device int* gPrime [[buffer(4)]],       // Output: transformed green (= G)
    device int* bPrime [[buffer(5)]],       // Output: transformed blue
    constant uint& count [[buffer(6)]],     // Number of pixels
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    rPrime[gid] = r[gid] - g[gid];
    gPrime[gid] = g[gid];
    bPrime[gid] = b[gid] - g[gid];
}

/// Apply HP1 inverse colour transform to a batch of transformed pixels.
///
/// HP1 inverse transform:
///   R = R′ + G′
///   G = G′
///   B = B′ + G′
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp1_inverse(
    constant int* rPrime [[buffer(0)]],     // Input: transformed red
    constant int* gPrime [[buffer(1)]],     // Input: transformed green (= G)
    constant int* bPrime [[buffer(2)]],     // Input: transformed blue
    device int* r [[buffer(3)]],            // Output: recovered red
    device int* g [[buffer(4)]],            // Output: recovered green
    device int* b [[buffer(5)]],            // Output: recovered blue
    constant uint& count [[buffer(6)]],     // Number of pixels
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    r[gid] = rPrime[gid] + gPrime[gid];
    g[gid] = gPrime[gid];
    b[gid] = bPrime[gid] + gPrime[gid];
}

/// Apply HP2 forward colour transform to a batch of RGB pixels.
///
/// HP2 forward transform (lossless, reversible):
///   R′ = R − G
///   G′ = G
///   B′ = B − ((R + G) >> 1)
///
/// The arithmetic right-shift (>> 1) performs floor division by 2.
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp2_forward(
    constant int* r [[buffer(0)]],
    constant int* g [[buffer(1)]],
    constant int* b [[buffer(2)]],
    device int* rPrime [[buffer(3)]],
    device int* gPrime [[buffer(4)]],
    device int* bPrime [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    int rv = r[gid];
    int gv = g[gid];
    int bv = b[gid];
    rPrime[gid] = rv - gv;
    gPrime[gid] = gv;
    bPrime[gid] = bv - ((rv + gv) >> 1);
}

/// Apply HP2 inverse colour transform to a batch of transformed pixels.
///
/// HP2 inverse transform:
///   R = R′ + G′
///   G = G′
///   B = B′ + ((R + G) >> 1)
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp2_inverse(
    constant int* rPrime [[buffer(0)]],
    constant int* gPrime [[buffer(1)]],
    constant int* bPrime [[buffer(2)]],
    device int* r [[buffer(3)]],
    device int* g [[buffer(4)]],
    device int* b [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    int rv = rPrime[gid] + gPrime[gid];  // R = R′ + G′
    int gv = gPrime[gid];
    r[gid] = rv;
    g[gid] = gv;
    b[gid] = bPrime[gid] + ((rv + gv) >> 1);
}

/// Apply HP3 forward colour transform to a batch of RGB pixels.
///
/// HP3 forward transform (lossless, reversible):
///   B′ = B
///   R′ = R − B
///   G′ = G − ((R + B) >> 1)
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp3_forward(
    constant int* r [[buffer(0)]],
    constant int* g [[buffer(1)]],
    constant int* b [[buffer(2)]],
    device int* rPrime [[buffer(3)]],
    device int* gPrime [[buffer(4)]],
    device int* bPrime [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    int rv = r[gid];
    int gv = g[gid];
    int bv = b[gid];
    rPrime[gid] = rv - bv;
    gPrime[gid] = gv - ((rv + bv) >> 1);
    bPrime[gid] = bv;
}

/// Apply HP3 inverse colour transform to a batch of transformed pixels.
///
/// HP3 inverse transform:
///   B = B′
///   R = R′ + B′
///   G = G′ + ((R + B) >> 1)
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_colour_transform_hp3_inverse(
    constant int* rPrime [[buffer(0)]],
    constant int* gPrime [[buffer(1)]],
    constant int* bPrime [[buffer(2)]],
    device int* r [[buffer(3)]],
    device int* g [[buffer(4)]],
    device int* b [[buffer(5)]],
    constant uint& count [[buffer(6)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }
    int bv = bPrime[gid];
    int rv = rPrime[gid] + bv;  // R = R′ + B′
    r[gid] = rv;
    g[gid] = gPrime[gid] + ((rv + bv) >> 1);
    b[gid] = bv;
}

// MARK: - Full Encoding Preprocessing Pipeline

/// Combined encoding preprocessing shader.
///
/// Performs the complete JPEG-LS encoding preprocessing for a batch of pixels
/// in a single GPU pass, replacing three separate dispatch calls
/// (compute_gradients + compute_med_prediction + compute_quantize_gradients)
/// with one. This reduces dispatch overhead and improves data locality.
///
/// For each pixel position i, given neighbours a (north), b (west),
/// c (northwest) and the current pixel x, the shader outputs:
/// - prediction[i] = MED(a, b, c) prediction value
/// - predError[i]  = x[i] − prediction[i]  (raw prediction error)
/// - q1[i], q2[i], q3[i] = quantised gradients (context indices in [−4, 4])
///
/// The quantisation uses the NEAR-aware formula:
///   d < −NEAR → −1,  −NEAR ≤ d ≤ NEAR → 0
/// which reduces to the standard lossless mapping when NEAR = 0.
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_encoding_pipeline(
    constant int*  a          [[buffer(0)]],   // North pixel values
    constant int*  b          [[buffer(1)]],   // West pixel values
    constant int*  c          [[buffer(2)]],   // Northwest pixel values
    constant int*  x          [[buffer(3)]],   // Current pixel values
    device   int*  prediction [[buffer(4)]],   // Output: MED predictions
    device   int*  predError  [[buffer(5)]],   // Output: raw prediction errors
    device   int*  q1         [[buffer(6)]],   // Output: quantised gradient 1
    device   int*  q2         [[buffer(7)]],   // Output: quantised gradient 2
    device   int*  q3         [[buffer(8)]],   // Output: quantised gradient 3
    constant uint& count      [[buffer(9)]],   // Number of elements
    constant int&  near       [[buffer(10)]],  // NEAR parameter (0 = lossless)
    constant int&  t1         [[buffer(11)]],  // Quantisation threshold 1
    constant int&  t2         [[buffer(12)]],  // Quantisation threshold 2
    constant int&  t3         [[buffer(13)]],  // Quantisation threshold 3
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }

    int av = a[gid];
    int bv = b[gid];
    int cv = c[gid];
    int xv = x[gid];

    // Gradients (convention: a=north, b=west, c=northwest)
    int d1 = bv - cv;
    int d2 = av - cv;
    int d3 = cv - av;

    // Quantise gradients with NEAR-aware formula
    q1[gid] = quantise_gradient_near(d1, t1, t2, t3, near);
    q2[gid] = quantise_gradient_near(d2, t1, t2, t3, near);
    q3[gid] = quantise_gradient_near(d3, t1, t2, t3, near);

    // MED prediction
    int px = med_predict(av, bv, cv);
    prediction[gid] = px;

    // Raw prediction error
    predError[gid] = xv - px;
}

// MARK: - Full Decoding Reconstruction Pipeline

/// Combined decoding reconstruction shader.
///
/// Performs the JPEG-LS decoding reconstruction for a batch of pixels in a
/// single GPU pass. Given the MED neighbours (a, b, c) and the mapped
/// prediction error for each pixel (output from Golomb-Rice entropy decoding
/// on the CPU), reconstructs the original pixel values.
///
/// For each pixel position i:
///   reconstructed[i] = MED(a[i], b[i], c[i]) + errval[i]
///
/// The entropy-decoded error values must already be de-mapped (signed)
/// before being passed to this shader.
///
/// Thread layout: 1D with one thread per pixel
kernel void compute_decoding_pipeline(
    constant int*  a             [[buffer(0)]],  // North pixel (already decoded)
    constant int*  b             [[buffer(1)]],  // West pixel (already decoded)
    constant int*  c             [[buffer(2)]],  // Northwest pixel (already decoded)
    constant int*  errval        [[buffer(3)]],  // Mapped prediction error
    device   int*  reconstructed [[buffer(4)]],  // Output: reconstructed pixel values
    constant uint& count         [[buffer(5)]],  // Number of elements
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= count) {
        return;
    }

    int px = med_predict(a[gid], b[gid], c[gid]);
    reconstructed[gid] = px + errval[gid];
}
