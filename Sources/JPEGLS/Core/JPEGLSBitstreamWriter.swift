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
    
    /// Write a single byte to the stream
    ///
    /// Performs marker stuffing if byte is 0xFF (writes 0xFF 0x00)
    ///
    /// - Parameter byte: The byte to write
    public func writeByte(_ byte: UInt8) {
        data.append(byte)
        
        // Marker stuffing: 0xFF -> 0xFF 0x00
        if byte == JPEGLSMarker.markerPrefix {
            data.append(0x00)
        }
    }
    
    /// Write multiple bytes to the stream
    ///
    /// - Parameter bytes: The bytes to write
    public func writeBytes(_ bytes: Data) {
        for byte in bytes {
            writeByte(byte)
        }
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
    
    /// Write bits to the bitstream
    ///
    /// Accumulates bits in buffer and writes complete bytes with stuffing
    ///
    /// - Parameters:
    ///   - bits: The bits to write as UInt32
    ///   - count: Number of bits to write (1-32)
    public func writeBits(_ bits: UInt32, count: Int) {
        guard count > 0 && count <= 32 else {
            return
        }
        
        // Mask to get only the requested bits
        let mask: UInt32 = (1 << count) - 1
        let maskedBits = bits & mask
        
        // Add bits to buffer
        bitBuffer = (bitBuffer << count) | maskedBits
        bitsInBuffer += count
        
        // Write complete bytes
        while bitsInBuffer >= 8 {
            let shift = bitsInBuffer - 8
            let byte = UInt8((bitBuffer >> shift) & 0xFF)
            writeByte(byte)
            bitsInBuffer -= 8
        }
    }
    
    /// Flush remaining bits in buffer
    ///
    /// Pads with zeros to complete the final byte
    public func flush() {
        if bitsInBuffer > 0 {
            let shift = 8 - bitsInBuffer
            let byte = UInt8((bitBuffer << shift) & 0xFF)
            writeByte(byte)
            bitBuffer = 0
            bitsInBuffer = 0
        }
    }
    
    /// Reset the bit buffer (typically called at scan boundaries)
    public func resetBitBuffer() {
        flush()
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
