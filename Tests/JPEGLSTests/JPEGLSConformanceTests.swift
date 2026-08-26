// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Raster Images Private Limited

import Foundation
import Testing
@testable import JPEGLS

/// Structural and decoder regression coverage using only deterministic,
/// Raster-authored data. Normative behaviour is derived from ITU-T.87; these
/// generated vectors intentionally do not claim independent implementation
/// interoperability.
@Suite("JPEG-LS Generated Vector Tests")
struct JPEGLSGeneratedVectorTests {
    struct TestCase: CustomTestStringConvertible, Sendable {
        let filename: String
        let width: Int
        let height: Int
        let bitsPerSample: Int
        let components: Int
        let near: Int
        let description: String

        var testDescription: String { description }
    }

    static let testCases: [TestCase] = [
        .init(filename: SyntheticFixtureName.rgb8PlanarLossless, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 0, description: "8-bit RGB planar, lossless"),
        .init(filename: SyntheticFixtureName.rgb8PlanarNear3, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 3, description: "8-bit RGB planar, near=3"),
        .init(filename: SyntheticFixtureName.rgb8LineLossless, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 0, description: "8-bit RGB line-interleaved, lossless"),
        .init(filename: SyntheticFixtureName.rgb8LineNear3, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 3, description: "8-bit RGB line-interleaved, near=3"),
        .init(filename: SyntheticFixtureName.rgb8SampleLossless, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 0, description: "8-bit RGB sample-interleaved, lossless"),
        .init(filename: SyntheticFixtureName.rgb8SampleNear3, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 3, description: "8-bit RGB sample-interleaved, near=3"),
        .init(filename: SyntheticFixtureName.gray12Lossless, width: 256, height: 256, bitsPerSample: 12, components: 1, near: 0, description: "12-bit grayscale, lossless"),
        .init(filename: SyntheticFixtureName.gray12Near3, width: 256, height: 256, bitsPerSample: 12, components: 1, near: 3, description: "12-bit grayscale, near=3"),
        .init(filename: SyntheticFixtureName.subsampled8Lossless, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 0, description: "8-bit sub-sampled zero-run layout, lossless"),
        .init(filename: SyntheticFixtureName.subsampled8Near3, width: 256, height: 256, bitsPerSample: 8, components: 3, near: 3, description: "8-bit sub-sampled zero-run layout, near=3 marker"),
        .init(filename: SyntheticFixtureName.gray8CustomLossless, width: 128, height: 128, bitsPerSample: 8, components: 1, near: 0, description: "8-bit custom preset, lossless"),
        .init(filename: SyntheticFixtureName.gray8CustomNear3, width: 128, height: 128, bitsPerSample: 8, components: 1, near: 3, description: "8-bit custom preset, near=3"),
    ]

    @Test("Generated vectors exist")
    func generatedVectorsExist() {
        for testCase in Self.testCases {
            #expect(SyntheticFixtureLoader.fixtureExists(named: testCase.filename))
        }
    }

    @Test("Parse generated vector headers", arguments: testCases)
    func parseGeneratedVectorHeaders(testCase: TestCase) throws {
        let data = try SyntheticFixtureLoader.loadFixture(named: testCase.filename)
        #expect(data.starts(with: [0xFF, 0xD8]))

        let result = try JPEGLSParser(data: data).parse()
        #expect(result.frameHeader.width == testCase.width)
        #expect(result.frameHeader.height == testCase.height)
        #expect(result.frameHeader.bitsPerSample == testCase.bitsPerSample)
        #expect(result.frameHeader.componentCount == testCase.components)
        #expect(result.scanHeaders.first?.near == testCase.near)
    }

    @Test("Validate generated vector structure", arguments: testCases)
    func validateGeneratedVectorStructure(testCase: TestCase) throws {
        let data = try SyntheticFixtureLoader.loadFixture(named: testCase.filename)
        #expect(data.count >= 4)
        #expect(data.starts(with: [0xFF, 0xD8]))
        #expect(data.suffix(2).elementsEqual([0xFF, 0xD9]))

        let result = try JPEGLSParser(data: data).parse()
        let configuration = JPEGLSDecoderConfiguration(
            width: result.frameHeader.width,
            height: result.frameHeader.height,
            bitsPerSample: result.frameHeader.bitsPerSample,
            componentCount: result.frameHeader.componentCount,
            near: result.scanHeaders.first?.near ?? 0,
            interleaveMode: result.scanHeaders.first?.interleaveMode ?? .none,
            colorTransformation: .none
        )
        #expect(configuration.width == testCase.width)
        #expect(configuration.height == testCase.height)
        #expect(configuration.bitsPerSample == testCase.bitsPerSample)
        #expect(configuration.componentCount == testCase.components)
    }

    @Test("Load generated PGM images")
    func loadGeneratedPGMImages() throws {
        for component in [
            SyntheticFixtureName.red8,
            SyntheticFixtureName.green8,
            SyntheticFixtureName.blue8,
        ] {
            let (width, height, maxVal, pixels) = try SyntheticFixtureLoader.loadPGM(named: component)
            #expect(width == 256)
            #expect(height == 256)
            #expect(maxVal == 255)
            #expect(pixels.count == 256 * 256)
        }

        let (width, height, maxVal, pixels) = try SyntheticFixtureLoader.loadPGM(
            named: SyntheticFixtureName.gray12
        )
        #expect(width == 256)
        #expect(height == 256)
        #expect(maxVal == 4095)
        #expect(pixels.count == 256 * 256)
    }

    @Test("Load generated PPM image")
    func loadGeneratedPPMImage() throws {
        let (width, height, maxVal, pixels) = try SyntheticFixtureLoader.loadPPM(
            named: SyntheticFixtureName.rgb8
        )
        #expect(width == 256)
        #expect(height == 256)
        #expect(maxVal == 255)
        #expect(pixels.count == 256 * 256 * 3)
    }
}

struct JPEGLSDecoderConfiguration {
    let width: Int
    let height: Int
    let bitsPerSample: Int
    let componentCount: Int
    let near: Int
    let interleaveMode: JPEGLSInterleaveMode
    let colorTransformation: JPEGLSColorTransformation
}

@Suite("JPEG-LS Generated Pixel Regression Tests")
struct JPEGLSGeneratedPixelRegressionTests {
    struct ComparisonTestCase: CustomTestStringConvertible, Sendable {
        let jlsFile: String
        let referenceFile: String
        let width: Int
        let height: Int
        let components: Int
        let near: Int
        let description: String

        var testDescription: String { description }
    }

    static let comparisonTestCases: [ComparisonTestCase] = [
        .init(jlsFile: SyntheticFixtureName.rgb8PlanarLossless, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 0, description: "8-bit RGB planar, lossless"),
        .init(jlsFile: SyntheticFixtureName.rgb8PlanarNear3, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 3, description: "8-bit RGB planar, near=3"),
        .init(jlsFile: SyntheticFixtureName.rgb8LineLossless, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 0, description: "8-bit RGB line-interleaved, lossless"),
        .init(jlsFile: SyntheticFixtureName.rgb8LineNear3, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 3, description: "8-bit RGB line-interleaved, near=3"),
        .init(jlsFile: SyntheticFixtureName.rgb8SampleLossless, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 0, description: "8-bit RGB sample-interleaved, lossless"),
        .init(jlsFile: SyntheticFixtureName.rgb8SampleNear3, referenceFile: SyntheticFixtureName.rgb8, width: 256, height: 256, components: 3, near: 3, description: "8-bit RGB sample-interleaved, near=3"),
        .init(jlsFile: SyntheticFixtureName.gray12Lossless, referenceFile: SyntheticFixtureName.gray12, width: 256, height: 256, components: 1, near: 0, description: "12-bit grayscale, lossless"),
        .init(jlsFile: SyntheticFixtureName.gray12Near3, referenceFile: SyntheticFixtureName.gray12, width: 256, height: 256, components: 1, near: 3, description: "12-bit grayscale, near=3"),
        .init(jlsFile: SyntheticFixtureName.gray8CustomLossless, referenceFile: SyntheticFixtureName.blue8HalfResolution, width: 128, height: 128, components: 1, near: 0, description: "8-bit custom preset, lossless"),
        .init(jlsFile: SyntheticFixtureName.gray8CustomNear3, referenceFile: SyntheticFixtureName.blue8HalfResolution, width: 128, height: 128, components: 1, near: 3, description: "8-bit custom preset, near=3"),
    ]

    @Test("Compare decoded pixels with generated source", arguments: comparisonTestCases)
    func compareDecodedPixels(testCase: ComparisonTestCase) throws {
        let encoded = try SyntheticFixtureLoader.loadFixture(named: testCase.jlsFile)
        let decoded = try JPEGLSDecoder().decode(encoded)
        let reference: [UInt16]
        if testCase.referenceFile.hasSuffix(".ppm") {
            reference = try SyntheticFixtureLoader.loadPPM(named: testCase.referenceFile).pixels
        } else {
            reference = try SyntheticFixtureLoader.loadPGM(named: testCase.referenceFile).pixels
        }

        #expect(decoded.frameHeader.width == testCase.width)
        #expect(decoded.frameHeader.height == testCase.height)
        #expect(decoded.components.count == testCase.components)
        for componentIndex in 0..<testCase.components {
            let componentReference: [UInt16]
            if testCase.components == 1 {
                componentReference = reference
            } else {
                componentReference = stride(
                    from: componentIndex,
                    to: reference.count,
                    by: testCase.components
                ).map { reference[$0] }
            }
            for row in 0..<testCase.height {
                for column in 0..<testCase.width {
                    let actual = decoded.components[componentIndex].pixels[row][column]
                    let expected = Int(componentReference[row * testCase.width + column])
                    #expect(abs(actual - expected) <= testCase.near)
                }
            }
        }
    }

    @Test("Decode every generated non-subsampled vector")
    func decodeEveryGeneratedVector() throws {
        for testCase in Self.comparisonTestCases {
            let data = try SyntheticFixtureLoader.loadFixture(named: testCase.jlsFile)
            let decoded = try JPEGLSDecoder().decode(data)
            #expect(decoded.frameHeader.width > 0)
            #expect(decoded.frameHeader.height > 0)
            #expect(!decoded.components.isEmpty)
        }
    }
}

@Suite("JPEG-LS Sub-sampled Zero-Run Layout Tests")
struct JPEGLSSubsampledZeroRunLayoutTests {
    struct TestCase: CustomTestStringConvertible, Sendable {
        let jlsFile: String
        let near: Int
        let description: String
        var testDescription: String { description }
    }

    struct ComponentReference: Sendable {
        let width: Int
        let height: Int
        let componentID: UInt8
    }

    static let componentReferences: [ComponentReference] = [
        .init(width: 256, height: 256, componentID: 1),
        .init(width: 256, height: 64, componentID: 2),
        .init(width: 128, height: 128, componentID: 3),
    ]

    static let testCases: [TestCase] = [
        .init(jlsFile: SyntheticFixtureName.subsampled8Lossless, near: 0, description: "Sub-sampled zero-run lossless layout"),
        .init(jlsFile: SyntheticFixtureName.subsampled8Near3, near: 3, description: "Sub-sampled zero-run layout with NEAR=3 marker"),
    ]

    @Test("Decode sub-sampled zero-run component layout", arguments: testCases)
    func decodeSubsampledZeroRunLayout(testCase: TestCase) throws {
        let data = try SyntheticFixtureLoader.loadFixture(named: testCase.jlsFile)
        let parsed = try JPEGLSParser(data: data).parse()
        let decoded = try JPEGLSDecoder().decode(data)
        #expect(parsed.scanHeaders.first?.near == testCase.near)
        #expect(parsed.scanHeaders.first?.interleaveMode == .line)
        #expect(decoded.frameHeader.width == 256)
        #expect(decoded.frameHeader.height == 256)
        #expect(decoded.components.count == 3)

        for reference in Self.componentReferences {
            let component = try #require(
                decoded.components.first { $0.id == reference.componentID }
            )
            #expect(component.pixels.count == reference.height)
            #expect(component.pixels.first?.count == reference.width)
            for row in 0..<reference.height {
                for column in 0..<reference.width {
                    #expect(component.pixels[row][column] == 0)
                }
            }
        }
    }
}
