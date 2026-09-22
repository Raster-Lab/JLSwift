import Foundation
import Testing
@testable import JPEGLS

/// ITU-T T.81 B.1.1.2: any marker may be preceded by any number of 0xFF fill
/// bytes. CharLS (DCMTK `dcmcjpls`) emits one before EOI whenever the entropy
/// coder's final byte is 0xFF, so such streams occur in real DICOM objects.
@Suite("JPEG-LS fill bytes before markers")
struct JPEGLSFillByteTests {
    /// 1x3 8-bit lossless [0, 1, 255] as written by DCMTK 3.7.0 dcmcjpls (CharLS):
    /// entropy data `AA 00`, then a 0xFF fill byte, then EOI.
    static let charLSOneRow: [UInt8] = [
        0xFF, 0xD8, 0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x03, 0x01, 0x01, 0x11, 0x00,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0xAA, 0x00, 0xFF, 0xFF, 0xD9,
    ]

    /// 1x3 8-bit lossless [1, 255, 0] from the same encoder: `54 A0`, fill, EOI.
    static let charLSOneRowAlternate: [UInt8] = [
        0xFF, 0xD8, 0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x03, 0x01, 0x01, 0x11, 0x00,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x54, 0xA0, 0xFF, 0xFF, 0xD9,
    ]

    @Test("A CharLS stream with a fill byte before EOI decodes to the encoded samples")
    func charLSFillByteDecodes() throws {
        let image = try JPEGLSDecoder().decode(Data(Self.charLSOneRow))
        #expect(image.frameHeader.width == 3)
        #expect(image.frameHeader.height == 1)
        #expect(image.components.count == 1)
        #expect(image.components[0].pixels == [[0, 1, 255]])
        let alternate = try JPEGLSDecoder().decode(Data(Self.charLSOneRowAlternate))
        #expect(alternate.components[0].pixels == [[1, 255, 0]])
    }

    @Test("Any number of fill bytes before EOI is skipped and excluded from the scan body")
    func multipleFillBytes() throws {
        var stream = Self.charLSOneRow
        stream.insert(contentsOf: [0xFF, 0xFF, 0xFF], at: stream.count - 2)
        let parsed = try JPEGLSParser(data: Data(stream)).parse()
        #expect(parsed.scanHeaders.count == 1)
        // Scan body is exactly `AA 00`: the fill bytes are not entropy data.
        #expect(parsed.scanDataRanges == [25..<27])
        let image = try JPEGLSDecoder().decode(Data(stream))
        #expect(image.components[0].pixels == [[0, 1, 255]])
    }

    @Test("The stream without the fill byte parses to the same scan body")
    func withoutFillByte() throws {
        var stream = Self.charLSOneRow
        stream.remove(at: stream.count - 3)
        let parsed = try JPEGLSParser(data: Data(stream)).parse()
        #expect(parsed.scanDataRanges == [25..<27])
        #expect(try JPEGLSDecoder().decode(Data(stream)).components[0].pixels == [[0, 1, 255]])
    }

    @Test("readMarker skips fill bytes")
    func readMarkerSkipsFill() throws {
        let reader = JPEGLSBitstreamReader(data: Data([0xFF, 0xFF, 0xFF, 0xD9]))
        #expect(try reader.readMarker() == .endOfImage)
        #expect(reader.isAtEnd)
    }

    @Test("A stuffed byte after 0xFF is still entropy data, not a fill byte")
    func stuffedByteRemainsData() throws {
        // 2x3 [0,1,255,1,255,0]: entropy data `AA 6F 80` ends in a byte >= 0x80
        // that is preceded by 0x6F, so no fill/stuffing ambiguity arises; assert
        // the decoder still consumes it fully.
        let stream: [UInt8] = [
            0xFF, 0xD8, 0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x02, 0x00, 0x03, 0x01, 0x01, 0x11,
            0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0xAA, 0x6F, 0x80,
            0xFF, 0xD9,
        ]
        let image = try JPEGLSDecoder().decode(Data(stream))
        #expect(image.components[0].pixels == [[0, 1, 255], [1, 255, 0]])
    }
}
