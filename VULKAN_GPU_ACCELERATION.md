# Vulkan GPU Compute Acceleration

## Overview

JLSwift includes planned support for GPU acceleration via the Vulkan compute API on Linux and Windows platforms. Vulkan compute shaders provide cross-vendor GPU parallelism for JPEG-LS encoding operations, complementing the Metal GPU support available on Apple platforms.

> **Status**: Planned (Phase 15.2). Vulkan compute support is not yet implemented. This document describes the planned architecture and usage patterns.

## Design Goals

The Vulkan GPU acceleration is designed to mirror the Metal pipeline with these principles:

1. **Cross-Vendor Compatibility**: Supports NVIDIA, AMD, Intel, and ARM Mali GPUs via Vulkan 1.1+
2. **Bit-Exact Results**: GPU and CPU implementations produce identical results
3. **Conditional Compilation**: Compiled only when Vulkan headers are available
4. **CPU Fallback**: Automatic fallback when Vulkan is unavailable or unsupported
5. **Platform Independence**: Shared algorithm logic between Metal and Vulkan pipelines

## Planned Architecture

```
Platform/Vulkan/
├── VulkanAccelerator.swift      # Swift API wrapping Vulkan compute
├── VulkanDevice.swift           # Device selection and capability detection
├── VulkanBuffers.swift          # GPU buffer management and host–device transfer
└── Shaders/
    ├── jpegls_gradient.spv      # SPIR-V gradient computation shader
    ├── jpegls_prediction.spv    # SPIR-V MED prediction shader
    └── jpegls_encode.spv        # SPIR-V encoding pipeline shader
```

## GPU vs CPU Decision

The Vulkan accelerator will use the same threshold-based decision as the Metal implementation:

- **Small images** (< 1024 pixels): Use CPU fallback — GPU overhead exceeds benefit
- **Large images** (≥ 1024 pixels): Use GPU compute — parallelism outweighs transfer cost
- **Batch processing**: GPU preferred for batches of 8+ images regardless of size

## Planned Usage

### Basic Usage (Planned)

```swift
#if canImport(VulkanSwift)
import VulkanSwift

// Check Vulkan availability
guard VulkanAccelerator.isSupported else {
    print("Vulkan not available, using CPU fallback")
    return
}

// Create accelerator with automatic device selection
let accelerator = try VulkanAccelerator()

// Use for gradient computation
let (d1, d2, d3) = accelerator.computeGradients(a: 100, b: 110, c: 105)
print("Gradients: D1=\(d1), D2=\(d2), D3=\(d3)")
#endif
```

### Encoding with Vulkan Acceleration (Planned)

```swift
import JPEGLS

// Encoding always uses the best available accelerator automatically
// No code changes needed — Vulkan acceleration is transparent
let encoder = JPEGLSEncoder()
let jpegLSData = try encoder.encode(imageData)
```

### Device Selection (Planned)

```swift
#if canImport(VulkanSwift)
import VulkanSwift

// List available Vulkan devices
let devices = try VulkanDevice.enumerateDevices()
for device in devices {
    print("\(device.name): \(device.deviceType), \(device.memoryMB) MB VRAM")
}

// Select a specific device (by default, the highest-performance device is chosen)
let selectedDevice = devices.first { $0.deviceType == .discreteGPU }
let accelerator = try VulkanAccelerator(device: selectedDevice)
#endif
```

## Prerequisites (When Implemented)

To use Vulkan GPU acceleration, the following are required:

1. **Vulkan Runtime**: Vulkan 1.1 or later installed
   - Linux: Install via package manager (`apt install libvulkan-dev`)
   - Windows: Install LunarG Vulkan SDK from vulkan.lunarg.com
2. **Vulkan-capable GPU**: Any GPU with Vulkan compute support (NVIDIA, AMD, Intel, ARM Mali)
3. **SPIR-V Compiler**: For building shader binaries (glslc or glslangValidator)

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
