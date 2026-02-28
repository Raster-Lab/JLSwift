# AppKit Integration Examples for JLSwift

This guide demonstrates how to integrate JLSwift JPEG-LS compression into AppKit applications for macOS.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Basic Examples](#basic-examples)
  - [Loading JPEG-LS into NSImage](#loading-jpeg-ls-into-nsimage)
  - [NSImageView Integration](#nsimageview-integration)
  - [Custom NSView with Direct Rendering](#custom-nsview-with-direct-rendering)
- [Document-Based Applications](#document-based-applications)
  - [NSDocument Subclass](#nsdocument-subclass)
  - [Document Type Registration](#document-type-registration)
  - [Quick Look Preview](#quick-look-preview)
- [Image Processing UI](#image-processing-ui)
  - [Batch Processor Window](#batch-processor-window)
  - [Progress Indicators](#progress-indicators)
  - [Error Handling Dialog](#error-handling-dialog)
- [Medical Image Viewing](#medical-image-viewing)
  - [DICOM-Style Viewer](#dicom-style-viewer)
  - [Window/Level Adjustment](#windowlevel-adjustment)
  - [Measurement Tools](#measurement-tools)
- [Performance Optimisation](#performance-optimisation)
  - [Background Loading](#background-loading)
  - [Thumbnail Generation](#thumbnail-generation)
  - [Memory Management](#memory-management)

## Overview

JLSwift integrates seamlessly with AppKit for macOS applications. The key integration points are:

1. **NSImage** - Standard macOS image container
2. **NSImageView** - Built-in image display view
3. **NSDocument** - Document-based app architecture
4. **Custom NSView** - For advanced rendering and interaction

## Prerequisites

Add JLSwift to your macOS project's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourMacApp",
        dependencies: ["JPEGLS"]
    )
]
```

## Basic Examples

### Loading JPEG-LS into NSImage

Create a utility class for JPEG-LS to NSImage conversion:

```swift
import Cocoa
import JPEGLS

class JPEGLSImageLoader {
    
    /// Load a JPEG-LS file and convert to NSImage
    static func loadImage(from url: URL) throws -> NSImage {
        let cgImage = try loadCGImage(from: url)
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    /// Load a JPEG-LS file and convert to CGImage
    static func loadCGImage(from url: URL) throws -> CGImage {
        // Load file data
        let data = try Data(contentsOf: url)
        
        // Parse JPEG-LS structure
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        // Create decoder
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: parseResult.frameHeader,
            scanHeader: parseResult.scanHeaders[0],
            colorTransformation: .none
        )
        
        // Create pixel buffer from parsed data
        // Note: Full bitstream decoding integration is pending
        let imageData = try MultiComponentImageData.grayscale(
            pixels: [[0]], // Placeholder
            bitsPerSample: Int(parseResult.frameHeader.bitsPerSample)
        )
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        
        // Decode the scan
        _ = try decoder.decodeScan(buffer: buffer)
        
        // Reconstruct components
        let reconstructed = try decoder.reconstructComponents(from: buffer)
        
        // Convert to CGImage
        return try convertToCGImage(
            reconstructed: reconstructed,
            frameHeader: parseResult.frameHeader
        )
    }
    
    /// Convert reconstructed components to CGImage
    private static func convertToCGImage(
        reconstructed: ReconstructedComponents,
        frameHeader: JPEGLSFrameHeader
    ) throws -> CGImage {
        let width = reconstructed.width
        let height = reconstructed.height
        let bitsPerSample = Int(frameHeader.bitsPerSample)
        let componentCount = Int(frameHeader.componentCount)
        
        if componentCount == 1 {
            return try createGrayscaleCGImage(
                pixels: reconstructed.getPixels(componentId: 1)!,
                width: width,
                height: height,
                bitsPerSample: bitsPerSample
            )
        } else if componentCount == 3 {
            let red = reconstructed.getPixels(componentId: 1)!
            let green = reconstructed.getPixels(componentId: 2)!
            let blue = reconstructed.getPixels(componentId: 3)!
            
            return try createRGBCGImage(
                red: red,
                green: green,
                blue: blue,
                width: width,
                height: height,
                bitsPerSample: bitsPerSample
            )
        } else {
            throw JPEGLSError.invalidComponentCount
        }
    }
    
    private static func createGrayscaleCGImage(
        pixels: [[Int]],
        width: Int,
        height: Int,
        bitsPerSample: Int
    ) throws -> CGImage {
        var pixelData: [UInt8] = []
        pixelData.reserveCapacity(width * height)
        
        for row in pixels {
            for pixel in row {
                let clamped = max(0, min((1 << bitsPerSample) - 1, pixel))
                pixelData.append(UInt8(clamped & 0xFF))
            }
        }
        
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
    
    private static func createRGBCGImage(
        red: [[Int]],
        green: [[Int]],
        blue: [[Int]],
        width: Int,
        height: Int,
        bitsPerSample: Int
    ) throws -> CGImage {
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

### NSImageView Integration

Simple image viewer using NSImageView:

```swift
import Cocoa
import JPEGLS

class SimpleImageViewController: NSViewController {
    
    private let imageView = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    private let errorLabel = NSTextField()
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
    }
    
    private func setupUI() {
        // Configure image view
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)
        
        // Configure progress indicator
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.isHidden = true
        view.addSubview(progressIndicator)
        
        // Configure error label
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isEditable = false
        errorLabel.isBordered = false
        errorLabel.backgroundColor = .clear
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            progressIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    func loadImage(from url: URL) {
        imageView.image = nil
        errorLabel.isHidden = true
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let image = try JPEGLSImageLoader.loadImage(from: url)
                
                DispatchQueue.main.async {
                    self?.imageView.image = image
                    self?.progressIndicator.stopAnimation(nil)
                    self?.progressIndicator.isHidden = true
                }
            } catch {
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(nil)
                    self?.progressIndicator.isHidden = true
                    self?.errorLabel.stringValue = "Failed to load image: \(error.localizedDescription)"
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }
}
```

### Custom NSView with Direct Rendering

For advanced control over rendering:

```swift
import Cocoa
import JPEGLS

class JPEGLSImageView: NSView {
    
    private var cgImage: CGImage?
    private var zoomLevel: CGFloat = 1.0
    private var offset: CGPoint = .zero
    
    override var isFlipped: Bool { true }
    
    func setImage(_ image: CGImage) {
        self.cgImage = image
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = cgImage else {
            return
        }
        
        // Calculate scaled image rect
        let imageWidth = CGFloat(image.width) * zoomLevel
        let imageHeight = CGFloat(image.height) * zoomLevel
        
        let x = (bounds.width - imageWidth) / 2 + offset.x
        let y = (bounds.height - imageHeight) / 2 + offset.y
        
        let imageRect = CGRect(x: x, y: y, width: imageWidth, height: imageHeight)
        
        // Draw the image
        context.draw(image, in: imageRect)
    }
    
    func zoom(by factor: CGFloat) {
        zoomLevel *= factor
        zoomLevel = max(0.1, min(10.0, zoomLevel))
        needsDisplay = true
    }
    
    func pan(by delta: CGPoint) {
        offset.x += delta.x
        offset.y += delta.y
        needsDisplay = true
    }
    
    func resetView() {
        zoomLevel = 1.0
        offset = .zero
        needsDisplay = true
    }
    
    // Mouse event handling
    private var lastDragLocation: NSPoint?
    
    override func mouseDown(with event: NSEvent) {
        lastDragLocation = convert(event.locationInWindow, from: nil)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentLocation = convert(event.locationInWindow, from: nil)
        
        if let lastLocation = lastDragLocation {
            let delta = CGPoint(
                x: currentLocation.x - lastLocation.x,
                y: currentLocation.y - lastLocation.y
            )
            pan(by: delta)
        }
        
        lastDragLocation = currentLocation
    }
    
    override func scrollWheel(with event: NSEvent) {
        let zoomFactor = 1.0 + (event.deltaY * 0.01)
        zoom(by: zoomFactor)
    }
}
```

## Document-Based Applications

### NSDocument Subclass

Create a document type for JPEG-LS files:

```swift
import Cocoa
import JPEGLS

class JPEGLSDocument: NSDocument {
    
    var image: NSImage?
    var metadata: JPEGLSMetadata?
    
    struct JPEGLSMetadata {
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
        let interleaveMode: JPEGLSInterleaveMode
        let near: UInt8
        let fileSize: Int64
    }
    
    override class var autosavesInPlace: Bool {
        return false // JPEG-LS is read-only in this example
    }
    
    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(
            withIdentifier: "JPEGLSWindowController"
        ) as! NSWindowController
        
        addWindowController(windowController)
        
        // Set the document content
        if let viewController = windowController.contentViewController as? JPEGLSViewController {
            viewController.image = image
            viewController.metadata = metadata
        }
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        // Load the JPEG-LS file
        let data = try Data(contentsOf: url)
        
        // Parse JPEG-LS structure
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        // Extract metadata
        let frameHeader = parseResult.frameHeader
        let scanHeader = parseResult.scanHeaders[0]
        
        metadata = JPEGLSMetadata(
            width: Int(frameHeader.width),
            height: Int(frameHeader.height),
            bitsPerSample: Int(frameHeader.bitsPerSample),
            componentCount: Int(frameHeader.componentCount),
            interleaveMode: scanHeader.interleaveMode,
            near: scanHeader.near,
            fileSize: Int64(data.count)
        )
        
        // Load the image
        image = try JPEGLSImageLoader.loadImage(from: url)
    }
}

class JPEGLSViewController: NSViewController {
    
    @IBOutlet weak var imageView: NSImageView!
    @IBOutlet weak var infoLabel: NSTextField!
    
    var image: NSImage? {
        didSet {
            if isViewLoaded {
                imageView.image = image
            }
        }
    }
    
    var metadata: JPEGLSDocument.JPEGLSMetadata? {
        didSet {
            if isViewLoaded {
                updateInfoLabel()
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        imageView.image = image
        updateInfoLabel()
    }
    
    private func updateInfoLabel() {
        guard let metadata = metadata else {
            infoLabel.stringValue = ""
            return
        }
        
        let encoding = metadata.near == 0 ? "Lossless" : "Near-lossless (NEAR=\(metadata.near))"
        infoLabel.stringValue = """
            \(metadata.width) × \(metadata.height) pixels, \
            \(metadata.bitsPerSample)-bit, \
            \(metadata.componentCount) component(s), \
            \(encoding)
            """
    }
    
    @IBAction func zoomIn(_ sender: Any) {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        // Implement custom zoom if needed
    }
    
    @IBAction func zoomOut(_ sender: Any) {
        imageView.imageScaling = .scaleAxesIndependently
        // Implement custom zoom if needed
    }
    
    @IBAction func actualSize(_ sender: Any) {
        imageView.imageScaling = .scaleNone
    }
}
```

### Document Type Registration

Add to your `Info.plist`:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>jls</string>
            <string>jpegls</string>
        </array>
        <key>CFBundleTypeName</key>
        <string>JPEG-LS Image</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.example.jpegls</string>
        </array>
        <key>NSDocumentClass</key>
        <string>$(PRODUCT_MODULE_NAME).JPEGLSDocument</string>
    </dict>
</array>

<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
            <string>public.image</string>
        </array>
        <key>UTTypeDescription</key>
        <string>JPEG-LS Image</string>
        <key>UTTypeIdentifier</key>
        <string>com.example.jpegls</string>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>jls</string>
                <string>jpegls</string>
            </array>
        </dict>
    </dict>
</array>
```

### Quick Look Preview

Implement Quick Look preview generation:

```swift
import Cocoa
import Quartz
import JPEGLS

class JPEGLSPreviewProvider: QLPreviewProvider {
    
    override func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        
        // Load the JPEG-LS image
        let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
        
        let contentSize = CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
        
        return QLPreviewReply(
            contextSize: contentSize,
            isBitmap: true,
            drawUsing: { context, _ in
                context.draw(
                    cgImage,
                    in: CGRect(origin: .zero, size: contentSize)
                )
                return true
            }
        )
    }
}
```

## Image Processing UI

### Batch Processor Window

Process multiple JPEG-LS files:

```swift
import Cocoa
import JPEGLS

class BatchProcessorWindowController: NSWindowController {
    
    @IBOutlet weak var fileListTableView: NSTableView!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    
    private var fileURLs: [URL] = []
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        fileListTableView.dataSource = self
        fileListTableView.delegate = self
        
        updateUI()
    }
    
    @IBAction func addFiles(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [.init(filenameExtension: "jls")!]
        
        openPanel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.fileURLs.append(contentsOf: openPanel.urls)
            self?.fileListTableView.reloadData()
            self?.updateUI()
        }
    }
    
    @IBAction func removeFiles(_ sender: Any) {
        let selectedRows = fileListTableView.selectedRowIndexes
        fileURLs.remove(atOffsets: IndexSet(selectedRows))
        fileListTableView.reloadData()
        updateUI()
    }
    
    @IBAction func startProcessing(_ sender: Any) {
        guard !fileURLs.isEmpty else { return }
        
        isProcessing = true
        updateUI()
        
        processingTask = Task { [weak self] in
            await self?.processFiles()
        }
    }
    
    @IBAction func cancelProcessing(_ sender: Any) {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        updateUI()
    }
    
    private func processFiles() async {
        let total = fileURLs.count
        
        await MainActor.run {
            progressBar.minValue = 0
            progressBar.maxValue = Double(total)
            progressBar.doubleValue = 0
        }
        
        for (index, url) in fileURLs.enumerated() {
            guard !Task.isCancelled else { break }
            
            await MainActor.run {
                statusLabel.stringValue = "Processing \(url.lastPathComponent)..."
                progressBar.doubleValue = Double(index)
            }
            
            // Process the file
            do {
                _ = try JPEGLSImageLoader.loadImage(from: url)
                // Perform your processing here
                try await Task.sleep(nanoseconds: 500_000_000) // Simulate work
            } catch {
                NSLog("Failed to process \(url.lastPathComponent): \(error)")
            }
        }
        
        await MainActor.run {
            progressBar.doubleValue = Double(total)
            statusLabel.stringValue = "Processing complete"
            isProcessing = false
            updateUI()
        }
    }
    
    private func updateUI() {
        startButton.isEnabled = !fileURLs.isEmpty && !isProcessing
        cancelButton.isEnabled = isProcessing
        fileListTableView.isEnabled = !isProcessing
    }
}

extension BatchProcessorWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return fileURLs.count
    }
}

extension BatchProcessorWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("FileCell"),
            owner: self
        ) as? NSTableCellView ?? NSTableCellView()
        
        cell.textField?.stringValue = fileURLs[row].lastPathComponent
        return cell
    }
}
```

### Progress Indicators

Custom progress view for long operations:

```swift
import Cocoa

class ProgressWindowController: NSWindowController {
    
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var detailLabel: NSTextField!
    
    private var currentProgress: Double = 0
    private var totalProgress: Double = 100
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        progressBar.minValue = 0
        progressBar.maxValue = totalProgress
    }
    
    func setProgress(_ current: Double, total: Double, status: String, detail: String = "") {
        DispatchQueue.main.async { [weak self] in
            self?.currentProgress = current
            self?.totalProgress = total
            self?.progressBar.maxValue = total
            self?.progressBar.doubleValue = current
            self?.statusLabel.stringValue = status
            self?.detailLabel.stringValue = detail
        }
    }
}
```

### Error Handling Dialog

User-friendly error presentation:

```swift
import Cocoa
import JPEGLS

extension NSViewController {
    
    func showJPEGLSError(_ error: Error, for url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Failed to load JPEG-LS image"
        
        if let jpegError = error as? JPEGLSError {
            alert.informativeText = formatJPEGLSError(jpegError, url: url)
        } else {
            alert.informativeText = """
                File: \(url.lastPathComponent)
                Error: \(error.localizedDescription)
                """
        }
        
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: view.window!)
    }
    
    private func formatJPEGLSError(_ error: JPEGLSError, url: URL) -> String {
        var message = "File: \(url.lastPathComponent)\n\n"
        
        switch error {
        case .invalidMarker:
            message += "The file does not appear to be a valid JPEG-LS image.\nExpected Start of Image (SOI) marker not found."
        case .invalidComponentCount:
            message += "The image has an unsupported number of components."
        case .invalidParameter:
            message += "The JPEG-LS parameters in this file are invalid."
        case .invalidFrameHeader:
            message += "The frame header in this file is corrupted or invalid."
        case .invalidScanHeader:
            message += "The scan header in this file is corrupted or invalid."
        case .bitstreamError:
            message += "The compressed bitstream data is corrupted."
        default:
            message += "An error occurred: \(error.localizedDescription)"
        }
        
        return message
    }
}
```

## Medical Image Viewing

### DICOM-Style Viewer

Professional medical image viewer:

```swift
import Cocoa
import JPEGLS

class MedicalImageViewController: NSViewController {
    
    @IBOutlet weak var imageView: JPEGLSImageView!
    @IBOutlet weak var windowLevelSlider: NSSlider!
    @IBOutlet weak var windowWidthSlider: NSSlider!
    @IBOutlet weak var infoPanel: NSView!
    @IBOutlet weak var dimensionsLabel: NSTextField!
    @IBOutlet weak var bitsLabel: NSTextField!
    @IBOutlet weak var encodingLabel: NSTextField!
    
    private var originalImage: CGImage?
    private var metadata: ImageMetadata?
    
    struct ImageMetadata {
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let componentCount: Int
        let near: UInt8
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSliders()
    }
    
    func loadImage(from url: URL) {
        do {
            // Load file data
            let data = try Data(contentsOf: url)
            
            // Parse JPEG-LS
            let parser = JPEGLSParser(data: data)
            let parseResult = try parser.parse()
            
            // Extract metadata
            metadata = ImageMetadata(
                width: Int(parseResult.frameHeader.width),
                height: Int(parseResult.frameHeader.height),
                bitsPerSample: Int(parseResult.frameHeader.bitsPerSample),
                componentCount: Int(parseResult.frameHeader.componentCount),
                near: parseResult.scanHeaders[0].near
            )
            
            // Load image
            let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
            originalImage = cgImage
            imageView.setImage(cgImage)
            
            updateInfoPanel()
            configureWindowLevelForImage()
        } catch {
            showJPEGLSError(error, for: url)
        }
    }
    
    private func setupSliders() {
        windowLevelSlider.target = self
        windowLevelSlider.action = #selector(windowLevelChanged)
        
        windowWidthSlider.target = self
        windowWidthSlider.action = #selector(windowWidthChanged)
    }
    
    private func configureWindowLevelForImage() {
        guard let metadata = metadata else { return }
        
        let maxValue = (1 << metadata.bitsPerSample) - 1
        
        windowLevelSlider.minValue = 0
        windowLevelSlider.maxValue = Double(maxValue)
        windowLevelSlider.doubleValue = Double(maxValue / 2)
        
        windowWidthSlider.minValue = 1
        windowWidthSlider.maxValue = Double(maxValue)
        windowWidthSlider.doubleValue = Double(maxValue)
    }
    
    @objc private func windowLevelChanged() {
        applyWindowLevel()
    }
    
    @objc private func windowWidthChanged() {
        applyWindowLevel()
    }
    
    private func applyWindowLevel() {
        guard let original = originalImage else { return }
        
        // In a real implementation, you would apply window/level
        // transformation to the pixel data
        
        // For now, just refresh the display
        imageView.needsDisplay = true
    }
    
    private func updateInfoPanel() {
        guard let metadata = metadata else { return }
        
        dimensionsLabel.stringValue = "\(metadata.width) × \(metadata.height)"
        bitsLabel.stringValue = "\(metadata.bitsPerSample)-bit"
        encodingLabel.stringValue = metadata.near == 0 ? "Lossless" : "Near-lossless (NEAR=\(metadata.near))"
    }
    
    @IBAction func resetView(_ sender: Any) {
        imageView.resetView()
        configureWindowLevelForImage()
    }
    
    @IBAction func zoomIn(_ sender: Any) {
        imageView.zoom(by: 1.2)
    }
    
    @IBAction func zoomOut(_ sender: Any) {
        imageView.zoom(by: 0.8)
    }
}
```

### Window/Level Adjustment

Implement proper window/level for medical images:

```swift
import Cocoa
import CoreImage

class WindowLevelFilter {
    
    static func apply(
        to image: CGImage,
        windowLevel: Double,
        windowWidth: Double
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        
        // Calculate window bounds
        let minValue = windowLevel - (windowWidth / 2)
        let maxValue = windowLevel + (windowWidth / 2)
        
        // Create color controls filter
        guard let filter = CIFilter(name: "CIColorControls") else {
            return nil
        }
        
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        // Adjust contrast and brightness based on window/level
        let scale = 1.0 / windowWidth
        let offset = -minValue * scale
        
        filter.setValue(scale, forKey: kCIInputSaturationKey)
        filter.setValue(offset, forKey: kCIInputBrightnessKey)
        
        guard let output = filter.outputImage else {
            return nil
        }
        
        let context = CIContext()
        return context.createCGImage(output, from: output.extent)
    }
}
```

### Measurement Tools

Add measurement and annotation tools:

```swift
import Cocoa

class MeasurementOverlay: NSView {
    
    struct Measurement {
        let start: CGPoint
        let end: CGPoint
        let pixelSize: Double // mm per pixel
        
        var length: Double {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let pixels = sqrt(dx * dx + dy * dy)
            return pixels * pixelSize
        }
    }
    
    private var measurements: [Measurement] = []
    private var currentMeasurement: (start: CGPoint, current: CGPoint)?
    private var pixelSize: Double = 0.1 // Default: 0.1 mm per pixel
    
    override var isFlipped: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        NSColor.yellow.setStroke()
        
        // Draw completed measurements
        for measurement in measurements {
            drawMeasurement(from: measurement.start, to: measurement.end)
            drawLabel(for: measurement)
        }
        
        // Draw current measurement in progress
        if let current = currentMeasurement {
            NSColor.cyan.setStroke()
            drawMeasurement(from: current.start, to: current.current)
        }
    }
    
    private func drawMeasurement(from start: CGPoint, to end: CGPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 2.0
        path.stroke()
        
        // Draw endpoints
        let endpointPath = NSBezierPath(
            ovalIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)
        )
        endpointPath.fill()
    }
    
    private func drawLabel(for measurement: Measurement) {
        let text = String(format: "%.1f mm", measurement.length)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.yellow
        ]
        
        let midPoint = CGPoint(
            x: (measurement.start.x + measurement.end.x) / 2,
            y: (measurement.start.y + measurement.end.y) / 2
        )
        
        (text as NSString).draw(at: midPoint, withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        currentMeasurement = (start: location, current: location)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard var measurement = currentMeasurement else { return }
        let location = convert(event.locationInWindow, from: nil)
        measurement.current = location
        currentMeasurement = measurement
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let current = currentMeasurement else { return }
        
        let measurement = Measurement(
            start: current.start,
            end: current.current,
            pixelSize: pixelSize
        )
        measurements.append(measurement)
        currentMeasurement = nil
        needsDisplay = true
    }
    
    func clearMeasurements() {
        measurements.removeAll()
        currentMeasurement = nil
        needsDisplay = true
    }
    
    func setPixelSize(_ size: Double) {
        pixelSize = size
        needsDisplay = true
    }
}
```

## Performance Optimisation

### Background Loading

Load images without blocking the UI:

```swift
import Cocoa
import JPEGLS

class AsyncImageLoader {
    
    typealias CompletionHandler = (Result<NSImage, Error>) -> Void
    
    private let queue = DispatchQueue(
        label: "com.example.jpegls.loader",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    func loadImage(from url: URL, completion: @escaping CompletionHandler) {
        queue.async {
            do {
                let image = try JPEGLSImageLoader.loadImage(from: url)
                DispatchQueue.main.async {
                    completion(.success(image))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
```

### Thumbnail Generation

Generate thumbnails efficiently:

```swift
import Cocoa
import JPEGLS

class JPEGLSThumbnailGenerator {
    
    static func generateThumbnail(
        from url: URL,
        maxSize: CGSize
    ) throws -> NSImage {
        // Load the full image
        let cgImage = try JPEGLSImageLoader.loadCGImage(from: url)
        
        // Calculate thumbnail size maintaining aspect ratio
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let thumbnailSize = calculateThumbnailSize(
            imageSize: imageSize,
            maxSize: maxSize
        )
        
        // Create thumbnail
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        
        let sourceRect = CGRect(origin: .zero, size: imageSize)
        let destRect = CGRect(origin: .zero, size: thumbnailSize)
        
        if let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            context.draw(cgImage, in: destRect)
        }
        
        thumbnail.unlockFocus()
        return thumbnail
    }
    
    private static func calculateThumbnailSize(
        imageSize: CGSize,
        maxSize: CGSize
    ) -> CGSize {
        let widthRatio = maxSize.width / imageSize.width
        let heightRatio = maxSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        
        return CGSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
        )
    }
}
```

### Memory Management

Efficient memory handling for large images:

```swift
import Cocoa
import JPEGLS

class ManagedImageLoader {
    
    private var imageCache: NSCache<NSURL, NSImage>
    
    init(memoryLimit: Int = 100 * 1024 * 1024) { // 100 MB default
        imageCache = NSCache()
        imageCache.totalCostLimit = memoryLimit
    }
    
    func loadImage(from url: URL) throws -> NSImage {
        // Check cache first
        if let cached = imageCache.object(forKey: url as NSURL) {
            return cached
        }
        
        // Load image
        let image = try JPEGLSImageLoader.loadImage(from: url)
        
        // Estimate memory cost
        let cost = estimateMemoryCost(for: image)
        
        // Cache with cost
        imageCache.setObject(image, forKey: url as NSURL, cost: cost)
        
        return image
    }
    
    private func estimateMemoryCost(for image: NSImage) -> Int {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return 0
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        return width * height * bytesPerPixel
    }
    
    func clearCache() {
        imageCache.removeAllObjects()
    }
}
```

## Next Steps

- Explore [SWIFTUI_EXAMPLES.md](SWIFTUI_EXAMPLES.md) for SwiftUI integration patterns
- See [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) for general library usage
- Refer to [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) for optimisation strategies
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues

## Notes

**Important**: Some examples use placeholder code for bitstream decoding, which is currently under development (see MILESTONES.md Phase 7.1). The architecture and API patterns shown are production-ready and will work with minimal modifications once bitstream integration is complete. The AppKit integration patterns demonstrated here provide a solid foundation for building professional medical imaging applications on macOS.
