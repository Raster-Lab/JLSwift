/// Bitstream writer for JPEG-LS encoding
///
/// Provides bit-level and byte-level writing operations with automatic
/// marker stuffing and buffer management.

import Foundation

/// Bitstream writer for JPEG-LS
///
/// Writes bytes and bits to a buffer, handling marker stuffing automatically.
public final class JPEGLSBitstreamWriter {
    private var data: Data
    private var bitBuffer: UInt32
    private var bitsInBuffer: Int
    
    /// Initialize writer with optional initial capacity
    ///
    /// - Parameter capacity: Initial buffer capacity in bytes
    public init(capacity: Int = 4096) {
        self.data = Data(capacity: capacity)
        self.bitBuffer = 0
        self.bitsInBuffer = 0
    }
    
    /// Get the written data
    ///
    /// - Returns: The complete bitstream data
    /// - Throws: `JPEGLSError` if bit buffer is not flushed
    public func getData() throws -> Data {
        guard bitsInBuffer == 0 else {
            throw JPEGLSError.internalError(
                reason: "Bit buffer not flushed, \(bitsInBuffer) bits remaining"
            )
        }
        return data
    }
    
    /// Current write position in bytes
    public var currentPosition: Int {
        return data.count
    }
    
    /// Write a single byte to the stream (no stuffing).
    ///
    /// This method writes raw bytes for structured data (marker segments, headers).
    /// Bit-level stuffing for compressed scan data is handled automatically by `writeBits`.
    ///
    /// - Parameter byte: The byte to write
    public func writeByte(_ byte: UInt8) {
        data.append(byte)
    }
    
    /// Write multiple bytes to the stream (no stuffing).
    ///
    /// - Parameter bytes: The bytes to write
    public func writeBytes(_ bytes: Data) {
        data.append(contentsOf: bytes)
    }
    
    /// Write a 16-bit big-endian value
    ///
    /// - Parameter value: The 16-bit value
    public func writeUInt16(_ value: UInt16) {
        let byte1 = UInt8((value >> 8) & 0xFF)
        let byte2 = UInt8(value & 0xFF)
        data.append(byte1)
        data.append(byte2)
    }
    
    /// Write a marker (2-byte sequence)
    ///
    /// Does NOT perform marker stuffing for marker bytes
    ///
    /// - Parameter marker: The marker to write
    public func writeMarker(_ marker: JPEGLSMarker) {
        data.append(JPEGLSMarker.markerPrefix)
        data.append(marker.rawValue)
    }
    
    /// Write bits to the bitstream with JPEG-LS bit-level stuffing.
    ///
    /// Accumulates bits in a buffer and flushes complete bytes. Implements bit-level
    /// byte stuffing per ISO 14495-1 §9.1: when a byte of 0xFF is emitted, a 0 stuff bit
    /// is inserted at the next bit position, so the subsequent byte has its MSB = 0
    /// (the stuff bit) and its lower 7 bits carry real data.
    ///
    /// The decoder mirrors this: on reading 0xFF, if the next byte has MSB = 0 it is a
    /// stuffed byte and its 7 lower bits are real data; if MSB = 1 it is a marker.
    ///
    /// - Parameters:
    ///   - bits: The bits to write as UInt32
    ///   - count: Number of bits to write (1-32)
    public func writeBits(_ bits: UInt32, count: Int) {
        guard count > 0 && count <= 32 else {
            return
        }

        // Mask to get only the requested bits
        let mask: UInt32 = count < 32 ? ((1 << count) - 1) : UInt32.max
        let maskedBits = bits & mask

        // Add bits to buffer
        bitBuffer = (bitBuffer << count) | maskedBits
        bitsInBuffer += count

        // Write complete bytes with bit-level stuffing
        while bitsInBuffer >= 8 {
            let shift = bitsInBuffer - 8
            let byte = UInt8((bitBuffer >> shift) & 0xFF)
            data.append(byte)
            bitsInBuffer -= 8

            // Bit-level stuffing per ISO 14495-1 §9.1:
            // After emitting a byte of 0xFF, insert a 0 stuff bit at the next bit position.
            // The UInt32 buffer already has 0 in unused positions; we clear the specific bit
            // at position `bitsInBuffer` (the new MSB of the valid range) to make it 0.
            if byte == 0xFF {
                bitBuffer &= ~(UInt32(1) << UInt32(bitsInBuffer))
                bitsInBuffer += 1
            }
        }
    }
    
    /// Flush remaining bits in buffer
    ///
    /// Pads with zeros to complete the final byte. No stuffing is applied to the
    /// final flushed byte because it is immediately followed by a marker (whose
    /// MSB = 1 signals to the decoder that it is not a stuffed byte).
    public func flush() {
        if bitsInBuffer > 0 {
            let shift = 8 - bitsInBuffer
            let byte = UInt8((bitBuffer << shift) & 0xFF)
            data.append(byte)
            bitBuffer = 0
            bitsInBuffer = 0
        }
    }
    
    /// Reset the bit buffer (typically called at scan boundaries)
    public func resetBitBuffer() {
        flush()
    }

    /// Write a unary code: n zero bits followed by a single 1 bit.
    ///
    /// This is a performance-optimised alternative to calling `writeBits(0, count: 1)` in a loop
    /// followed by `writeBits(1, count: 1)`.  Writing in batches of up to 24 bits reduces
    /// function-call overhead significantly in the Golomb-Rice coding hot path.
    ///
    /// The batch size is capped at 24 because the internal `bitBuffer` is 32 bits wide and may
    /// already hold up to 7 bits from the previous call.  Adding 25 bits (24 zeros + 1 terminator)
    /// to a 7-bit residual gives exactly 32 bits, which fits without overflow.
    ///
    /// - Parameter n: Number of leading zero bits (must be ≥ 0)
    public func writeUnaryCode(_ n: Int) {
        var remaining = n
        // Write up to 24 zeros at a time.  Combined with a worst-case 7-bit residual in
        // the buffer, the total (7 + 24 = 31) safely fits in the 32-bit UInt32 bitBuffer.
        while remaining >= 24 {
            writeBits(0, count: 24)
            remaining -= 24
        }
        // Write the remaining zeros and the terminating 1 in one call (max count = 24
        // when remaining == 23, giving 7 + 24 = 31 bits total — within UInt32 range).
        writeBits(1, count: remaining + 1)
    }

    /// Write n consecutive 1 bits (used for Golomb run-length continuation codes).
    ///
    /// This is a performance-optimised alternative to calling `writeBits(1, count: 1)` in a loop.
    /// The batch size is capped at 24 for the same UInt32 overflow reason as `writeUnaryCode`.
    ///
    /// - Parameter n: Number of 1 bits to write (must be ≥ 0)
    public func writeOnes(_ n: Int) {
        var remaining = n
        // (1 << 24) - 1 = 0x00FF_FFFF fits in UInt32 with room to spare.
        while remaining >= 24 {
            writeBits(0x00FFFFFF, count: 24)
            remaining -= 24
        }
        if remaining > 0 {
            writeBits(UInt32((1 << remaining) - 1), count: remaining)
        }
    }
    
    /// Write a marker segment with length field
    ///
    /// - Parameters:
    ///   - marker: The marker to write
    ///   - payload: The segment payload data
    public func writeMarkerSegment(marker: JPEGLSMarker, payload: Data) {
        writeMarker(marker)
        
        // Length includes the 2 bytes for length field itself
        let length = UInt16(payload.count + 2)
        writeUInt16(length)
        
        // Write payload without stuffing (it's not compressed data)
        data.append(payload)
    }
    
    /// Reserve space for a marker segment and return position
    ///
    /// Useful for writing segments where length is not known upfront
    ///
    /// - Parameter marker: The marker to write
    /// - Returns: Position where length field starts
    public func beginMarkerSegment(marker: JPEGLSMarker) -> Int {
        writeMarker(marker)
        let lengthPos = data.count
        writeUInt16(0)  // Placeholder for length
        return lengthPos
    }
    
    /// Finalize a marker segment by updating its length
    ///
    /// - Parameter lengthPosition: Position returned by beginMarkerSegment
    public func endMarkerSegment(lengthPosition: Int) {
        let currentPos = data.count
        let length = UInt16(currentPos - lengthPosition)
        
        // Update length field
        let byte1 = UInt8((length >> 8) & 0xFF)
        let byte2 = UInt8(length & 0xFF)
        data[lengthPosition] = byte1
        data[lengthPosition + 1] = byte2
    }
}
