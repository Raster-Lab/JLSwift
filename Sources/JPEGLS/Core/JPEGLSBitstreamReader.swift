/// Bitstream reader for JPEG-LS decoding
///
/// Provides bit-level and byte-level reading operations on a data buffer
/// with marker detection and error handling.

import Foundation

/// Bitstream reader for JPEG-LS
///
/// Reads bytes and bits from a buffer, handling marker stuffing and
/// detecting premature end of stream.
public final class JPEGLSBitstreamReader {
    private let data: Data
    private var position: Int
    private var bitBuffer: UInt32
    private var bitsInBuffer: Int
    
    /// Initialize reader with data buffer
    ///
    /// - Parameter data: Input data to read from
    public init(data: Data) {
        self.data = data
        self.position = 0
        self.bitBuffer = 0
        self.bitsInBuffer = 0
    }
    
    /// Current read position in bytes
    public var currentPosition: Int {
        return position
    }
    
    /// Number of bytes remaining in buffer
    public var bytesRemaining: Int {
        return data.count - position
    }
    
    /// Returns true if end of data reached
    public var isAtEnd: Bool {
        return position >= data.count && bitsInBuffer == 0
    }
    
    /// Read a single byte from the stream
    ///
    /// - Returns: The byte value
    /// - Throws: `JPEGLSError.prematureEndOfStream` if no data available
    public func readByte() throws -> UInt8 {
        guard position < data.count else {
            throw JPEGLSError.prematureEndOfStream
        }
        let byte = data[position]
        position += 1
        return byte
    }
    
    /// Read multiple bytes from the stream
    ///
    /// - Parameter count: Number of bytes to read
    /// - Returns: Data containing the bytes
    /// - Throws: `JPEGLSError.prematureEndOfStream` if not enough data
    public func readBytes(_ count: Int) throws -> Data {
        guard position + count <= data.count else {
            throw JPEGLSError.prematureEndOfStream
        }
        let bytes = data[position..<position + count]
        position += count
        return bytes
    }
    
    /// Read a 16-bit big-endian value
    ///
    /// - Returns: The 16-bit value
    /// - Throws: `JPEGLSError.prematureEndOfStream` if not enough data
    public func readUInt16() throws -> UInt16 {
        let byte1 = try readByte()
        let byte2 = try readByte()
        return (UInt16(byte1) << 8) | UInt16(byte2)
    }
    
    /// Peek at the next byte without advancing position
    ///
    /// - Returns: The next byte, or nil if at end
    public func peekByte() -> UInt8? {
        guard position < data.count else {
            return nil
        }
        return data[position]
    }
    
    /// Read a marker (2-byte sequence starting with 0xFF)
    ///
    /// - Returns: The marker
    /// - Throws: `JPEGLSError` if marker is invalid or not found
    public func readMarker() throws -> JPEGLSMarker {
        let byte1 = try readByte()
        guard byte1 == JPEGLSMarker.markerPrefix else {
            throw JPEGLSError.invalidMarker(byte1: byte1, byte2: 0)
        }
        
        let byte2 = try readByte()
        guard let marker = JPEGLSMarker(rawValue: byte2) else {
            throw JPEGLSError.invalidMarker(byte1: byte1, byte2: byte2)
        }
        
        return marker
    }
    
    /// Skip to the next marker in the stream
    ///
    /// - Returns: The marker found
    /// - Throws: `JPEGLSError` if no marker found before end of stream
    public func findNextMarker() throws -> JPEGLSMarker {
        while !isAtEnd {
            let byte = try readByte()
            if byte == JPEGLSMarker.markerPrefix {
                if let nextByte = peekByte(), nextByte != 0x00 {
                    // This is a marker, read it
                    position -= 1  // Back up to re-read the 0xFF
                    return try readMarker()
                }
            }
        }
        throw JPEGLSError.prematureEndOfStream
    }
    
    /// Read bits from the bitstream
    ///
    /// Handles byte stuffing including CharLS extensions:
    /// - 0xFF 0x00: Standard JPEG-LS byte stuffing
    /// - 0xFF 0x60-0x7F: CharLS escape sequences
    /// - 0xFF 0xXX where 0xXX is not a recognised JPEG-LS marker: extended stuffing
    ///   (used by the JPEG-LS conformance reference implementation and some encoders)
    ///
    /// This logic mirrors the scan-boundary detection in `JPEGLSDecoder.extractScanData()`:
    /// any `FF XX` that would NOT be treated as a real marker there must also be treated as
    /// a stuffed byte here to keep the two code paths consistent.
    ///
    /// - Parameter count: Number of bits to read (1-32)
    /// - Returns: The bits as a UInt32
    /// - Throws: `JPEGLSError.prematureEndOfStream` if not enough data
    public func readBits(_ count: Int) throws -> UInt32 {
        guard count > 0 && count <= 32 else {
            throw JPEGLSError.internalError(reason: "Invalid bit count: \(count)")
        }
        
        // Fill buffer if needed
        while bitsInBuffer < count && !isAtEnd {
            let byte = try readByte()
            
            // Handle byte stuffing (standard and CharLS/reference-implementation extensions).
            // Any FF XX where XX does not correspond to a known JPEG-LS marker is treated as
            // a stuffed byte: the XX byte is discarded and only FF contributes to the bitstream.
            // This matches the extended stuffing detection in extractScanData().
            if byte == 0xFF {
                if let next = peekByte() {
                    let isKnownMarker = JPEGLSMarker(rawValue: next) != nil
                    if !isKnownMarker {
                        _ = try readByte()  // Skip the stuffed byte
                    }
                    // If next byte IS a known marker, FF is end-of-scan data —
                    // it will be added to the buffer but no valid code should consume it.
                }
            }
            
            bitBuffer = (bitBuffer << 8) | UInt32(byte)
            bitsInBuffer += 8
        }
        
        guard bitsInBuffer >= count else {
            throw JPEGLSError.prematureEndOfStream
        }
        
        // Extract bits
        let shift = bitsInBuffer - count
        let mask: UInt32 = (1 << count) - 1
        let bits = (bitBuffer >> shift) & mask
        
        bitsInBuffer -= count
        
        return bits
    }
    
    /// Reset the bit buffer (typically called at scan boundaries)
    public func resetBitBuffer() {
        bitBuffer = 0
        bitsInBuffer = 0
    }
    
    /// Seek to a specific position in the stream
    ///
    /// - Parameter position: Target position in bytes
    /// - Throws: `JPEGLSError` if position is invalid
    public func seek(to position: Int) throws {
        guard position >= 0 && position <= data.count else {
            throw JPEGLSError.internalError(reason: "Invalid seek position: \(position)")
        }
        self.position = position
        resetBitBuffer()
    }
}
