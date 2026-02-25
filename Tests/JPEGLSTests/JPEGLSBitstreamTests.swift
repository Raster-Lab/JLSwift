/// Tests for JPEG-LS bitstream reader and writer

import Testing
import Foundation
@testable import JPEGLS

@Suite("JPEG-LS Bitstream Reader Tests")
struct JPEGLSBitstreamReaderTests {
    @Test("Read single byte")
    func testReadByte() throws {
        let data = Data([0x12, 0x34, 0x56])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(try reader.readByte() == 0x12)
        #expect(try reader.readByte() == 0x34)
        #expect(try reader.readByte() == 0x56)
    }
    
    @Test("Read multiple bytes")
    func testReadBytes() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let reader = JPEGLSBitstreamReader(data: data)
        
        let bytes = try reader.readBytes(3)
        #expect(bytes == Data([0x12, 0x34, 0x56]))
        #expect(try reader.readByte() == 0x78)
    }
    
    @Test("Read 16-bit big-endian value")
    func testReadUInt16() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(try reader.readUInt16() == 0x1234)
        #expect(try reader.readUInt16() == 0x5678)
    }
    
    @Test("Peek byte without advancing")
    func testPeekByte() throws {
        let data = Data([0x12, 0x34])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(reader.peekByte() == 0x12)
        #expect(reader.peekByte() == 0x12)  // Still the same
        _ = try reader.readByte()
        #expect(reader.peekByte() == 0x34)
    }
    
    @Test("Read marker")
    func testReadMarker() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let reader = JPEGLSBitstreamReader(data: data)
        
        let marker1 = try reader.readMarker()
        #expect(marker1 == .startOfImage)
        
        let marker2 = try reader.readMarker()
        #expect(marker2 == .endOfImage)
    }
    
    @Test("Read invalid marker throws error")
    func testReadInvalidMarker() {
        let data = Data([0xFF, 0x01])  // Invalid marker
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try reader.readMarker()
        }
    }
    
    @Test("Read marker with missing prefix throws error")
    func testReadMarkerMissingPrefix() {
        let data = Data([0xD8, 0xFF])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(throws: JPEGLSError.self) {
            try reader.readMarker()
        }
    }
    
    @Test("Find next marker")
    func testFindNextMarker() throws {
        let data = Data([0x12, 0x34, 0x56, 0xFF, 0xD8])
        let reader = JPEGLSBitstreamReader(data: data)
        
        let marker = try reader.findNextMarker()
        #expect(marker == .startOfImage)
    }
    
    @Test("Find next marker skips stuffed bytes")
    func testFindNextMarkerSkipsStuffing() throws {
        let data = Data([0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD8])
        let reader = JPEGLSBitstreamReader(data: data)
        
        let marker = try reader.findNextMarker()
        #expect(marker == .startOfImage)
    }
    
    @Test("Read bits")
    func testReadBits() throws {
        // Binary: 10110011 = 0xB3
        let data = Data([0xB3])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(try reader.readBits(1) == 1)  // 1
        #expect(try reader.readBits(2) == 1)  // 01
        #expect(try reader.readBits(3) == 4)  // 100
        #expect(try reader.readBits(2) == 3)  // 11
    }
    
    @Test("Read bits across byte boundary")
    func testReadBitsAcrossByteBoundary() throws {
        // ISO 14495-1 §9.1 bit-level stuffing: FF 00 contributes 8 bits (FF) + 7 bits from
        // the stuffed byte (0x00's lower 7 bits = 0000000), then 0xAA contributes 8 bits.
        // Total 23-bit stream: 11111111 0000000 10101010
        let data = Data([0xFF, 0x00, 0xAA])
        let reader = JPEGLSBitstreamReader(data: data)

        #expect(try reader.readBits(4) == 0xF)   // 1111
        #expect(try reader.readBits(8) == 0xF0)  // 11110000
    }

    @Test("Read bits handles byte stuffing")
    func testReadBitsHandlesStuffing() throws {
        // ISO 14495-1 §9.1 bit-level stuffing: FF XX (XX < 0x80) contributes 8 + 7 = 15 bits.
        // FF 00: 8 bits (11111111) + 7 bits from 0x00 (0000000), then AA: 8 bits (10101010).
        // Total 23-bit stream: 11111111 0000000 10101010
        let data = Data([0xFF, 0x00, 0xAA])
        let reader = JPEGLSBitstreamReader(data: data)

        #expect(try reader.readBits(8) == 0xFF)
        #expect(try reader.readBits(7) == 0x00)  // 7 data bits from the stuffed 0x00
        #expect(try reader.readBits(8) == 0xAA)
    }
    
    @Test("Current position tracking")
    func testCurrentPosition() throws {
        let data = Data([0x12, 0x34, 0x56])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(reader.currentPosition == 0)
        _ = try reader.readByte()
        #expect(reader.currentPosition == 1)
        _ = try reader.readByte()
        #expect(reader.currentPosition == 2)
    }
    
    @Test("Bytes remaining")
    func testBytesRemaining() throws {
        let data = Data([0x12, 0x34, 0x56])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(reader.bytesRemaining == 3)
        _ = try reader.readByte()
        #expect(reader.bytesRemaining == 2)
        _ = try reader.readBytes(2)
        #expect(reader.bytesRemaining == 0)
    }
    
    @Test("Is at end")
    func testIsAtEnd() throws {
        let data = Data([0x12])
        let reader = JPEGLSBitstreamReader(data: data)
        
        #expect(!reader.isAtEnd)
        _ = try reader.readByte()
        #expect(reader.isAtEnd)
    }
    
    @Test("Reset bit buffer")
    func testResetBitBuffer() throws {
        // Use two non-FF bytes so no stuffing logic is triggered.
        // Read 4 bits of the first byte, reset, then read the second byte.
        let data = Data([0xAB, 0xAA])
        let reader = JPEGLSBitstreamReader(data: data)
        
        _ = try reader.readBits(4)
        reader.resetBitBuffer()
        
        // After reset, should read from next byte boundary
        #expect(try reader.readByte() == 0xAA)
    }
    
    @Test("Seek to position")
    func testSeek() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let reader = JPEGLSBitstreamReader(data: data)
        
        try reader.seek(to: 2)
        #expect(try reader.readByte() == 0x56)
        
        try reader.seek(to: 0)
        #expect(try reader.readByte() == 0x12)
    }
    
    @Test("Seek resets bit buffer")
    func testSeekResetsBitBuffer() throws {
        let data = Data([0xFF, 0xAA, 0xBB])
        let reader = JPEGLSBitstreamReader(data: data)
        
        _ = try reader.readBits(4)
        try reader.seek(to: 1)
        
        // Should read from byte boundary after seek
        #expect(try reader.readByte() == 0xAA)
    }
    
    @Test("Read beyond end throws error")
    func testReadBeyondEnd() {
        let data = Data([0x12])
        let reader = JPEGLSBitstreamReader(data: data)
        
        _ = try? reader.readByte()
        
        #expect(throws: JPEGLSError.self) {
            try reader.readByte()
        }
    }
}

@Suite("JPEG-LS Bitstream Writer Tests")
struct JPEGLSBitstreamWriterTests {
    @Test("Write single byte")
    func testWriteByte() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeByte(0x12)
        writer.writeByte(0x34)
        
        let data = try writer.getData()
        #expect(data == Data([0x12, 0x34]))
    }
    
    @Test("Write byte does not add stuffing")
    func testWriteByteNoStuffing() throws {
        let writer = JPEGLSBitstreamWriter()

        writer.writeByte(0xFF)
        writer.writeByte(0xAA)

        // writeByte is a plain byte-write for structured data; no stuffing added
        let data = try writer.getData()
        #expect(data == Data([0xFF, 0xAA]))
    }

    @Test("Write multiple bytes does not add stuffing")
    func testWriteBytes() throws {
        let writer = JPEGLSBitstreamWriter()

        writer.writeBytes(Data([0x12, 0x34, 0xFF, 0x56]))

        // writeBytes is a plain bulk write; no stuffing added
        let data = try writer.getData()
        #expect(data == Data([0x12, 0x34, 0xFF, 0x56]))
    }
    
    @Test("Write 16-bit big-endian value")
    func testWriteUInt16() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeUInt16(0x1234)
        writer.writeUInt16(0x5678)
        
        let data = try writer.getData()
        #expect(data == Data([0x12, 0x34, 0x56, 0x78]))
    }
    
    @Test("Write marker")
    func testWriteMarker() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeMarker(.startOfImage)
        writer.writeMarker(.endOfImage)
        
        let data = try writer.getData()
        #expect(data == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }
    
    @Test("Write marker does not stuff marker bytes")
    func testWriteMarkerNoStuffing() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeMarker(.startOfImage)  // 0xFF 0xD8
        
        let data = try writer.getData()
        // Should be exactly 2 bytes, no stuffing
        #expect(data == Data([0xFF, 0xD8]))
    }
    
    @Test("Write bits")
    func testWriteBits() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeBits(0b1011, count: 4)  // 1011
        writer.writeBits(0b0011, count: 4)  // 0011
        writer.flush()
        
        // Combined: 10110011 = 0xB3
        let data = try writer.getData()
        #expect(data == Data([0xB3]))
    }
    
    @Test("Write bits across byte boundary with bit-level stuffing")
    func testWriteBitsAcrossByteBoundary() throws {
        let writer = JPEGLSBitstreamWriter()

        writer.writeBits(0xF, count: 4)    // 1111
        writer.writeBits(0xF0, count: 8)   // 11110000
        writer.flush()

        // Combined 12 bits: 1111 1111 0000
        // First 8 bits form 0xFF → emitted, then stuff bit (0) inserted.
        // Remaining 5 bits after stuffing: stuff(0) + 0000 = 00000, padded to 0x00.
        // Result: 0xFF then stuffed-byte 0x00.
        let data = try writer.getData()
        #expect(data == Data([0xFF, 0x00]))
    }

    @Test("Write bits handles bit-level byte stuffing")
    func testWriteBitsStuffing() throws {
        let writer = JPEGLSBitstreamWriter()

        writer.writeBits(0xFF, count: 8)
        writer.writeBits(0xAA, count: 8)
        writer.flush()

        // Bit stream: 11111111 10101010 (16 bits).
        // 0xFF emitted; stuff bit (0) inserted next.
        // Next 7 bits of 0xAA (1010101) fill the stuffed byte: 0 1010101 = 0x55.
        // Last bit of 0xAA (0) flushed, padded to 0x00.
        let data = try writer.getData()
        #expect(data == Data([0xFF, 0x55, 0x00]))
    }
    
    @Test("Flush pads with zeros")
    func testFlushPadding() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeBits(0b101, count: 3)
        writer.flush()
        
        // Result: 10100000 = 0xA0 (padded with 5 zeros)
        let data = try writer.getData()
        #expect(data == Data([0xA0]))
    }
    
    @Test("Reset bit buffer")
    func testResetBitBuffer() throws {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeBits(0b101, count: 3)
        writer.resetBitBuffer()  // Should flush
        
        writer.writeByte(0xAA)
        
        let data = try writer.getData()
        #expect(data == Data([0xA0, 0xAA]))  // 0xA0 from flushed bits, then 0xAA
    }
    
    @Test("Write marker segment")
    func testWriteMarkerSegment() throws {
        let writer = JPEGLSBitstreamWriter()
        
        let payload = Data([0x01, 0x02, 0x03])
        writer.writeMarkerSegment(marker: .comment, payload: payload)
        
        let data = try writer.getData()
        // Marker (2) + Length (2) + Payload (3) = 7 bytes
        // Length = 2 + 3 = 5
        #expect(data == Data([0xFF, 0xFE, 0x00, 0x05, 0x01, 0x02, 0x03]))
    }
    
    @Test("Begin and end marker segment")
    func testBeginEndMarkerSegment() throws {
        let writer = JPEGLSBitstreamWriter()
        
        let lengthPos = writer.beginMarkerSegment(marker: .comment)
        writer.writeByte(0x01)
        writer.writeByte(0x02)
        writer.endMarkerSegment(lengthPosition: lengthPos)
        
        let data = try writer.getData()
        // Marker (2) + Length (2) + Payload (2) = 6 bytes
        // Length = 4
        #expect(data == Data([0xFF, 0xFE, 0x00, 0x04, 0x01, 0x02]))
    }
    
    @Test("Current position tracking")
    func testCurrentPosition() {
        let writer = JPEGLSBitstreamWriter()
        
        #expect(writer.currentPosition == 0)
        writer.writeByte(0x12)
        #expect(writer.currentPosition == 1)
        writer.writeByte(0xFF)
        #expect(writer.currentPosition == 3)  // 0xFF stuffed to 2 bytes
    }
    
    @Test("Get data with unflushed bits throws error")
    func testGetDataUnflushed() {
        let writer = JPEGLSBitstreamWriter()
        
        writer.writeBits(0b101, count: 3)
        
        #expect(throws: JPEGLSError.self) {
            try writer.getData()
        }
    }
}
