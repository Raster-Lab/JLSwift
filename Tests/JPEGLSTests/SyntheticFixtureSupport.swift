// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Raster Images Private Limited

import Foundation
@testable import JPEGLS

/// Stable names for the deterministic, Raster-authored test corpus.
enum SyntheticFixtureName {
    static let rgb8 = "synthetic-rgb8.ppm"
    static let rgb8Transform = "synthetic-rgb8-transform.ppm"
    static let red8 = "synthetic-red8.pgm"
    static let green8 = "synthetic-green8.pgm"
    static let blue8 = "synthetic-blue8.pgm"
    static let green8QuarterHeight = "synthetic-green8-quarter-height.pgm"
    static let blue8HalfResolution = "synthetic-blue8-half-resolution.pgm"
    static let gray12 = "synthetic-gray12.pgm"

    static let rgb8PlanarLossless = "synthetic-rgb8-planar-lossless.jls"
    static let rgb8PlanarNear3 = "synthetic-rgb8-planar-near3.jls"
    static let rgb8LineLossless = "synthetic-rgb8-line-lossless.jls"
    static let rgb8LineNear3 = "synthetic-rgb8-line-near3.jls"
    static let rgb8SampleLossless = "synthetic-rgb8-sample-lossless.jls"
    static let rgb8SampleNear3 = "synthetic-rgb8-sample-near3.jls"
    static let gray12Lossless = "synthetic-gray12-lossless.jls"
    static let gray12Near3 = "synthetic-gray12-near3.jls"
    static let gray8CustomLossless = "synthetic-gray8-custom-lossless.jls"
    static let gray8CustomNear3 = "synthetic-gray8-custom-near3.jls"
    static let subsampled8Lossless = "synthetic-subsampled8-lossless.jls"
    static let subsampled8Near3 = "synthetic-subsampled8-near3.jls"
}

enum SyntheticFixtureError: Error, CustomStringConvertible {
    case unknownFixture(String)
    case invalidFormat(String)
    case generationFailed(String)

    var description: String {
        switch self {
        case .unknownFixture(let name):
            return "Unknown synthetic fixture: \(name)"
        case .invalidFormat(let message):
            return "Invalid synthetic fixture format: \(message)"
        case .generationFailed(let message):
            return "Synthetic fixture generation failed: \(message)"
        }
    }
}

/// Creates the test corpus in memory from deterministic formulas, JLSwift's
/// public encoder, and two hand-authored zero-run streams. No copied images,
/// compressed streams, or external codec are required. These are regression
/// tests; independent cross-implementation conformance remains pending.
struct SyntheticFixtureLoader {
    private enum State: Sendable {
        case ready([String: Data])
        case failed(String)
    }

    private static let state: State = {
        do {
            return .ready(try makeFixtures())
        } catch {
            return .failed(String(describing: error))
        }
    }()

    static func loadFixture(named filename: String) throws -> Data {
        switch state {
        case .failed(let message):
            throw SyntheticFixtureError.generationFailed(message)
        case .ready(let fixtures):
            guard let data = fixtures[filename] else {
                throw SyntheticFixtureError.unknownFixture(filename)
            }
            return data
        }
    }

    static func fixtureExists(named filename: String) -> Bool {
        guard case .ready(let fixtures) = state else { return false }
        return fixtures[filename] != nil
    }

    static func loadPGM(
        named filename: String
    ) throws -> (width: Int, height: Int, maxVal: Int, pixels: [UInt16]) {
        try parsePNM(data: loadFixture(named: filename), expectedMagic: "P5")
    }

    static func loadPPM(
        named filename: String
    ) throws -> (width: Int, height: Int, maxVal: Int, pixels: [UInt16]) {
        try parsePNM(data: loadFixture(named: filename), expectedMagic: "P6")
    }

    private static func makeFixtures() throws -> [String: Data] {
        let width = 256
        let height = 256
        let red = makePlane(width: width, height: height, channel: 0)
        let green = makePlane(width: width, height: height, channel: 1)
        let blue = makePlane(width: width, height: height, channel: 2)
        let gray12 = (0..<height).map { row in
            (0..<width).map { column in
                (column * 37 + row * 61 + ((column * row) >> 2) + ((column ^ row) * 11)) & 0x0FFF
            }
        }

        let greenQuarterHeight = stride(from: 0, to: height, by: 4).map { green[$0] }
        let blueHalfResolution = stride(from: 0, to: height, by: 2).map { row in
            stride(from: 0, to: width, by: 2).map { column in blue[row][column] }
        }
        let transformRed = makeNoisePlane(width: 16, height: 16, seed: 0x1020_3040)
        let transformGreen = makeNoisePlane(width: 16, height: 16, seed: 0x5060_7080)
        let transformBlue = makeNoisePlane(width: 16, height: 16, seed: 0x90A0_B0C0)

        var fixtures: [String: Data] = [
            SyntheticFixtureName.rgb8: makePPM(red: red, green: green, blue: blue, maxVal: 255),
            SyntheticFixtureName.rgb8Transform: makePPM(
                red: transformRed,
                green: transformGreen,
                blue: transformBlue,
                maxVal: 255
            ),
            SyntheticFixtureName.red8: makePGM(pixels: red, maxVal: 255),
            SyntheticFixtureName.green8: makePGM(pixels: green, maxVal: 255),
            SyntheticFixtureName.blue8: makePGM(pixels: blue, maxVal: 255),
            SyntheticFixtureName.green8QuarterHeight: makePGM(pixels: greenQuarterHeight, maxVal: 255),
            SyntheticFixtureName.blue8HalfResolution: makePGM(pixels: blueHalfResolution, maxVal: 255),
            SyntheticFixtureName.gray12: makePGM(pixels: gray12, maxVal: 4095),
        ]

        let encoder = JPEGLSEncoder()
        let rgbImage = try MultiComponentImageData.rgb(
            redPixels: red,
            greenPixels: green,
            bluePixels: blue,
            bitsPerSample: 8
        )
        let gray12Image = try MultiComponentImageData.grayscale(pixels: gray12, bitsPerSample: 12)
        let customGrayImage = try MultiComponentImageData.grayscale(
            pixels: blueHalfResolution,
            bitsPerSample: 8
        )

        let rgbCases: [(String, JPEGLSInterleaveMode, Int)] = [
            (SyntheticFixtureName.rgb8PlanarLossless, .none, 0),
            (SyntheticFixtureName.rgb8PlanarNear3, .none, 3),
            (SyntheticFixtureName.rgb8LineLossless, .line, 0),
            (SyntheticFixtureName.rgb8LineNear3, .line, 3),
            (SyntheticFixtureName.rgb8SampleLossless, .sample, 0),
            (SyntheticFixtureName.rgb8SampleNear3, .sample, 3),
        ]
        for (name, mode, near) in rgbCases {
            let configuration = try JPEGLSEncoder.Configuration(
                near: near,
                interleaveMode: mode
            )
            fixtures[name] = try encoder.encode(rgbImage, configuration: configuration)
        }

        fixtures[SyntheticFixtureName.gray12Lossless] = try encoder.encode(
            gray12Image,
            configuration: .init(near: 0)
        )
        fixtures[SyntheticFixtureName.gray12Near3] = try encoder.encode(
            gray12Image,
            configuration: .init(near: 3)
        )

        let customPreset = try JPEGLSPresetParameters(
            maxValue: 255,
            threshold1: 9,
            threshold2: 9,
            threshold3: 9,
            reset: 31
        )
        fixtures[SyntheticFixtureName.gray8CustomLossless] = try encoder.encode(
            customGrayImage,
            configuration: .init(near: 0, presetParameters: customPreset)
        )
        fixtures[SyntheticFixtureName.gray8CustomNear3] = try encoder.encode(
            customGrayImage,
            configuration: .init(near: 3, presetParameters: customPreset)
        )

        fixtures[SyntheticFixtureName.subsampled8Lossless] = try makeSubsampledStream(near: 0)
        fixtures[SyntheticFixtureName.subsampled8Near3] = try makeSubsampledStream(near: 3)

        return fixtures
    }

    /// The formula combines smooth structure with channel-specific detail. The
    /// three planes remain decorrelated after HP1/HP2/HP3 transforms, avoiding
    /// accidental constant transformed planes while remaining reproducible.
    private static func makePlane(width: Int, height: Int, channel: Int) -> [[Int]] {
        (0..<height).map { row in
            (0..<width).map { column in
                switch channel {
                case 0:
                    return (column * 3 + row * 5 + ((column * row) >> 6)) & 0xFF
                case 1:
                    return (column * 5 + row * 2 + ((column * row) >> 7) + 17) & 0xFF
                default:
                    return (column * 2 + row * 7 + ((column * row) >> 5) + 43) & 0xFF
                }
            }
        }
    }

    private static func makeNoisePlane(width: Int, height: Int, seed: UInt64) -> [[Int]] {
        var state = seed
        return (0..<height).map { _ in
            (0..<width).map { _ in
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Int((state >> 33) & 0xFF)
            }
        }
    }

    private static func makePGM(pixels: [[Int]], maxVal: Int) -> Data {
        let height = pixels.count
        let width = pixels.first?.count ?? 0
        var data = Data("P5\n\(width) \(height)\n\(maxVal)\n".utf8)
        appendSamples(pixels.joined(), maxVal: maxVal, to: &data)
        return data
    }

    private static func makePPM(
        red: [[Int]],
        green: [[Int]],
        blue: [[Int]],
        maxVal: Int
    ) -> Data {
        let height = red.count
        let width = red.first?.count ?? 0
        var data = Data("P6\n\(width) \(height)\n\(maxVal)\n".utf8)
        for row in 0..<height {
            for column in 0..<width {
                appendSample(red[row][column], maxVal: maxVal, to: &data)
                appendSample(green[row][column], maxVal: maxVal, to: &data)
                appendSample(blue[row][column], maxVal: maxVal, to: &data)
            }
        }
        return data
    }

    private static func appendSamples<S: Sequence>(
        _ samples: S,
        maxVal: Int,
        to data: inout Data
    ) where S.Element == Int {
        for sample in samples {
            appendSample(sample, maxVal: maxVal, to: &data)
        }
    }

    private static func appendSample(_ sample: Int, maxVal: Int, to data: inout Data) {
        if maxVal < 256 {
            data.append(UInt8(sample))
        } else {
            data.append(UInt8((sample >> 8) & 0xFF))
            data.append(UInt8(sample & 0xFF))
        }
    }

    /// Builds a minimal line-interleaved sub-sampled stream whose three planes
    /// contain zero-valued samples. Full zero lines are represented entirely by
    /// JPEG-LS run-continuation bits, so this exercises the sub-sampled stripe
    /// schedule without requiring the production encoder to accept sub-sampled
    /// component planes.
    private static func makeSubsampledStream(near: Int) throws -> Data {
        guard (0...255).contains(near) else {
            throw SyntheticFixtureError.generationFailed("Invalid NEAR value \(near)")
        }

        var output = Data([0xFF, 0xD8])
        appendFrameHeader(
            width: 256,
            height: 256,
            components: [(1, 2, 4), (2, 2, 1), (3, 1, 2)],
            to: &output
        )
        appendSubsampledScanHeader(near: near, to: &output)

        let scanWriter = JPEGLSBitstreamWriter(capacity: 80)
        var runIndices = [0, 0, 0]
        for _ in 0..<64 {
            for _ in 0..<4 {
                writeZeroRunLine(width: 256, runIndex: &runIndices[0], to: scanWriter)
            }
            writeZeroRunLine(width: 256, runIndex: &runIndices[1], to: scanWriter)
            for _ in 0..<2 {
                writeZeroRunLine(width: 128, runIndex: &runIndices[2], to: scanWriter)
            }
        }
        scanWriter.flush()
        output.append(try scanWriter.getData())

        output.append(contentsOf: [0xFF, 0xD9])
        return output
    }

    private static let runLengthJTable = [
        0, 0, 0, 0, 1, 1, 1, 1,
        2, 2, 2, 2, 3, 3, 3, 3,
        4, 4, 5, 5, 6, 6, 7, 7,
        8, 9, 10, 11, 12, 13, 14, 15,
    ]

    private static func writeZeroRunLine(
        width: Int,
        runIndex: inout Int,
        to writer: JPEGLSBitstreamWriter
    ) {
        var remaining = width
        while remaining > 0 {
            let blockSize = 1 << runLengthJTable[runIndex]
            writer.writeBits(1, count: 1)
            if remaining >= blockSize {
                remaining -= blockSize
                runIndex = min(runIndex + 1, runLengthJTable.count - 1)
            } else {
                remaining = 0
            }
        }
    }

    private static func appendSubsampledScanHeader(near: Int, to data: inout Data) {
        data.append(contentsOf: [
            0xFF, 0xDA,
            0x00, 0x0C,
            0x03,
            0x01, 0x00,
            0x02, 0x00,
            0x03, 0x00,
            UInt8(near), 0x01, 0x00,
        ])
    }

    private static func appendFrameHeader(
        width: Int,
        height: Int,
        components: [(id: UInt8, horizontal: UInt8, vertical: UInt8)],
        to data: inout Data
    ) {
        data.append(contentsOf: [0xFF, 0xF7])
        appendUInt16(8 + 3 * components.count, to: &data)
        data.append(8)
        appendUInt16(height, to: &data)
        appendUInt16(width, to: &data)
        data.append(UInt8(components.count))
        for component in components {
            data.append(component.id)
            data.append((component.horizontal << 4) | component.vertical)
            data.append(0)
        }
    }

    private static func appendUInt16(_ value: Int, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func parsePNM(
        data: Data,
        expectedMagic: String
    ) throws -> (width: Int, height: Int, maxVal: Int, pixels: [UInt16]) {
        var headerEnd = 0
        var newlineCount = 0
        for index in 0..<min(data.count, 100) where data[index] == 0x0A {
            newlineCount += 1
            if newlineCount == 3 {
                headerEnd = index + 1
                break
            }
        }
        guard headerEnd > 0,
              let header = String(data: data[..<headerEnd], encoding: .ascii) else {
            throw SyntheticFixtureError.invalidFormat("PNM header is incomplete")
        }
        let lines = header.split(whereSeparator: \.isNewline)
        guard lines.count >= 3, String(lines[0]) == expectedMagic else {
            throw SyntheticFixtureError.invalidFormat("Expected \(expectedMagic) header")
        }
        let dimensions = lines[1].split(separator: " ")
        guard dimensions.count == 2,
              let width = Int(dimensions[0]),
              let height = Int(dimensions[1]),
              let maxVal = Int(lines[2]) else {
            throw SyntheticFixtureError.invalidFormat("Invalid PNM dimensions or MAXVAL")
        }

        let bytes = data[headerEnd...]
        var pixels: [UInt16] = []
        pixels.reserveCapacity(width * height * (expectedMagic == "P6" ? 3 : 1))
        if maxVal < 256 {
            pixels.append(contentsOf: bytes.map(UInt16.init))
        } else {
            guard bytes.count.isMultiple(of: 2) else {
                throw SyntheticFixtureError.invalidFormat("Odd 16-bit PNM payload length")
            }
            var index = bytes.startIndex
            while index < bytes.endIndex {
                pixels.append((UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1]))
                index += 2
            }
        }
        return (width, height, maxVal, pixels)
    }
}
