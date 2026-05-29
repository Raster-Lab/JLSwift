# SwiftUI Integration Examples for JLSwift

This guide demonstrates how to integrate JLSwift JPEG-LS compression into SwiftUI applications for iOS, macOS, and other Apple platforms.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Basic Examples](#basic-examples)
  - [Simple JPEG-LS Image Loader](#simple-jpeg-ls-image-loader)
  - [Async Image Loading with Progress](#async-image-loading-with-progress)
  - [Image Gallery with JPEG-LS](#image-gallery-with-jpeg-ls)
- [Advanced Examples](#advanced-examples)
  - [Medical Image Viewer](#medical-image-viewer)
  - [Multi-Component RGB Display](#multi-component-rgb-display)
  - [Image Inspector with Metadata](#image-inspector-with-metadata)
- [Performance Optimisation](#performance-optimisation)
  - [Caching Decoded Images](#caching-decoded-images)
  - [Background Decoding](#background-decoding)
  - [Memory-Efficient Tile Loading](#memory-efficient-tile-loading)
- [Error Handling](#error-handling)
- [Platform Differences](#platform-differences)

## Overview

JLSwift provides native JPEG-LS decoding capabilities that can be integrated into SwiftUI views. The key steps are:

1. **Load** the JPEG-LS file data
2. **Decode** the image data using `JPEGLSDecoder`
3. **Convert** pixel data to `CGImage`, then to platform-specific image types (`Image` in SwiftUI)

## Prerequisites

Add JLSwift to your project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["JPEGLS"]
    )
]
```

## Basic Examples

### Simple JPEG-LS Image Loader

Create a reusable image conversion utility:

```swift
import Foundation
import JPEGLS
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Utility for converting JPEG-LS files to platform images
enum JPEGLSImageLoader {
    
    /// Load a JPEG-LS file and convert to CGImage
    static func loadCGImage(from url: URL) throws -> CGImage {
        // Load file data
        let data = try Data(contentsOf: url)
        
        // Parse JPEG-LS structure
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        // Decode using the high-level decoder
        let decoder = JPEGLSDecoder()
        let imageData = try decoder.decode(data)
        
        // Convert to CGImage
        return try convertToCGImage(imageData: imageData)
    }
    
    /// Convert decoded image data to CGImage
    private static func convertToCGImage(
        imageData: MultiComponentImageData
    ) throws -> CGImage {
        let width = imageData.frameHeader.width
        let height = imageData.frameHeader.height
        let bitsPerSample = imageData.frameHeader.bitsPerSample
        let componentCount = imageData.frameHeader.componentCount
        
        if componentCount == 1 {
            // Greyscale image
            return try createGrayscaleCGImage(
                pixels: imageData.components[0].pixels,
                width: width,
                height: height,
                bitsPerSample: bitsPerSample
            )
        } else if componentCount == 3 {
            // RGB image
            return try createRGBCGImage(
                red: imageData.components[0].pixels,
                green: imageData.components[1].pixels,
                blue: imageData.components[2].pixels,
                width: width,
                height: height,
                bitsPerSample: bitsPerSample
            )
        } else {
            throw JPEGLSError.invalidComponentCount(count: componentCount)
        }
    }
    
    /// Create a grayscale CGImage from pixel data
    private static func createGrayscaleCGImage(
        pixels: [[Int]],
        width: Int,
        height: Int,
        bitsPerSample: Int
    ) throws -> CGImage {
        // Flatten 2D array to byte array
        var pixelData: [UInt8] = []
        pixelData.reserveCapacity(width * height)
        
        for row in pixels {
            for pixel in row {
                // Clamp to valid range and convert to UInt8
                let clamped = max(0, min((1 << bitsPerSample) - 1, pixel))
                pixelData.append(UInt8(clamped & 0xFF))
            }
        }
        
        // Create CGImage
        guard let dataProvider = CGDataProvider(
            data: NSData(bytes: pixelData, length: pixelData.count)
        ) else {
            throw JPEGLSError.internalError
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: min(bitsPerSample, 8),
            bitsPerPixel: min(bitsPerSample, 8),
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw JPEGLSError.internalError
        }
        
        return cgImage
    }
    
    /// Create an RGB CGImage from component pixel data
    private static func createRGBCGImage(
        red: [[Int]],
        green: [[Int]],
        blue: [[Int]],
        width: Int,
        height: Int,
        bitsPerSample: Int
    ) throws -> CGImage {
        // Interleave RGB components into a single byte array
        var pixelData: [UInt8] = []
        pixelData.reserveCapacity(width * height * 3)
        
        for y in 0..<height {
            for x in 0..<width {
                let r = max(0, min((1 << bitsPerSample) - 1, red[y][x]))
                let g = max(0, min((1 << bitsPerSample) - 1, green[y][x]))
                let b = max(0, min((1 << bitsPerSample) - 1, blue[y][x]))
                
                pixelData.append(UInt8(r & 0xFF))
                pixelData.append(UInt8(g & 0xFF))
                pixelData.append(UInt8(b & 0xFF))
            }
        }
        
        // Create CGImage
        guard let dataProvider = CGDataProvider(
            data: NSData(bytes: pixelData, length: pixelData.count)
        ) else {
            throw JPEGLSError.internalError
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: min(bitsPerSample, 8),
            bitsPerPixel: min(bitsPerSample, 8) * 3,
            bytesPerRow: width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw JPEGLSError.internalError
        }
        
        return cgImage
    }
}
```

Now use it in a SwiftUI view:

```swift
import SwiftUI
import JPEGLS

struct JPEGLSImageView: View {
    let imageURL: URL
    @State private var image: Image?
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .scaledToFit()
            } else if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                ProgressView()
                    .onAppear(perform: loadImage)
            }
        }
    }
    
    private func loadImage() {
        Task {
            do {
                let cgImage = try JPEGLSImageLoader.loadCGImage(from: imageURL)
                await MainActor.run {
                    #if os(macOS)
                    self.image = Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    #else
                    self.image = Image(uiImage: UIImage(cgImage: cgImage))
                    #endif
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
```

### Async Image Loading with Progress

For better UX, show progress during decoding:

```swift
import SwiftUI
import JPEGLS

struct AsyncJPEGLSImageView: View {
    let imageURL: URL
    
    @State private var loadingState: LoadingState = .idle
    
    enum LoadingState {
        case idle
        case loading(progress: Double)
        case loaded(Image)
        case failed(Error)
    }
    
    var body: some View {
        Group {
            switch loadingState {
            case .idle:
                Color.clear.onAppear(perform: loadImage)
                
            case .loading(let progress):
                VStack {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Loading: \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                
            case .loaded(let image):
                image
                    .resizable()
                    .scaledToFit()
                
            case .failed(let error):
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to load image")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
    
    private func loadImage() {
        loadingState = .loading(progress: 0.0)
        
        Task {
            do {
                // Simulate progress updates during loading
                await updateProgress(0.3)
                
                let cgImage = try JPEGLSImageLoader.loadCGImage(from: imageURL)
                
                await updateProgress(1.0)
                
                await MainActor.run {
                    #if os(macOS)
                    self.loadingState = .loaded(Image(nsImage: NSImage(cgImage: cgImage, size: .zero)))
                    #else
                    self.loadingState = .loaded(Image(uiImage: UIImage(cgImage: cgImage)))
                    #endif
                }
            } catch {
                await MainActor.run {
                    self.loadingState = .failed(error)
                }
            }
        }
    }
    
    private func updateProgress(_ progress: Double) async {
        await MainActor.run {
            if case .loading = loadingState {
                loadingState = .loading(progress: progress)
            }
        }
    }
}
```

### Image Gallery with JPEG-LS

Display a grid of JPEG-LS images:

```swift
import SwiftUI
import JPEGLS

struct JPEGLSGalleryView: View {
    let imageURLs: [URL]
    
    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(imageURLs, id: \.self) { url in
                    JPEGLSGalleryThumbnail(imageURL: url)
                }
            }
            .padding()
        }
        .navigationTitle("JPEG-LS Gallery")
    }
}

struct JPEGLSGalleryThumbnail: View {
    let imageURL: URL
    @State private var thumbnail: Image?
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 150)
                    .overlay(ProgressView())
            }
        }
        .onAppear(perform: loadThumbnail)
    }
    
    private func loadThumbnail() {
        Task {
            do {
                let cgImage = try JPEGLSImageLoader.loadCGImage(from: imageURL)
                await MainActor.run {
                    #if os(macOS)
                    self.thumbnail = Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    #else
                    self.thumbnail = Image(uiImage: UIImage(cgImage: cgImage))
                    #endif
                }
            } catch {
                // Handle error silently in thumbnail context
                print("Failed to load thumbnail: \(error)")
            }
        }
    }
}
```

## Advanced Examples

### Medical Image Viewer

A specialised viewer for medical imaging with windowing controls:

```swift
import SwiftUI
import JPEGLS

struct MedicalImageViewer: View {
    let imageURL: URL
    
    @State private var image: CGImage?
    @State private var imageInfo: ImageInfo?
    @State private var windowLevel: Double = 128
    @State private var windowWidth: Double = 256
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    struct ImageInfo {
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
        let near: UInt8
    }
    
    var body: some View {
        VStack {
            // Image display with zoom and pan
            if let image = image {
                GeometryReader { geometry in
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = max(0.5, min(5.0, value))
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = value.translation
                                }
                        )
                }
            } else {
                ProgressView()
                    .onAppear(perform: loadImage)
            }
            
            // Image information
            if let info = imageInfo {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dimensions: \(info.width) × \(info.height)")
                        Text("Bits per sample: \(info.bitsPerSample)")
                        Text("Components: \(info.componentCount)")
                        Text("Encoding: \(info.near == 0 ? "Lossless" : "Near-lossless (NEAR=\(info.near))")")
                    }
                    .font(.caption)
                    Spacer()
                }
                .padding()
            }
            
            // Controls
            Divider()
            VStack {
                HStack {
                    Text("Zoom: \(String(format: "%.1fx", zoom))")
                    Slider(value: $zoom, in: 0.5...5.0)
                    Button("Reset") {
                        zoom = 1.0
                        offset = .zero
                    }
                }
                
                // Window/Level controls for grayscale medical images
                if imageInfo?.componentCount == 1 {
                    HStack {
                        Text("Window Level")
                        Slider(value: $windowLevel, in: 0...255)
                    }
                    HStack {
                        Text("Window Width")
                        Slider(value: $windowWidth, in: 1...512)
                    }
                }
            }
            .padding()
        }
    }
    
    private func loadImage() {
        Task {
            do {
                // Load file data
                let data = try Data(contentsOf: imageURL)
                
                // Parse JPEG-LS structure
                let parser = JPEGLSParser(data: data)
                let parseResult = try parser.parse()
                
                // Extract image information
                let info = ImageInfo(
                    width: Int(parseResult.frameHeader.width),
                    height: Int(parseResult.frameHeader.height),
                    bitsPerSample: Int(parseResult.frameHeader.bitsPerSample),
                    componentCount: Int(parseResult.frameHeader.componentCount),
                    near: parseResult.scanHeaders[0].near
                )
                
                // Load the image
                let cgImage = try JPEGLSImageLoader.loadCGImage(from: imageURL)
                
                await MainActor.run {
                    self.image = cgImage
                    self.imageInfo = info
                    // Set initial window level/width based on bit depth
                    self.windowLevel = Double((1 << info.bitsPerSample) / 2)
                    self.windowWidth = Double(1 << info.bitsPerSample)
                }
            } catch {
                print("Failed to load medical image: \(error)")
            }
        }
    }
}
```

### Multi-Component RGB Display

Display RGB components separately and combined:

```swift
import SwiftUI
import JPEGLS

struct RGBComponentViewer: View {
    let imageURL: URL
    
    @State private var redImage: Image?
    @State private var greenImage: Image?
    @State private var blueImage: Image?
    @State private var combinedImage: Image?
    @State private var selectedView: ComponentView = .combined
    
    enum ComponentView: String, CaseIterable {
        case combined = "Combined"
        case red = "Red"
        case green = "Green"
        case blue = "Blue"
    }
    
    var body: some View {
        VStack {
            // Component selector
            Picker("View", selection: $selectedView) {
                ForEach(ComponentView.allCases, id: \.self) { view in
                    Text(view.rawValue).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Image display
            Group {
                switch selectedView {
                case .combined:
                    if let image = combinedImage {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView().onAppear(perform: loadImages)
                    }
                case .red:
                    if let image = redImage {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                case .green:
                    if let image = greenImage {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                case .blue:
                    if let image = blueImage {
                        image.resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
            }
        }
    }
    
    private func loadImages() {
        Task {
            do {
                // Load and decode JPEG-LS file
                let data = try Data(contentsOf: imageURL)
                
                // Decode using the high-level decoder
                let decoder = JPEGLSDecoder()
                let imageData = try decoder.decode(data)
                
                // Access component pixel data
                let width = imageData.frameHeader.width
                let height = imageData.frameHeader.height
                let bitsPerSample = imageData.frameHeader.bitsPerSample
                
                let redPixels = imageData.components[0].pixels
                let greenPixels = imageData.components[1].pixels
                let bluePixels = imageData.components[2].pixels
                
                // Create grayscale images for each component
                let redCG = try JPEGLSImageLoader.createGrayscaleCGImage(
                    pixels: redPixels, width: width, height: height, bitsPerSample: bitsPerSample
                )
                let greenCG = try JPEGLSImageLoader.createGrayscaleCGImage(
                    pixels: greenPixels, width: width, height: height, bitsPerSample: bitsPerSample
                )
                let blueCG = try JPEGLSImageLoader.createGrayscaleCGImage(
                    pixels: bluePixels, width: width, height: height, bitsPerSample: bitsPerSample
                )
                
                // Create combined RGB image
                let combinedCG = try JPEGLSImageLoader.createRGBCGImage(
                    red: redPixels, green: greenPixels, blue: bluePixels,
                    width: width, height: height, bitsPerSample: bitsPerSample
                )
                
                await MainActor.run {
                    #if os(macOS)
                    self.redImage = Image(nsImage: NSImage(cgImage: redCG, size: .zero))
                    self.greenImage = Image(nsImage: NSImage(cgImage: greenCG, size: .zero))
                    self.blueImage = Image(nsImage: NSImage(cgImage: blueCG, size: .zero))
                    self.combinedImage = Image(nsImage: NSImage(cgImage: combinedCG, size: .zero))
                    #else
                    self.redImage = Image(uiImage: UIImage(cgImage: redCG))
                    self.greenImage = Image(uiImage: UIImage(cgImage: greenCG))
                    self.blueImage = Image(uiImage: UIImage(cgImage: blueCG))
                    self.combinedImage = Image(uiImage: UIImage(cgImage: combinedCG))
                    #endif
                }
            } catch {
                print("Failed to load RGB components: \(error)")
            }
        }
    }
}

// Make methods public for component viewer
extension JPEGLSImageLoader {
    public static func createGrayscaleCGImage(
        pixels: [[Int]],
        width: Int,
        height: Int,
        bitsPerSample: Int
    ) throws -> CGImage {
        // Implementation from above
        var pixelData: [UInt8] = []
        for row in pixels {
            for pixel in row {
                let clamped = max(0, min((1 << bitsPerSample) - 1, pixel))
                pixelData.append(UInt8(clamped & 0xFF))
            }
        }
        
        guard let dataProvider = CGDataProvider(data: NSData(bytes: pixelData, length: pixelData.count)) else {
            throw JPEGLSError.internalError
        }
        
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: min(bitsPerSample, 8),
            bitsPerPixel: min(bitsPerSample, 8),
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw JPEGLSError.internalError
        }
        
        return cgImage
    }
    
    public static func createRGBCGImage(
        red: [[Int]], green: [[Int]], blue: [[Int]],
        width: Int, height: Int, bitsPerSample: Int
    ) throws -> CGImage {
        // Implementation from above
        var pixelData: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let r = max(0, min((1 << bitsPerSample) - 1, red[y][x]))
                let g = max(0, min((1 << bitsPerSample) - 1, green[y][x]))
                let b = max(0, min((1 << bitsPerSample) - 1, blue[y][x]))
                pixelData.append(UInt8(r & 0xFF))
                pixelData.append(UInt8(g & 0xFF))
                pixelData.append(UInt8(b & 0xFF))
            }
        }
        
        guard let dataProvider = CGDataProvider(data: NSData(bytes: pixelData, length: pixelData.count)) else {
            throw JPEGLSError.internalError
        }
        
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: min(bitsPerSample, 8),
            bitsPerPixel: min(bitsPerSample, 8) * 3,
            bytesPerRow: width * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw JPEGLSError.internalError
        }
        
        return cgImage
    }
}
```

### Image Inspector with Metadata

Display comprehensive JPEG-LS file information:

```swift
import SwiftUI
import JPEGLS

struct JPEGLSInspectorView: View {
    let imageURL: URL
    
    @State private var metadata: JPEGLSMetadata?
    @State private var image: Image?
    
    struct JPEGLSMetadata {
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
        let interleaveMode: JPEGLSInterleaveMode
        let near: UInt8
        let pointTransform: UInt8
        let colorTransformation: JPEGLSColorTransformation
        let presetParameters: JPEGLSPresetParameters?
        let fileSize: Int64
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image preview
                if let image = image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .background(Color.gray.opacity(0.1))
                } else {
                    ProgressView()
                        .frame(height: 300)
                        .onAppear(perform: loadData)
                }
                
                // Metadata sections
                if let metadata = metadata {
                    metadataSection(title: "Image Information") {
                        metadataRow(label: "Dimensions", value: "\(metadata.width) × \(metadata.height)")
                        metadataRow(label: "Bits per sample", value: "\(metadata.bitsPerSample)")
                        metadataRow(label: "Components", value: "\(metadata.componentCount)")
                        metadataRow(label: "File size", value: formatFileSize(metadata.fileSize))
                    }
                    
                    metadataSection(title: "Encoding Parameters") {
                        metadataRow(label: "Interleave mode", value: metadata.interleaveMode.description)
                        metadataRow(label: "Encoding", value: metadata.near == 0 ? "Lossless" : "Near-lossless (NEAR=\(metadata.near))")
                        metadataRow(label: "Point transform", value: "\(metadata.pointTransform)")
                        metadataRow(label: "Color transform", value: metadata.colorTransformation.description)
                    }
                    
                    if let preset = metadata.presetParameters {
                        metadataSection(title: "Preset Parameters") {
                            metadataRow(label: "MAXVAL", value: "\(preset.maxval)")
                            metadataRow(label: "T1", value: "\(preset.t1)")
                            metadataRow(label: "T2", value: "\(preset.t2)")
                            metadataRow(label: "T3", value: "\(preset.t3)")
                            metadataRow(label: "RESET", value: "\(preset.reset)")
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Image Inspector")
    }
    
    private func metadataSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    private func loadData() {
        Task {
            do {
                // Load file
                let data = try Data(contentsOf: imageURL)
                let fileSize = Int64(data.count)
                
                // Parse JPEG-LS
                let parser = JPEGLSParser(data: data)
                let parseResult = try parser.parse()
                
                // Extract metadata
                let frameHeader = parseResult.frameHeader
                let scanHeader = parseResult.scanHeaders[0]
                
                let metadata = JPEGLSMetadata(
                    width: Int(frameHeader.width),
                    height: Int(frameHeader.height),
                    bitsPerSample: Int(frameHeader.bitsPerSample),
                    componentCount: Int(frameHeader.componentCount),
                    interleaveMode: scanHeader.interleaveMode,
                    near: scanHeader.near,
                    pointTransform: scanHeader.pointTransform,
                    colorTransformation: .none,
                    presetParameters: parseResult.presetParameters,
                    fileSize: fileSize
                )
                
                // Load image
                let cgImage = try JPEGLSImageLoader.loadCGImage(from: imageURL)
                
                await MainActor.run {
                    self.metadata = metadata
                    #if os(macOS)
                    self.image = Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                    #else
                    self.image = Image(uiImage: UIImage(cgImage: cgImage))
                    #endif
                }
            } catch {
                print("Failed to load metadata: \(error)")
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// Extension to make interleave mode printable
extension JPEGLSInterleaveMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none: return "None (separate scans)"
        case .line: return "Line-interleaved"
        case .sample: return "Sample-interleaved"
        }
    }
}

extension JPEGLSColorTransformation: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none: return "None"
        case .hp1: return "HP1"
        case .hp2: return "HP2"
        case .hp3: return "HP3"
        }
    }
}
```

## Performance Optimisation

### Caching Decoded Images

Implement a simple cache to avoid redundant decoding:

```swift
import Foundation
import JPEGLS

actor JPEGLSImageCache {
    private var cache: [URL: CGImage] = [:]
    private let maxCacheSize = 50
    
    func getImage(for url: URL) -> CGImage? {
        return cache[url]
    }
    
    func setImage(_ image: CGImage, for url: URL) {
        // Simple LRU eviction
        if cache.count >= maxCacheSize {
            let oldestKey = cache.keys.first!
            cache.removeValue(forKey: oldestKey)
        }
        cache[url] = image
    }
    
    func clearCache() {
        cache.removeAll()
    }
}

// Usage in your image loader
extension JPEGLSImageLoader {
    static let cache = JPEGLSImageCache()
    
    static func loadCGImageWithCache(from url: URL) async throws -> CGImage {
        // Check cache first
        if let cached = await cache.getImage(for: url) {
            return cached
        }
        
        // Load and decode
        let image = try loadCGImage(from: url)
        
        // Cache for next time
        await cache.setImage(image, for: url)
        
        return image
    }
}
```

### Background Decoding

Decode images on background threads to keep UI responsive:

```swift
import SwiftUI
import JPEGLS

struct BackgroundDecodingImageView: View {
    let imageURL: URL
    @State private var image: Image?
    
    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .task {
                        await loadImageInBackground()
                    }
            }
        }
    }
    
    private func loadImageInBackground() async {
        // Decode on background thread
        let cgImage = await Task.detached(priority: .userInitiated) {
            try? JPEGLSImageLoader.loadCGImage(from: imageURL)
        }.value
        
        guard let cgImage = cgImage else { return }
        
        // Update UI on main thread
        await MainActor.run {
            #if os(macOS)
            self.image = Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
            #else
            self.image = Image(uiImage: UIImage(cgImage: cgImage))
            #endif
        }
    }
}
```

### Memory-Efficient Tile Loading

For very large medical images, use tile-based loading:

```swift
import SwiftUI
import JPEGLS

struct TiledImageView: View {
    let imageURL: URL
    let tileSize: Int = 512
    
    @State private var tiles: [TileInfo] = []
    
    struct TileInfo: Identifiable {
        let id = UUID()
        let rect: CGRect
        var image: Image?
    }
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for tile in tiles {
                    if let image = tile.image {
                        // Draw tile at its position
                        context.draw(image, in: tile.rect)
                    }
                }
            }
            .onAppear {
                loadTiles()
            }
        }
    }
    
    private func loadTiles() {
        Task {
            do {
                // Load file metadata
                let data = try Data(contentsOf: imageURL)
                let parser = JPEGLSParser(data: data)
                let parseResult = try parser.parse()
                
                let width = Int(parseResult.frameHeader.width)
                let height = Int(parseResult.frameHeader.height)
                
                // Calculate tile layout
                let tileProcessor = JPEGLSTileProcessor(
                    imageWidth: width,
                    imageHeight: height,
                    configuration: TileConfiguration(
                        tileWidth: tileSize,
                        tileHeight: tileSize,
                        overlap: 0
                    )
                )
                
                let tileRects = tileProcessor.calculateTiles()
                
                // Create tile info
                await MainActor.run {
                    tiles = tileRects.map { rect in
                        TileInfo(rect: CGRect(
                            x: CGFloat(rect.x),
                            y: CGFloat(rect.y),
                            width: CGFloat(rect.width),
                            height: CGFloat(rect.height)
                        ))
                    }
                }
                
                // Load tiles progressively
                for index in tiles.indices {
                    // In a real implementation, you would decode only the tile region
                    // This is a simplified example
                    try await Task.sleep(nanoseconds: 100_000_000) // Simulate load
                }
            } catch {
                print("Failed to load tiles: \(error)")
            }
        }
    }
}
```

## Error Handling

Robust error handling for production apps:

```swift
import SwiftUI
import JPEGLS

enum ImageLoadError: LocalizedError {
    case fileNotFound
    case invalidFormat
    case decodingFailed(underlying: Error)
    case unsupportedConfiguration(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Image file not found"
        case .invalidFormat:
            return "Invalid JPEG-LS format"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .unsupportedConfiguration(let details):
            return "Unsupported configuration: \(details)"
        }
    }
}

extension JPEGLSImageLoader {
    static func loadCGImageSafely(from url: URL) throws -> CGImage {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageLoadError.fileNotFound
        }
        
        do {
            return try loadCGImage(from: url)
        } catch let error as JPEGLSError {
            // Handle specific JPEG-LS errors
            throw ImageLoadError.decodingFailed(underlying: error)
        } catch {
            // Handle generic errors
            throw ImageLoadError.decodingFailed(underlying: error)
        }
    }
}
```

## Platform Differences

### iOS/iPadOS Considerations

```swift
#if os(iOS)
import UIKit

// Use UIImage for iOS
extension Image {
    init(jpegLSURL url: URL) throws {
        let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
        let uiImage = UIImage(cgImage: cgImage)
        self.init(uiImage: uiImage)
    }
}
#endif
```

### macOS Considerations

```swift
#if os(macOS)
import AppKit

// Use NSImage for macOS
extension Image {
    init(jpegLSURL url: URL) throws {
        let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        self.init(nsImage: nsImage)
    }
}

// Support drag and drop
struct JPEGLSDropView: View {
    @State private var image: Image?
    
    var body: some View {
        Group {
            if let image = image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Text("Drop a JPEG-LS file here")
                    .frame(width: 400, height: 300)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                Task {
                    do {
                        let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
                        await MainActor.run {
                            self.image = Image(nsImage: NSImage(cgImage: cgImage, size: .zero))
                        }
                    } catch {
                        print("Failed to load dropped image: \(error)")
                    }
                }
            }
            
            return true
        }
    }
}
#endif
```

## Next Steps

- Explore [APPKIT_EXAMPLES.md](APPKIT_EXAMPLES.md) for AppKit-specific integration patterns
- See [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) for general library usage
- Refer to [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) for optimisation strategies
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Notes

**Important**: Some examples above use placeholder code for bitstream decoding, which is currently under development (see MILESTONES.md Phase 7.1). Once bitstream integration is complete, the decoder will be able to read compressed pixel data directly from JPEG-LS files. The architecture and API patterns shown here are production-ready and will work with minimal modifications once the bitstream integration is finished.
