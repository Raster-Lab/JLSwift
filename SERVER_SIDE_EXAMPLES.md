# Server-Side Swift Integration Examples for JLSwift

This guide demonstrates how to integrate JLSwift JPEG-LS compression into server-side Swift applications using popular frameworks like Vapor, Hummingbird, and standalone NIO-based services.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Vapor Framework Examples](#vapor-framework-examples)
  - [REST API for JPEG-LS Conversion](#rest-api-for-jpeg-ls-conversion)
  - [Medical Imaging Upload Service](#medical-imaging-upload-service)
  - [Streaming Large File Encoder](#streaming-large-file-encoder)
  - [Batch Processing API](#batch-processing-api)
- [Hummingbird Framework Examples](#hummingbird-framework-examples)
  - [Simple JPEG-LS API Service](#simple-jpeg-ls-api-service)
  - [File Upload Handler](#file-upload-handler)
- [Swift NIO Examples](#swift-nio-examples)
  - [Custom Protocol Handler](#custom-protocol-handler)
  - [Non-Blocking File Processing](#non-blocking-file-processing)
- [Deployment Examples](#deployment-examples)
  - [Docker Container](#docker-container)
  - [Kubernetes Deployment](#kubernetes-deployment)
  - [Systemd Service](#systemd-service)
- [Performance Optimization](#performance-optimization)
  - [Connection Pooling](#connection-pooling)
  - [Worker Thread Management](#worker-thread-management)
  - [Memory-Efficient Streaming](#memory-efficient-streaming)
- [Middleware & Integration](#middleware--integration)
  - [Authentication Middleware](#authentication-middleware)
  - [Rate Limiting](#rate-limiting)
  - [Response Caching](#response-caching)

## Overview

JLSwift is well-suited for server-side Swift applications that need to:
- Process medical imaging data (DICOM)
- Provide image conversion APIs
- Handle batch image processing
- Serve high-performance compression services
- Build microservices for image analysis

Key benefits for server-side use:
- **Pure Swift**: No C dependencies, easier deployment
- **Memory Efficient**: Buffer pooling and tile-based processing
- **Performance**: Hardware acceleration on Apple Silicon servers
- **Concurrent**: Safe to use across multiple concurrent requests
- **Standards Compliant**: Full JPEG-LS (ISO/IEC 14495-1:1999) support

## Prerequisites

Add JLSwift to your server project's `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyImageServer",
    platforms: [
        .macOS(.v12),
        .linux
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/Raster-Lab/JLSwift.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MyImageServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JPEGLS", package: "JLSwift")
            ]
        )
    ]
)
```

## Vapor Framework Examples

### REST API for JPEG-LS Conversion

Create a REST API that converts raw image data to JPEG-LS format:

```swift
import Vapor
import JPEGLS

struct ImageConversionRequest: Content {
    let width: Int
    let height: Int
    let bitsPerSample: Int
    let near: Int?
    let interleaveMode: String?
}

func routes(_ app: Application) throws {
    
    // POST /api/encode - Encode raw image data to JPEG-LS
    app.post("api", "encode") { req async throws -> Response in
        // Parse metadata from JSON
        let metadata = try req.content.decode(ImageConversionRequest.self)
        
        // Read raw image data from body
        guard let rawData = req.body.data else {
            throw Abort(.badRequest, reason: "Missing image data")
        }
        
        // Validate parameters
        guard metadata.width > 0 && metadata.width <= 65535 else {
            throw Abort(.badRequest, reason: "Invalid width")
        }
        guard metadata.height > 0 && metadata.height <= 65535 else {
            throw Abort(.badRequest, reason: "Invalid height")
        }
        guard (2...16).contains(metadata.bitsPerSample) else {
            throw Abort(.badRequest, reason: "Bits per sample must be 2-16")
        }
        
        // Convert raw bytes to pixel array
        let pixels = try convertRawDataToPixels(
            data: rawData,
            width: metadata.width,
            height: metadata.height,
            bitsPerSample: metadata.bitsPerSample
        )
        
        // Create image data
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: metadata.bitsPerSample
        )
        
        // Create scan header with NEAR parameter
        let near = metadata.near ?? 0
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            componentIDs: [1],
            interleaveMode: .none,
            near: near,
            pointTransform: 0
        )
        
        // Encode
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        // Return encoded data with statistics
        let response = Response(status: .ok)
        response.headers.contentType = .init(type: "image", subType: "x-jls")
        response.headers.add(name: "X-Pixels-Encoded", value: "\(statistics.pixelsEncoded)")
        response.headers.add(name: "X-Regular-Mode-Count", value: "\(statistics.regularModeCount)")
        response.headers.add(name: "X-Run-Mode-Count", value: "\(statistics.runModeCount)")
        
        // Note: Full bitstream writing pending integration
        response.body = .init(string: "Encoding successful")
        
        return response
    }
    
    // POST /api/decode - Decode JPEG-LS file to raw data
    app.post("api", "decode") { req async throws -> Response in
        guard let jlsData = req.body.data else {
            throw Abort(.badRequest, reason: "Missing JPEG-LS data")
        }
        
        // Parse JPEG-LS file
        let parser = JPEGLSParser(data: Data(buffer: jlsData))
        let parseResult = try parser.parse()
        
        // Create decoder
        let decoder = try JPEGLSMultiComponentDecoder(
            frameHeader: parseResult.frameHeader,
            scanHeader: parseResult.scanHeaders[0],
            colorTransformation: .none
        )
        
        // Return file information
        let info = [
            "width": parseResult.frameHeader.width,
            "height": parseResult.frameHeader.height,
            "bitsPerSample": parseResult.frameHeader.bitsPerSample,
            "componentCount": parseResult.frameHeader.componentCount,
            "near": parseResult.scanHeaders[0].near
        ]
        
        return try await info.encodeResponse(for: req)
    }
    
    // GET /api/info/:filename - Get JPEG-LS file information
    app.get("api", "info", ":filename") { req async throws -> [String: Any] in
        guard let filename = req.parameters.get("filename") else {
            throw Abort(.badRequest, reason: "Missing filename")
        }
        
        let filePath = app.directory.publicDirectory + filename
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        let parser = JPEGLSParser(data: data)
        let result = try parser.parse()
        
        return [
            "filename": filename,
            "width": result.frameHeader.width,
            "height": result.frameHeader.height,
            "bitsPerSample": result.frameHeader.bitsPerSample,
            "componentCount": result.frameHeader.componentCount,
            "scanCount": result.scanHeaders.count,
            "fileSize": data.count,
            "hasPresetParameters": result.presetParameters != nil
        ]
    }
}

// Helper function to convert raw bytes to 2D pixel array
func convertRawDataToPixels(
    data: ByteBuffer,
    width: Int,
    height: Int,
    bitsPerSample: Int
) throws -> [[Int]] {
    let bytesPerSample = (bitsPerSample + 7) / 8
    let expectedSize = width * height * bytesPerSample
    
    guard data.readableBytes >= expectedSize else {
        throw Abort(.badRequest, reason: "Insufficient data for image dimensions")
    }
    
    var pixels: [[Int]] = []
    var offset = 0
    
    for _ in 0..<height {
        var row: [Int] = []
        for _ in 0..<width {
            let value: Int
            if bytesPerSample == 1 {
                value = Int(data.getInteger(at: offset, as: UInt8.self) ?? 0)
            } else {
                value = Int(data.getInteger(at: offset, endianness: .big, as: UInt16.self) ?? 0)
            }
            row.append(value)
            offset += bytesPerSample
        }
        pixels.append(row)
    }
    
    return pixels
}
```

### Medical Imaging Upload Service

Create a specialized service for handling medical imaging uploads with validation:

```swift
import Vapor
import JPEGLS

struct MedicalImageMetadata: Content {
    let patientID: String
    let studyID: String
    let seriesID: String
    let modality: String // CT, MR, CR, etc.
    let width: Int
    let height: Int
    let bitsPerSample: Int
}

func configureMedicalImageRoutes(_ app: Application) throws {
    
    let medical = app.grouped("api", "medical")
    
    // POST /api/medical/upload - Upload and compress medical image
    medical.on(.POST, "upload", body: .collect(maxSize: "100mb")) { req async throws -> Response in
        // Parse multipart form data
        let metadata = try req.content.decode(MedicalImageMetadata.self)
        
        // Validate medical imaging parameters
        try validateMedicalImageParameters(metadata)
        
        // Get image data from multipart
        guard let imageData = req.body.data else {
            throw Abort(.badRequest, reason: "Missing image data")
        }
        
        // Convert to JPEG-LS with lossless compression (required for diagnostics)
        let pixels = try convertRawDataToPixels(
            data: imageData,
            width: metadata.width,
            height: metadata.height,
            bitsPerSample: metadata.bitsPerSample
        )
        
        let image = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: metadata.bitsPerSample
        )
        
        // Use lossless compression for medical images
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: image.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: image)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        // Store to disk (example path)
        let filename = "\(metadata.studyID)_\(metadata.seriesID).jls"
        let storagePath = app.directory.workingDirectory + "medical_images/" + filename
        
        // Save metadata to database (example)
        req.logger.info("Encoded medical image", metadata: [
            "patient_id": .string(metadata.patientID),
            "study_id": .string(metadata.studyID),
            "modality": .string(metadata.modality),
            "pixels_encoded": .string("\(statistics.pixelsEncoded)"),
            "filename": .string(filename)
        ])
        
        return Response(status: .created, headers: [
            "Location": "/api/medical/image/\(filename)",
            "X-Image-ID": filename
        ])
    }
    
    // GET /api/medical/image/:id - Retrieve medical image
    medical.get("image", ":id") { req async throws -> Response in
        guard let imageID = req.parameters.get("id") else {
            throw Abort(.badRequest)
        }
        
        let filePath = app.directory.workingDirectory + "medical_images/" + imageID
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw Abort(.notFound, reason: "Image not found")
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        let response = Response(status: .ok)
        response.headers.contentType = .init(type: "image", subType: "x-jls")
        response.headers.cacheControl = .init(isPublic: false, maxAge: 3600)
        response.body = .init(data: data)
        
        return response
    }
    
    // POST /api/medical/validate - Validate JPEG-LS medical image
    medical.post("validate") { req async throws -> [String: Any] in
        guard let jlsData = req.body.data else {
            throw Abort(.badRequest, reason: "Missing JPEG-LS data")
        }
        
        let parser = JPEGLSParser(data: Data(buffer: jlsData))
        let result = try parser.parse()
        
        // Validate medical imaging requirements
        let isLossless = result.scanHeaders.allSatisfy { $0.near == 0 }
        let hasValidBitDepth = [8, 12, 16].contains(result.frameHeader.bitsPerSample)
        let hasValidDimensions = result.frameHeader.width > 0 && result.frameHeader.height > 0
        
        let isValid = isLossless && hasValidBitDepth && hasValidDimensions
        
        return [
            "valid": isValid,
            "lossless": isLossless,
            "bitDepth": result.frameHeader.bitsPerSample,
            "dimensions": "\(result.frameHeader.width)x\(result.frameHeader.height)",
            "warnings": isValid ? [] : [
                !isLossless ? "Near-lossless compression not recommended for diagnostics" : nil,
                !hasValidBitDepth ? "Non-standard bit depth for medical imaging" : nil
            ].compactMap { $0 }
        ]
    }
}

func validateMedicalImageParameters(_ metadata: MedicalImageMetadata) throws {
    // Validate patient ID format
    guard !metadata.patientID.isEmpty else {
        throw Abort(.badRequest, reason: "Patient ID required")
    }
    
    // Validate modality
    let validModalities = ["CT", "MR", "CR", "DX", "US", "MG", "XA", "RF"]
    guard validModalities.contains(metadata.modality) else {
        throw Abort(.badRequest, reason: "Invalid modality")
    }
    
    // Validate bit depth for medical imaging
    let validBitDepths = [8, 12, 16]
    guard validBitDepths.contains(metadata.bitsPerSample) else {
        throw Abort(.badRequest, reason: "Medical images require 8, 12, or 16 bits per sample")
    }
    
    // Validate dimensions
    guard metadata.width > 0 && metadata.width <= 65535 else {
        throw Abort(.badRequest, reason: "Invalid width")
    }
    guard metadata.height > 0 && metadata.height <= 65535 else {
        throw Abort(.badRequest, reason: "Invalid height")
    }
}
```

### Streaming Large File Encoder

Process large files with streaming to minimize memory usage:

```swift
import Vapor
import JPEGLS
import NIOCore

func configureStreamingRoutes(_ app: Application) throws {
    
    // POST /api/stream/encode - Stream-encode large image
    app.on(.POST, "api", "stream", "encode", body: .stream) { req async throws -> Response in
        // Use tile-based processing for large images
        let tileConfig = TileConfiguration(
            tileWidth: 512,
            tileHeight: 512,
            overlap: 4
        )
        
        // Parse dimensions from query parameters
        guard let width = req.query[Int.self, at: "width"],
              let height = req.query[Int.self, at: "height"],
              let bitsPerSample = req.query[Int.self, at: "bits"] else {
            throw Abort(.badRequest, reason: "Missing dimensions")
        }
        
        let processor = JPEGLSTileProcessor(
            imageWidth: width,
            imageHeight: height,
            configuration: tileConfig
        )
        
        let tiles = processor.calculateTilesWithOverlap()
        
        // Calculate memory savings
        let savings = processor.estimateMemorySavings(bytesPerPixel: (bitsPerSample + 7) / 8)
        
        req.logger.info("Processing large image with \(tiles.count) tiles", metadata: [
            "memory_savings": .string("\(Int(savings * 100))%"),
            "tile_size": .string("\(tileConfig.tileWidth)x\(tileConfig.tileHeight)")
        ])
        
        // Stream processing using buffer pool
        let bufferPool = JPEGLSBufferPool.shared
        var totalPixelsEncoded = 0
        
        for (index, tile) in tiles.enumerated() {
            // Acquire buffer from pool
            let contextBuffer = bufferPool.acquire(
                type: .contextArrays,
                size: 365 * MemoryLayout<JPEGLSContextModel.ContextState>.stride
            )
            defer { bufferPool.release(contextBuffer, type: .contextArrays) }
            
            req.logger.debug("Processing tile \(index + 1)/\(tiles.count)")
            
            // Process tile (simplified - actual implementation would read from stream)
            totalPixelsEncoded += tile.width * tile.height
        }
        
        return Response(status: .ok, headers: [
            "X-Tiles-Processed": "\(tiles.count)",
            "X-Pixels-Encoded": "\(totalPixelsEncoded)",
            "X-Memory-Savings": "\(Int(savings * 100))%"
        ])
    }
}
```

### Batch Processing API

Handle multiple images in a single request:

```swift
import Vapor
import JPEGLS

struct BatchProcessRequest: Content {
    struct ImageRequest: Content {
        let id: String
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let near: Int?
    }
    
    let images: [ImageRequest]
    let parallelism: Int?
}

struct BatchProcessResponse: Content {
    struct ImageResult: Content {
        let id: String
        let success: Bool
        let error: String?
        let pixelsEncoded: Int?
        let processingTimeMs: Double?
    }
    
    let results: [ImageResult]
    let totalProcessingTimeMs: Double
    let successCount: Int
    let failureCount: Int
}

func configureBatchRoutes(_ app: Application) throws {
    
    // POST /api/batch/encode - Batch encode multiple images
    app.post("api", "batch", "encode") { req async throws -> BatchProcessResponse in
        let startTime = Date()
        let batchRequest = try req.content.decode(BatchProcessRequest.self)
        
        // Validate batch size
        guard batchRequest.images.count <= 100 else {
            throw Abort(.badRequest, reason: "Batch size limited to 100 images")
        }
        
        // Process images in parallel using async/await
        let maxParallelism = batchRequest.parallelism ?? min(4, batchRequest.images.count)
        
        req.logger.info("Processing batch of \(batchRequest.images.count) images with parallelism \(maxParallelism)")
        
        // Use TaskGroup for concurrent processing
        let results = try await withThrowingTaskGroup(of: BatchProcessResponse.ImageResult.self) { group in
            var results: [BatchProcessResponse.ImageResult] = []
            var activeCount = 0
            var index = 0
            
            // Start initial tasks up to parallelism limit
            while index < batchRequest.images.count && activeCount < maxParallelism {
                let imageReq = batchRequest.images[index]
                group.addTask {
                    try await processImageAsync(imageReq, logger: req.logger)
                }
                activeCount += 1
                index += 1
            }
            
            // Process remaining images as tasks complete
            while let result = try await group.next() {
                results.append(result)
                
                // Start next task if available
                if index < batchRequest.images.count {
                    let imageReq = batchRequest.images[index]
                    group.addTask {
                        try await processImageAsync(imageReq, logger: req.logger)
                    }
                    index += 1
                }
            }
            
            return results
        }
        
        let totalTime = Date().timeIntervalSince(startTime) * 1000
        let successCount = results.filter { $0.success }.count
        let failureCount = results.count - successCount
        
        req.logger.info("Batch processing complete", metadata: [
            "total_images": .string("\(results.count)"),
            "success": .string("\(successCount)"),
            "failed": .string("\(failureCount)"),
            "time_ms": .string("\(Int(totalTime))")
        ])
        
        return BatchProcessResponse(
            results: results,
            totalProcessingTimeMs: totalTime,
            successCount: successCount,
            failureCount: failureCount
        )
    }
}

func processImageAsync(_ imageReq: BatchProcessRequest.ImageRequest, logger: Logger) async throws -> BatchProcessResponse.ImageResult {
    let startTime = Date()
    
    do {
        // Simulate image processing (in real implementation, would load from storage)
        let pixels = Array(repeating: Array(repeating: 0, count: imageReq.width), count: imageReq.height)
        
        let imageData = try MultiComponentImageData.grayscale(
            pixels: pixels,
            bitsPerSample: imageReq.bitsPerSample
        )
        
        let near = imageReq.near ?? 0
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            componentIDs: [1],
            interleaveMode: .none,
            near: near,
            pointTransform: 0
        )
        
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        let processingTime = Date().timeIntervalSince(startTime) * 1000
        
        return BatchProcessResponse.ImageResult(
            id: imageReq.id,
            success: true,
            error: nil,
            pixelsEncoded: statistics.pixelsEncoded,
            processingTimeMs: processingTime
        )
        
    } catch {
        let processingTime = Date().timeIntervalSince(startTime) * 1000
        logger.error("Failed to process image \(imageReq.id): \(error)")
        
        return BatchProcessResponse.ImageResult(
            id: imageReq.id,
            success: false,
            error: error.localizedDescription,
            pixelsEncoded: nil,
            processingTimeMs: processingTime
        )
    }
}
```

## Hummingbird Framework Examples

### Simple JPEG-LS API Service

Create a lightweight service using Hummingbird:

```swift
import Hummingbird
import JPEGLS

@main
struct JPEGLSService {
    static func main() async throws {
        let router = Router()
        
        // Health check endpoint
        router.get("/health") { request, context in
            return ["status": "healthy", "service": "jpegls-api"]
        }
        
        // Encode endpoint
        router.post("/encode") { request, context in
            guard let body = request.body.buffer else {
                throw HTTPError(.badRequest, message: "Missing body")
            }
            
            // Parse query parameters
            guard let width = request.uri.queryParameters.get("width", as: Int.self),
                  let height = request.uri.queryParameters.get("height", as: Int.self),
                  let bits = request.uri.queryParameters.get("bits", as: Int.self) else {
                throw HTTPError(.badRequest, message: "Missing parameters")
            }
            
            // Simple validation
            guard (1...65535).contains(width) && (1...65535).contains(height) && (2...16).contains(bits) else {
                throw HTTPError(.badRequest, message: "Invalid parameters")
            }
            
            context.logger.info("Encoding image", metadata: [
                "width": "\(width)",
                "height": "\(height)",
                "bits": "\(bits)"
            ])
            
            // Return success (full implementation would encode data)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(string: "{\"status\":\"encoded\"}"))
            )
        }
        
        // Info endpoint
        router.get("/info/:filename") { request, context in
            guard let filename = request.parameters.get("filename") else {
                throw HTTPError(.badRequest)
            }
            
            // Read file (example path)
            let filePath = "images/" + filename
            
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                throw HTTPError(.notFound, message: "File not found")
            }
            
            let parser = JPEGLSParser(data: data)
            let result = try parser.parse()
            
            return [
                "filename": filename,
                "width": result.frameHeader.width,
                "height": result.frameHeader.height,
                "bits": result.frameHeader.bitsPerSample,
                "components": result.frameHeader.componentCount
            ]
        }
        
        let app = Application(router: router)
        try await app.runService()
    }
}
```

### File Upload Handler

Handle multipart file uploads in Hummingbird:

```swift
import Hummingbird
import HummingbirdMultipart
import JPEGLS

func configureFileUpload(router: Router<some RequestContext>) {
    
    router.post("/upload") { request, context in
        // Parse multipart form data
        let formData = try await request.decode(as: MultipartForm.self, context: context)
        
        guard let imageFile = formData.parts.first(where: { $0.name == "image" }) else {
            throw HTTPError(.badRequest, message: "Missing image file")
        }
        
        guard let imageData = imageFile.body.buffer else {
            throw HTTPError(.badRequest, message: "Empty file")
        }
        
        // Get metadata from form
        let width = formData.parts.first(where: { $0.name == "width" })?.body.string.flatMap(Int.init) ?? 0
        let height = formData.parts.first(where: { $0.name == "height" })?.body.string.flatMap(Int.init) ?? 0
        let bits = formData.parts.first(where: { $0.name == "bits" })?.body.string.flatMap(Int.init) ?? 8
        
        // Validate
        guard width > 0 && height > 0 else {
            throw HTTPError(.badRequest, message: "Invalid dimensions")
        }
        
        context.logger.info("Processing upload", metadata: [
            "size": "\(imageData.readableBytes)",
            "dimensions": "\(width)x\(height)"
        ])
        
        // Save to disk
        let filename = UUID().uuidString + ".jls"
        let savePath = "uploads/" + filename
        
        try FileManager.default.createDirectory(
            atPath: "uploads",
            withIntermediateDirectories: true
        )
        
        try imageData.getData(at: 0, length: imageData.readableBytes)?.write(to: URL(fileURLWithPath: savePath))
        
        return Response(
            status: .created,
            headers: [
                "Location": "/files/\(filename)",
                .contentType: "application/json"
            ],
            body: .init(byteBuffer: ByteBuffer(string: "{\"filename\":\"\(filename)\"}"))
        )
    }
}
```

## Swift NIO Examples

### Custom Protocol Handler

Create a custom TCP protocol handler for JPEG-LS:

```swift
import NIO
import JPEGLS

final class JPEGLSProtocolHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        
        guard let data = buffer.readData(length: buffer.readableBytes) else {
            context.fireErrorCaught(JPEGLSError.invalidData)
            return
        }
        
        do {
            // Parse JPEG-LS data
            let parser = JPEGLSParser(data: data)
            let result = try parser.parse()
            
            // Create response with file info
            let response = """
            JPEGLS_INFO
            Width: \(result.frameHeader.width)
            Height: \(result.frameHeader.height)
            Bits: \(result.frameHeader.bitsPerSample)
            Components: \(result.frameHeader.componentCount)
            """
            
            var responseBuffer = context.channel.allocator.buffer(capacity: response.utf8.count)
            responseBuffer.writeString(response)
            
            context.writeAndFlush(wrapOutboundOut(responseBuffer), promise: nil)
            
        } catch {
            var errorBuffer = context.channel.allocator.buffer(capacity: 100)
            errorBuffer.writeString("ERROR: \(error.localizedDescription)")
            context.writeAndFlush(wrapOutboundOut(errorBuffer), promise: nil)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }
}

// Bootstrap server
func startJPEGLSServer(port: Int) throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer { try? group.syncShutdownGracefully() }
    
    let bootstrap = ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(JPEGLSProtocolHandler())
        }
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    
    let channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
    
    print("JPEG-LS server started on port \(port)")
    
    try channel.closeFuture.wait()
}
```

### Non-Blocking File Processing

Process files asynchronously with NIO:

```swift
import NIO
import JPEGLS

actor JPEGLSProcessor {
    private let eventLoop: EventLoop
    private let bufferPool = JPEGLSBufferPool.shared
    
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
    
    func processFile(path: String) -> EventLoopFuture<ProcessingResult> {
        let promise = eventLoop.makePromise(of: ProcessingResult.self)
        
        // Load file asynchronously
        eventLoop.execute {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let parser = JPEGLSParser(data: data)
                let result = try parser.parse()
                
                let processingResult = ProcessingResult(
                    filename: path,
                    width: Int(result.frameHeader.width),
                    height: Int(result.frameHeader.height),
                    bitsPerSample: Int(result.frameHeader.bitsPerSample),
                    fileSize: data.count
                )
                
                promise.succeed(processingResult)
                
            } catch {
                promise.fail(error)
            }
        }
        
        return promise.futureResult
    }
    
    func batchProcess(paths: [String]) -> EventLoopFuture<[ProcessingResult]> {
        let futures = paths.map { processFile(path: $0) }
        return EventLoopFuture.whenAllSucceed(futures, on: eventLoop)
    }
}

struct ProcessingResult {
    let filename: String
    let width: Int
    let height: Int
    let bitsPerSample: Int
    let fileSize: Int
}
```

## Deployment Examples

### Docker Container

Create a Dockerfile for your JPEG-LS service:

```dockerfile
# Dockerfile
FROM swift:6.2-jammy as builder

WORKDIR /app

# Copy Package files
COPY Package.swift Package.resolved ./
COPY Sources ./Sources

# Build in release mode
RUN swift build -c release \
    --static-swift-stdlib \
    -Xlinker -s

# Production image
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libcurl4 \
    libxml2 \
    && rm -rf /var/lib/apt/lists/*

# Copy the built executable
COPY --from=builder /app/.build/release/jpegls-service /usr/local/bin/

# Create non-root user
RUN useradd -m -u 1000 jpegls
USER jpegls

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the service
ENTRYPOINT ["/usr/local/bin/jpegls-service"]
```

Docker Compose configuration:

```yaml
# docker-compose.yml
version: '3.8'

services:
  jpegls-api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - LOG_LEVEL=info
      - MAX_UPLOAD_SIZE=104857600  # 100MB
    volumes:
      - ./uploads:/app/uploads
      - ./medical_images:/app/medical_images
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

  # Optional: nginx reverse proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    depends_on:
      - jpegls-api
    restart: unless-stopped
```

### Kubernetes Deployment

Kubernetes deployment manifest:

```yaml
# jpegls-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jpegls-service
  labels:
    app: jpegls
spec:
  replicas: 3
  selector:
    matchLabels:
      app: jpegls
  template:
    metadata:
      labels:
        app: jpegls
    spec:
      containers:
      - name: jpegls-api
        image: your-registry/jpegls-service:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: LOG_LEVEL
          value: "info"
        - name: MAX_UPLOAD_SIZE
          value: "104857600"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        volumeMounts:
        - name: uploads
          mountPath: /app/uploads
        - name: medical-images
          mountPath: /app/medical_images
      volumes:
      - name: uploads
        persistentVolumeClaim:
          claimName: jpegls-uploads-pvc
      - name: medical-images
        persistentVolumeClaim:
          claimName: jpegls-medical-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: jpegls-service
spec:
  selector:
    app: jpegls
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: LoadBalancer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jpegls-uploads-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jpegls-medical-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 500Gi
```

### Systemd Service

Create a systemd service for Linux servers:

```ini
# /etc/systemd/system/jpegls-service.service
[Unit]
Description=JPEG-LS Compression Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=jpegls
Group=jpegls
WorkingDirectory=/opt/jpegls
ExecStart=/opt/jpegls/bin/jpegls-service
Restart=always
RestartSec=10

# Environment
Environment="LOG_LEVEL=info"
Environment="PORT=8080"
Environment="MAX_UPLOAD_SIZE=104857600"

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/jpegls

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=jpegls-service

[Install]
WantedBy=multi-user.target
```

Installation and management:

```bash
# Install the service
sudo cp jpegls-service.service /etc/systemd/system/
sudo systemctl daemon-reload

# Start the service
sudo systemctl start jpegls-service

# Enable on boot
sudo systemctl enable jpegls-service

# Check status
sudo systemctl status jpegls-service

# View logs
sudo journalctl -u jpegls-service -f
```

## Performance Optimization

### Connection Pooling

Implement connection pooling for database or storage access:

```swift
import Vapor
import JPEGLS

actor ConnectionPool {
    private var available: [Connection] = []
    private let maxConnections: Int
    private var createdConnections = 0
    
    init(maxConnections: Int) {
        self.maxConnections = maxConnections
    }
    
    func acquire() async throws -> Connection {
        if let connection = available.popLast() {
            return connection
        }
        
        guard createdConnections < maxConnections else {
            // Wait for a connection to become available
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return try await acquire()
        }
        
        createdConnections += 1
        return Connection()
    }
    
    func release(_ connection: Connection) {
        available.append(connection)
    }
}

struct Connection {
    // Connection implementation
}

// Use in Vapor routes
func configurePooling(_ app: Application) {
    let pool = ConnectionPool(maxConnections: 10)
    app.storage[ConnectionPoolKey.self] = pool
}

struct ConnectionPoolKey: StorageKey {
    typealias Value = ConnectionPool
}
```

### Worker Thread Management

Optimize CPU-bound operations with dedicated worker threads:

```swift
import Vapor
import JPEGLS
import Dispatch

final class WorkerPool {
    private let queue: DispatchQueue
    private let workerCount: Int
    
    init(workerCount: Int = ProcessInfo.processInfo.processorCount) {
        self.workerCount = workerCount
        self.queue = DispatchQueue(
            label: "com.jpegls.workers",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }
    
    func encode(_ request: EncodeRequest) async throws -> EncodeResult {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.performEncode(request)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performEncode(_ request: EncodeRequest) throws -> EncodeResult {
        // Use buffer pooling for better memory management
        let bufferPool = JPEGLSBufferPool.shared
        let contextBuffer = bufferPool.acquire(type: .contextArrays, size: 365)
        defer { bufferPool.release(contextBuffer, type: .contextArrays) }
        
        // Perform encoding
        let imageData = try MultiComponentImageData.grayscale(
            pixels: request.pixels,
            bitsPerSample: request.bitsPerSample
        )
        
        let scanHeader = try JPEGLSScanHeader.grayscaleLossless()
        let encoder = try JPEGLSMultiComponentEncoder(
            frameHeader: imageData.frameHeader,
            scanHeader: scanHeader
        )
        
        let buffer = JPEGLSPixelBuffer(imageData: imageData)
        let statistics = try encoder.encodeScan(buffer: buffer)
        
        return EncodeResult(statistics: statistics)
    }
}

struct EncodeRequest {
    let pixels: [[Int]]
    let bitsPerSample: Int
}

struct EncodeResult {
    let statistics: JPEGLSMultiComponentEncoder.Statistics
}
```

### Memory-Efficient Streaming

Process large files with minimal memory footprint:

```swift
import Vapor
import JPEGLS

func configureStreamingProcessing(_ app: Application) {
    
    app.on(.POST, "api", "stream", "process", body: .stream) { req async throws -> Response in
        let tileConfig = TileConfiguration(tileWidth: 512, tileHeight: 512, overlap: 4)
        let bufferPool = JPEGLSBufferPool.shared
        
        var bytesProcessed: Int64 = 0
        var tilesProcessed = 0
        
        // Stream processing with backpressure
        for try await chunk in req.body {
            // Process chunk
            bytesProcessed += Int64(chunk.readableBytes)
            
            // Use cache-friendly buffer for better performance
            let cacheBuffer = JPEGLSCacheFriendlyBuffer(
                width: tileConfig.tileWidth,
                height: tileConfig.tileHeight,
                componentCount: 1
            )
            
            tilesProcessed += 1
            
            // Apply backpressure if memory usage is high
            if bytesProcessed > 100_000_000 { // 100MB
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        req.logger.info("Streaming processing complete", metadata: [
            "bytes_processed": "\(bytesProcessed)",
            "tiles_processed": "\(tilesProcessed)"
        ])
        
        return Response(status: .ok, headers: [
            "X-Bytes-Processed": "\(bytesProcessed)",
            "X-Tiles-Processed": "\(tilesProcessed)"
        ])
    }
}
```

## Middleware & Integration

### Authentication Middleware

Protect your API endpoints:

```swift
import Vapor
import JWT

struct AuthPayload: JWTPayload {
    let sub: String
    let exp: Date
    let iat: Date
    
    func verify(using signer: JWTSigner) throws {
        guard exp > Date() else {
            throw JWTError.claimVerificationFailure(name: "exp", reason: "Token expired")
        }
    }
}

struct AuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Skip auth for health checks
        if request.url.path == "/health" {
            return try await next.respond(to: request)
        }
        
        guard let bearerToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing authorization token")
        }
        
        do {
            let payload = try request.jwt.verify(bearerToken, as: AuthPayload.self)
            request.auth.login(payload)
            return try await next.respond(to: request)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid token")
        }
    }
}

// Configure in your app
func configure(_ app: Application) throws {
    app.middleware.use(AuthMiddleware())
    app.jwt.signers.use(.hs256(key: "your-secret-key"))
}
```

### Rate Limiting

Implement rate limiting to protect your service:

```swift
import Vapor

actor RateLimiter {
    private var requests: [String: [Date]] = [:]
    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    
    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }
    
    func checkLimit(for identifier: String) -> Bool {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSeconds)
        
        // Clean old requests
        requests[identifier] = requests[identifier]?.filter { $0 > cutoff } ?? []
        
        let count = requests[identifier]?.count ?? 0
        
        if count >= maxRequests {
            return false
        }
        
        requests[identifier, default: []].append(now)
        return true
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let identifier = request.remoteAddress?.description ?? "unknown"
        
        let allowed = await limiter.checkLimit(for: identifier)
        
        guard allowed else {
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded")
        }
        
        return try await next.respond(to: request)
    }
}

// Configure in your app
func configure(_ app: Application) throws {
    let limiter = RateLimiter(maxRequests: 100, windowSeconds: 60)
    app.middleware.use(RateLimitMiddleware(limiter: limiter))
}
```

### Response Caching

Cache processed results for frequently accessed files:

```swift
import Vapor

actor ResponseCache {
    private var cache: [String: CachedResponse] = [:]
    private let maxSize: Int
    private let ttlSeconds: TimeInterval
    
    struct CachedResponse {
        let response: Response
        let timestamp: Date
    }
    
    init(maxSize: Int = 1000, ttlSeconds: TimeInterval = 3600) {
        self.maxSize = maxSize
        self.ttlSeconds = ttlSeconds
    }
    
    func get(key: String) -> Response? {
        guard let cached = cache[key] else { return nil }
        
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > ttlSeconds {
            cache.removeValue(forKey: key)
            return nil
        }
        
        return cached.response
    }
    
    func set(key: String, response: Response) {
        if cache.count >= maxSize {
            // Simple LRU: remove oldest
            if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        
        cache[key] = CachedResponse(response: response, timestamp: Date())
    }
}

struct CacheMiddleware: AsyncMiddleware {
    let cache: ResponseCache
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Only cache GET requests
        guard request.method == .GET else {
            return try await next.respond(to: request)
        }
        
        let cacheKey = request.url.string
        
        // Check cache
        if let cachedResponse = await cache.get(key: cacheKey) {
            request.logger.debug("Cache hit for \(cacheKey)")
            var response = cachedResponse
            response.headers.add(name: "X-Cache", value: "HIT")
            return response
        }
        
        // Process request
        var response = try await next.respond(to: request)
        
        // Cache successful responses
        if response.status == .ok {
            await cache.set(key: cacheKey, response: response)
            response.headers.add(name: "X-Cache", value: "MISS")
        }
        
        return response
    }
}

// Configure in your app
func configure(_ app: Application) throws {
    let cache = ResponseCache(maxSize: 1000, ttlSeconds: 3600)
    app.middleware.use(CacheMiddleware(cache: cache))
}
```

## Best Practices

### Error Handling

Always handle errors gracefully:

```swift
import Vapor
import JPEGLS

enum APIError: Error {
    case invalidImageData
    case encodingFailed(String)
    case decodingFailed(String)
    case fileTooLarge
}

extension APIError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .invalidImageData, .encodingFailed, .decodingFailed:
            return .badRequest
        case .fileTooLarge:
            return .payloadTooLarge
        }
    }
    
    var reason: String {
        switch self {
        case .invalidImageData:
            return "Invalid image data format"
        case .encodingFailed(let details):
            return "Encoding failed: \(details)"
        case .decodingFailed(let details):
            return "Decoding failed: \(details)"
        case .fileTooLarge:
            return "File exceeds maximum size limit"
        }
    }
}
```

### Logging

Implement structured logging:

```swift
import Vapor
import Logging

func configureLogging(_ app: Application) {
    // Configure log level based on environment
    app.logger.logLevel = app.environment == .production ? .info : .debug
    
    // Add custom metadata
    app.middleware.use(LoggingMiddleware())
}

struct LoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let startTime = Date()
        
        let response = try await next.respond(to: request)
        
        let duration = Date().timeIntervalSince(startTime)
        
        request.logger.info("Request completed", metadata: [
            "method": .string(request.method.rawValue),
            "path": .string(request.url.path),
            "status": .string("\(response.status.code)"),
            "duration_ms": .string("\(Int(duration * 1000))")
        ])
        
        return response
    }
}
```

### Monitoring

Add health checks and metrics:

```swift
import Vapor

func configureMonitoring(_ app: Application) {
    
    // Health check endpoint
    app.get("health") { req -> [String: Any] in
        return [
            "status": "healthy",
            "uptime": Date().timeIntervalSince(startTime),
            "version": "1.0.0"
        ]
    }
    
    // Metrics endpoint
    app.get("metrics") { req -> [String: Any] in
        return [
            "requests_total": requestCount,
            "requests_success": successCount,
            "requests_error": errorCount,
            "avg_processing_time_ms": avgProcessingTime
        ]
    }
}

private var startTime = Date()
private var requestCount = 0
private var successCount = 0
private var errorCount = 0
private var avgProcessingTime: Double = 0
```

## Conclusion

This guide provides comprehensive examples for integrating JLSwift into server-side Swift applications. Key takeaways:

1. **Use appropriate frameworks**: Vapor for full-featured apps, Hummingbird for lightweight services, NIO for custom protocols
2. **Optimize for performance**: Buffer pooling, tile-based processing, worker threads
3. **Handle errors gracefully**: Comprehensive error handling and validation
4. **Secure your API**: Authentication, rate limiting, input validation
5. **Monitor and log**: Health checks, structured logging, metrics
6. **Deploy properly**: Docker, Kubernetes, or systemd for production

For more information:
- [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) - General usage patterns
- [PERFORMANCE_TUNING.md](PERFORMANCE_TUNING.md) - Performance optimization guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [README.md](README.md) - Project overview and API reference
