# Vulkan GPU Compute Acceleration

## Overview

JLSwift includes GPU acceleration architecture for the Vulkan compute API on Linux and Windows platforms. Vulkan compute shaders provide cross-vendor GPU parallelism for JPEG-LS encoding operations, complementing the Metal GPU support available on Apple platforms.

> **Status**: Phase 15.2 — Swift architecture implemented with CPU fallback. GPU execution via Vulkan compute requires the Vulkan SDK and SPIR-V shader binaries, which are not yet bundled with the project. All operations currently use the CPU fallback path, producing bit-exact results that will match the future GPU implementation.

## Design Goals

The Vulkan GPU acceleration is designed to mirror the Metal pipeline with these principles:

1. **Cross-Vendor Compatibility**: Supports NVIDIA, AMD, Intel, and ARM Mali GPUs via Vulkan 1.1+
2. **Bit-Exact Results**: GPU and CPU implementations produce identical results
3. **Conditional Compilation**: GPU code gated behind `#if canImport(VulkanSwift)` — CPU fallback always available
4. **CPU Fallback**: Automatic fallback when Vulkan is unavailable or unsupported
5. **Platform Independence**: Shared algorithm logic between Metal and Vulkan pipelines

## Current Architecture

```
Platform/Vulkan/
├── VulkanAccelerator.swift      # Swift API with CPU fallback (implemented)
└── VulkanDevice.swift           # Device selection and capability detection (implemented)
```

**Planned (requires Vulkan SDK):**

```
Platform/Vulkan/Shaders/
├── jpegls_gradients.spv         # SPIR-V gradient + MED prediction shader
├── jpegls_quantize.spv          # SPIR-V gradient quantisation shader
├── jpegls_colour_hp1.spv        # SPIR-V HP1 colour transform shader
├── jpegls_colour_hp2.spv        # SPIR-V HP2 colour transform shader
└── jpegls_colour_hp3.spv        # SPIR-V HP3 colour transform shader
```

## GPU vs CPU Decision

The Vulkan accelerator uses the same threshold-based decision as the Metal implementation:

- **Small images** (< 1024 pixels): Use CPU fallback — GPU overhead exceeds benefit
- **Large images** (≥ 1024 pixels): Use GPU compute — parallelism outweighs transfer cost
- **Batch processing**: GPU preferred for batches of 8+ images regardless of size

## Usage

### Basic Usage

```swift
import JPEGLS

// VulkanAccelerator is available on all platforms (no import guard needed).
// isSupported reflects whether a real Vulkan GPU is found.
let accelerator = VulkanAccelerator()

// Check for GPU availability
if VulkanAccelerator.isSupported {
    print("Vulkan GPU compute available: \(accelerator.device?.name ?? "unknown")")
} else {
    print("No Vulkan GPU found — using CPU fallback")
}

// Compute gradients (GPU when available, CPU fallback otherwise)
let a: [Int32] = // ... north pixel values
let b: [Int32] = // ... west pixel values
let c: [Int32] = // ... northwest pixel values

let (d1, d2, d3) = accelerator.computeGradientsBatch(a: a, b: b, c: c)
let predictions  = accelerator.computeMEDPredictionBatch(a: a, b: b, c: c)

// Quantise gradients to context indices
let (q1, q2, q3) = accelerator.quantizeGradientsBatch(
    d1: d1, d2: d2, d3: d3, t1: 3, t2: 7, t3: 21)

// Apply HP1 colour transform
let (rPrime, gPrime, bPrime) = accelerator.applyColourTransformForwardBatch(
    transform: .hp1, r: rPixels, g: gPixels, b: bPixels)
```

### Device Selection

```swift
import JPEGLS

// List available Vulkan devices (returns [] when no SDK present)
let devices = enumerateVulkanDevices()
for device in devices {
    print("\(device.name): \(device.deviceType)")
}

// Select best device
if let best = selectBestVulkanDevice() {
    print("Selected: \(best.name)")
}
```

## Prerequisites (for GPU Execution)

To enable real GPU acceleration, the following are required:

1. **Vulkan Runtime**: Vulkan 1.1 or later installed
   - Linux: Install via package manager (`apt install libvulkan-dev`)
   - Windows: Install LunarG Vulkan SDK from vulkan.lunarg.com
2. **Vulkan-capable GPU**: Any GPU with Vulkan compute support (NVIDIA, AMD, Intel, ARM Mali)
3. **VulkanSwift package**: A Swift package wrapping the Vulkan API (to be added as a dependency)

```bash
# Linux: Install Vulkan development libraries
sudo apt install libvulkan-dev vulkan-tools

# Verify Vulkan installation
vulkaninfo --summary
```

## Supported Platforms

| Platform  | Vulkan Support | GPU Acceleration |
|-----------|---------------|-----------------|
| Linux x86-64 | ✅ Planned | Vulkan compute |
| Linux ARM64  | ✅ Planned | Vulkan compute |
| Windows x86-64 | ✅ Planned | Vulkan compute |
| macOS | ❌ Not planned | Use Metal instead |
| iOS / iPadOS | ❌ Not planned | Use Metal instead |

## Comparison with Metal

| Feature | Metal (Apple) | Vulkan (Linux/Windows) |
|---------|--------------|----------------------|
| Status | ✅ Implemented | 📋 Planned |
| Platforms | macOS, iOS, tvOS | Linux, Windows |
| API Style | High-level Swift | Low-level C / Swift wrapper |
| Shader Language | MSL | GLSL → SPIR-V |
| Unified Memory | ✅ Apple Silicon | ❌ Discrete GPU only |
| Setup Complexity | Low | Medium |

## Performance Targets

Once implemented, Vulkan acceleration is expected to deliver:

- **Gradient computation**: 4–8× speedup over scalar CPU (large images)
- **MED prediction**: 3–6× speedup
- **Context quantisation**: 2–4× speedup
- **End-to-end encoding**: 2–3× speedup for images ≥ 1 MP

## Development Roadmap

See [MILESTONES.md](MILESTONES.md) **Phase 15.2** for the full implementation plan:

- [ ] Design Vulkan compute pipeline architecture
- [ ] Implement SPIR-V shaders for gradient computation and MED prediction
- [ ] Implement Vulkan memory management and buffer allocation
- [ ] Implement CPU fallback for systems without Vulkan
- [ ] Benchmark against CPU-only on Linux
- [ ] Verify bit-exact results against CPU implementation

## Related Documentation

- [METAL_GPU_ACCELERATION.md](METAL_GPU_ACCELERATION.md) — Metal GPU acceleration (Apple platforms, implemented)
- [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) — General performance optimisation guide
- [MILESTONES.md](MILESTONES.md) — Development roadmap and status

---

**Version**: 1.0 (Draft)  
**Last Updated**: 2026-02-28  
**Status**: Planned — implementation scheduled for Milestone 15
