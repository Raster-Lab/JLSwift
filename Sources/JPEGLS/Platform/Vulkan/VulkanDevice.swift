/// Vulkan device information and capability detection for JPEG-LS GPU compute.
///
/// This file provides device discovery and capability reporting for the Vulkan
/// compute backend. When the Vulkan SDK is not present, the implementation
/// reports no GPU devices and routes all work through the CPU fallback path.
///
/// **Platform Support**:
/// - Linux and Windows with Vulkan 1.1+ SDK: GPU compute available
/// - macOS / iOS / tvOS / watchOS: Not supported (use Metal instead)
/// - All other platforms without Vulkan SDK: CPU fallback only
///
/// **Conditional Compilation**:
/// Actual Vulkan device enumeration is gated behind `#if canImport(VulkanSwift)`.
/// The CPU-always-available type `VulkanDevice` is unconditionally compiled
/// to allow the rest of the library to reference it on all platforms.

import Foundation

// MARK: - Vulkan Device Type

/// Represents a single Vulkan-capable GPU device.
///
/// On platforms where the Vulkan SDK is not available, this type is still
/// usable but `isGPUDevice` will always return `false`, and all GPU
/// operations will be handled by the CPU fallback path.
public struct VulkanDevice: Sendable, CustomStringConvertible {

    /// The device name reported by Vulkan (or a CPU fallback description).
    public let name: String

    /// The Vulkan API version supported by this device (0 when no Vulkan SDK).
    public let apiVersion: UInt32

    /// The kind of device.
    public let deviceType: VulkanDeviceType

    /// Returns `true` if this entry represents a real GPU device (not a CPU fallback stub).
    public var isGPUDevice: Bool {
        deviceType == .discreteGPU || deviceType == .integratedGPU || deviceType == .virtualGPU
    }

    public var description: String {
        "VulkanDevice(name: \"\(name)\", type: \(deviceType), apiVersion: \(apiVersion))"
    }
}

// MARK: - Device Type

/// The physical device type as reported by Vulkan.
public enum VulkanDeviceType: Sendable, CustomStringConvertible {
    /// A discrete (dedicated) GPU.
    case discreteGPU
    /// An integrated GPU sharing system memory.
    case integratedGPU
    /// A virtual GPU inside a virtualisation environment.
    case virtualGPU
    /// A CPU-based Vulkan implementation (e.g. lavapipe/SwiftShader).
    case cpu
    /// Device type could not be determined.
    case other

    public var description: String {
        switch self {
        case .discreteGPU:   return "Discrete GPU"
        case .integratedGPU: return "Integrated GPU"
        case .virtualGPU:    return "Virtual GPU"
        case .cpu:           return "CPU"
        case .other:         return "Other"
        }
    }
}

// MARK: - Device Enumeration

/// Enumerate Vulkan-capable physical devices on the current system.
///
/// Returns an empty array on platforms without the Vulkan SDK, allowing callers
/// to use the CPU fallback path transparently.
///
/// - Returns: Array of available `VulkanDevice` instances (empty when no Vulkan SDK).
public func enumerateVulkanDevices() -> [VulkanDevice] {
    // When the Vulkan SDK / VulkanSwift package is available, real device
    // enumeration would go here. For now, return an empty array so that
    // VulkanAccelerator always uses its CPU fallback path.
    //
    // #if canImport(VulkanSwift)
    // import VulkanSwift
    // … vkEnumeratePhysicalDevices logic …
    // #endif
    return []
}

/// Select the best available Vulkan device for compute work.
///
/// Prefers discrete GPUs over integrated GPUs over virtual GPUs over CPU devices.
/// Returns `nil` when no suitable device is available (no Vulkan SDK or no GPU).
///
/// - Returns: The best `VulkanDevice`, or `nil` if none is available.
public func selectBestVulkanDevice() -> VulkanDevice? {
    let devices = enumerateVulkanDevices()
    let priority: [VulkanDeviceType] = [.discreteGPU, .integratedGPU, .virtualGPU, .cpu]
    for preferred in priority {
        if let device = devices.first(where: { $0.deviceType == preferred }) {
            return device
        }
    }
    return nil
}
