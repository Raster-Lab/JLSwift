// Mapping Table Tests
//
// Unit tests for JPEG-LS mapping table (LSE types 2 and 3) support.
// Tests cover table creation, lookup, component selector, parser integration,
// encoder output, and decoder application for palettised images.

import Foundation
import Testing
@testable import JPEGLS

// MARK: - JPEGLSMappingTable Unit Tests

@Suite("Mapping Table Core Tests")
struct JPEGLSMappingTableTests {

    // MARK: - Initialisation

    @Test("Create valid 8-bit mapping table")
    func testCreateValid8BitTable() throws {
        let entries = Array(0..<256).map { 255 - $0 }  // Invert
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: entries)
        #expect(table.id == 1)
        #expect(table.entryWidth == 1)
        #expect(table.count == 256)
        #expect(table.entries[0] == 255)
        #expect(table.entries[255] == 0)
    }

    @Test("Create valid 16-bit mapping table")
    func testCreateValid16BitTable() throws {
        let entries = [100, 200, 300, 400]
        let table = try JPEGLSMappingTable(id: 2, entryWidth: 2, entries: entries)
        #expect(table.id == 2)
        #expect(table.entryWidth == 2)
        #expect(table.count == 4)
        #expect(table.entries[0] == 100)
        #expect(table.entries[3] == 400)
    }

    @Test("Create empty mapping table")
    func testCreateEmptyTable() throws {
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [])
        #expect(table.count == 0)
    }

    @Test("Maximum valid table ID 255")
    func testMaxTableID() throws {
        let table = try JPEGLSMappingTable(id: 255, entryWidth: 1, entries: [42])
        #expect(table.id == 255)
    }

    @Test("Invalid table ID zero throws")
    func testInvalidTableIDZero() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 0, entryWidth: 1, entries: [0])
        }
    }

    @Test("Invalid entry width throws")
    func testInvalidEntryWidth() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 1, entryWidth: 3, entries: [0])
        }
    }

    @Test("Entry width zero throws")
    func testEntryWidthZero() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 1, entryWidth: 0, entries: [0])
        }
    }

    @Test("Entry value out of range for 1-byte width throws")
    func testEntryValueOutOfRange1Byte() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [256])
        }
    }

    @Test("Entry value out of range for 2-byte width throws")
    func testEntryValueOutOfRange2Byte() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 1, entryWidth: 2, entries: [65536])
        }
    }

    @Test("Negative entry value throws")
    func testNegativeEntryValue() throws {
        #expect(throws: JPEGLSError.self) {
            _ = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [-1])
        }
    }

    // MARK: - Lookup

    @Test("Map in-range pixel value")
    func testMapInRange() throws {
        let entries = [10, 20, 30, 40]
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: entries)
        #expect(table.map(0) == 10)
        #expect(table.map(1) == 20)
        #expect(table.map(2) == 30)
        #expect(table.map(3) == 40)
    }

    @Test("Map out-of-range pixel value returns raw value")
    func testMapOutOfRange() throws {
        let entries = [10, 20]
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: entries)
        #expect(table.map(5) == 5)    // Out of range → raw value
        #expect(table.map(-1) == -1)  // Negative → raw value
    }

    @Test("Map identity table returns same value")
    func testMapIdentity() throws {
        let entries = Array(0..<256)
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: entries)
        for i in 0..<256 {
            #expect(table.map(i) == i)
        }
    }

    @Test("maxOutputValue is correct")
    func testMaxOutputValue() throws {
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [3, 1, 7, 2])
        #expect(table.maxOutputValue == 7)
    }

    @Test("Empty table maxOutputValue is zero")
    func testMaxOutputValueEmpty() throws {
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [])
        #expect(table.maxOutputValue == 0)
    }

    // MARK: - Equatable

    @Test("Tables with same content are equal")
    func testEquality() throws {
        let t1 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [1, 2, 3])
        let t2 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [1, 2, 3])
        #expect(t1 == t2)
    }

    @Test("Tables with different entries are not equal")
    func testInequality() throws {
        let t1 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [1, 2, 3])
        let t2 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [1, 2, 4])
        #expect(t1 != t2)
    }

    @Test("Tables with different IDs are not equal")
    func testInequalityDifferentID() throws {
        let t1 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [1, 2, 3])
        let t2 = try JPEGLSMappingTable(id: 2, entryWidth: 1, entries: [1, 2, 3])
        #expect(t1 != t2)
    }

    // MARK: - Description

    @Test("Description is human readable")
    func testDescription() throws {
        let table = try JPEGLSMappingTable(id: 3, entryWidth: 2, entries: [100, 200])
        let desc = table.description
        #expect(desc.contains("3"))
        #expect(desc.contains("2"))
    }
}

// MARK: - ComponentSelector Tests

@Suite("Component Selector Mapping Table Tests")
struct ComponentSelectorMappingTableTests {

    @Test("Default mapping table ID is zero")
    func testDefaultMappingTableID() {
        let selector = JPEGLSScanHeader.ComponentSelector(id: 1)
        #expect(selector.mappingTableID == 0)
    }

    @Test("Custom mapping table ID is stored")
    func testCustomMappingTableID() {
        let selector = JPEGLSScanHeader.ComponentSelector(id: 2, mappingTableID: 5)
        #expect(selector.id == 2)
        #expect(selector.mappingTableID == 5)
    }

    @Test("Component selectors with same ID and table ID are equal")
    func testEquality() {
        let s1 = JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 3)
        let s2 = JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 3)
        #expect(s1 == s2)
    }

    @Test("Component selectors with different table IDs are not equal")
    func testInequality() {
        let s1 = JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 3)
        let s2 = JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 4)
        #expect(s1 != s2)
    }

    @Test("Scan header stores mapping table ID on component")
    func testScanHeaderStoresMappingTableID() throws {
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 7)],
            near: 0,
            interleaveMode: .none
        )
        #expect(scanHeader.components[0].mappingTableID == 7)
    }
}

// MARK: - ParseResult Tests

@Suite("ParseResult Mapping Table Tests")
struct ParseResultMappingTableTests {

    @Test("ParseResult mappingTables is empty by default")
    func testDefaultEmptyMappingTables() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 4, height: 4)
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: 0,
            interleaveMode: .none
        )
        let result = JPEGLSParseResult(frameHeader: frameHeader, scanHeaders: [scanHeader])
        #expect(result.mappingTables.isEmpty)
    }

    @Test("ParseResult stores mapping tables by ID")
    func testParseResultStoresMappingTables() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 1, height: 1)
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1, mappingTableID: 1)],
            near: 0,
            interleaveMode: .none
        )
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: Array(0..<256))
        let result = JPEGLSParseResult(
            frameHeader: frameHeader,
            scanHeaders: [scanHeader],
            mappingTables: [1: table]
        )
        #expect(result.mappingTables.count == 1)
        #expect(result.mappingTables[1] != nil)
    }

    @Test("ParseResult allows multiple mapping tables")
    func testMultipleMappingTablesInParseResult() throws {
        let frameHeader = try JPEGLSFrameHeader.grayscale(bitsPerSample: 8, width: 1, height: 1)
        let scanHeader = try JPEGLSScanHeader(
            componentCount: 1,
            components: [JPEGLSScanHeader.ComponentSelector(id: 1)],
            near: 0,
            interleaveMode: .none
        )
        let t1 = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [0, 1])
        let t2 = try JPEGLSMappingTable(id: 2, entryWidth: 1, entries: [10, 20])
        let result = JPEGLSParseResult(
            frameHeader: frameHeader,
            scanHeaders: [scanHeader],
            mappingTables: [1: t1, 2: t2]
        )
        #expect(result.mappingTables.count == 2)
        #expect(result.mappingTables[1]?.entries == [0, 1])
        #expect(result.mappingTables[2]?.entries == [10, 20])
    }
}

// MARK: - Encoder Mapping Table Write Tests

@Suite("Mapping Table Encoder Tests")
struct MappingTableEncoderTests {

    @Test("Write mapping table LSE type 2 marker for 1-byte entries")
    func testWriteMappingTableType2OneByte() throws {
        let entries = [10, 20, 30]
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: entries)
        let writer = JPEGLSBitstreamWriter()
        let encoder = JPEGLSEncoder()
        encoder.writeMappingTable(table, to: writer)
        let data = try writer.getData()
        let bytes = Array(data)
        // Expected layout: FF F8 (LSE), 00 08 (Ll=8), 02 (type=2), 01 (TID=1), 01 (Wt=1), 0A 14 1E (entries)
        #expect(bytes[0] == 0xFF)
        #expect(bytes[1] == 0xF8)   // LSE marker
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        #expect(length == 8)         // 2(Ll) + 1(Id) + 1(TID) + 1(Wt) + 3(entries×1) = 8
        #expect(bytes[4] == 0x02)    // LSE type 2
        #expect(bytes[5] == 0x01)    // Table ID = 1
        #expect(bytes[6] == 0x01)    // Entry width = 1
        #expect(bytes[7] == 10)      // Entry 0
        #expect(bytes[8] == 20)      // Entry 1
        #expect(bytes[9] == 30)      // Entry 2
    }

    @Test("Write mapping table LSE type 2 marker for 2-byte entries")
    func testWriteMappingTableType2TwoBytes() throws {
        let entries = [0x0100, 0x0200]
        let table = try JPEGLSMappingTable(id: 3, entryWidth: 2, entries: entries)
        let writer = JPEGLSBitstreamWriter()
        let encoder = JPEGLSEncoder()
        encoder.writeMappingTable(table, to: writer)
        let data = try writer.getData()
        let bytes = Array(data)
        // Ll = 2 + 1 + 1 + 1 + 2*2 = 9
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        #expect(length == 9)
        #expect(bytes[4] == 0x02)    // LSE type 2
        #expect(bytes[5] == 3)       // Table ID = 3
        #expect(bytes[6] == 2)       // Entry width = 2
        #expect(bytes[7] == 0x01)    // Entry 0 high byte
        #expect(bytes[8] == 0x00)    // Entry 0 low byte
        #expect(bytes[9] == 0x02)    // Entry 1 high byte
        #expect(bytes[10] == 0x00)   // Entry 1 low byte
    }

    @Test("Write empty mapping table emits valid LSE segment")
    func testWriteEmptyMappingTable() throws {
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: [])
        let writer = JPEGLSBitstreamWriter()
        JPEGLSEncoder().writeMappingTable(table, to: writer)
        let data = try writer.getData()
        let bytes = Array(data)
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        #expect(length == 5)  // 2(Ll) + 1(Id) + 1(TID) + 1(Wt) = 5, no entries
    }

    @Test("Encoded file has correct LSE marker when mapping table is injected")
    func testEncodedFileWithInjectedMappingTable() throws {
        // Encode a simple image, then parse the encoded output to verify it round-trips
        let imageData = try MultiComponentImageData.grayscale(
            pixels: [[10, 20], [30, 40]],
            bitsPerSample: 8
        )
        let encoder = JPEGLSEncoder()
        let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)

        // Build LSE for identity table
        let tableWriter = JPEGLSBitstreamWriter()
        let identityEntries = Array(0..<256)
        let identityTable = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: identityEntries)
        encoder.writeMappingTable(identityTable, to: tableWriter)
        let lseData = try tableWriter.getData()

        // Splice LSE before SOS in encoded data
        let patchedData = try spliceBeforeSOS(lseData, into: encoded)

        // Parse the patched file
        let parser = JPEGLSParser(data: patchedData)
        let result = try parser.parse()
        #expect(result.mappingTables.count == 1)
        #expect(result.mappingTables[1]?.count == 256)
    }

    // MARK: - Helper

    /// Insert `insertion` bytes into `data` immediately before the first SOS marker.
    private func spliceBeforeSOS(_ insertion: Data, into data: Data) throws -> Data {
        var insertPos: Int?
        let bytes = Array(data)
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDA {
                insertPos = i
                break
            }
            i += 1
        }
        guard let pos = insertPos else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS marker not found")
        }
        let preamble = data.prefix(pos)
        let rest = data.suffix(from: data.index(data.startIndex, offsetBy: pos))
        return preamble + insertion + rest
    }
}

// MARK: - Decoder Mapping Table Application Tests

@Suite("Mapping Table Decoder Tests")
struct MappingTableDecoderTests {

    @Test("Decode image without mapping table gives original values")
    func testDecodeWithoutMappingTable() throws {
        let pixels = [[10, 20], [30, 40]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        let decoded = try JPEGLSDecoder().decode(encoded)
        #expect(decoded.components[0].pixels == [[10, 20], [30, 40]])
    }

    @Test("ParseResult scan header component has mapping table ID after splice")
    func testScanHeaderComponentMappingTableIDAfterSplice() throws {
        // Build an image and inject a mapping table LSE + patch the SOS to reference it.
        // This verifies that the parser correctly reads the Tdi field from the scan header.
        let imageData = try MultiComponentImageData.grayscale(
            pixels: [[5, 10]],
            bitsPerSample: 8
        )
        let encoder = JPEGLSEncoder()
        let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)
        
        // Write LSE type 2 identity table
        let tableWriter = JPEGLSBitstreamWriter()
        let table = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: Array(0..<256))
        encoder.writeMappingTable(table, to: tableWriter)
        let lseData = try tableWriter.getData()
        
        // Patch the bitstream: insert LSE before SOS
        let patched = try patchBitstreamWithTableAndReference(
            encoded: encoded,
            lseData: lseData,
            tableID: 1
        )
        
        let parser = JPEGLSParser(data: patched)
        let result = try parser.parse()
        #expect(result.mappingTables[1] != nil)
        #expect(result.scanHeaders[0].components[0].mappingTableID == 1)
    }

    @Test("Mapping table lookup is applied by decoder")
    func testMappingTableLookupApplied() throws {
        // Encode [0, 1, 2, 3] pixels, then inject inversion table and decode.
        // Result should be [255, 254, 253, 252].
        let pixels = [[0, 1, 2, 3]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoder = JPEGLSEncoder()
        let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)

        // Build inversion table: entry[i] = 255 - i
        let inversionEntries = Array(0..<256).map { 255 - $0 }
        let inversionTable = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: inversionEntries)
        
        let tableWriter = JPEGLSBitstreamWriter()
        encoder.writeMappingTable(inversionTable, to: tableWriter)
        let lseData = try tableWriter.getData()
        
        // Patch bitstream with LSE + table reference in scan header
        let patched = try patchBitstreamWithTableAndReference(
            encoded: encoded,
            lseData: lseData,
            tableID: 1
        )
        
        let decoded = try JPEGLSDecoder().decode(patched)
        #expect(decoded.components[0].pixels[0] == [255, 254, 253, 252])
    }

    @Test("Identity mapping table does not change decoded values")
    func testIdentityMappingTable() throws {
        let pixels = [[42, 100, 200]]
        let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
        let encoder = JPEGLSEncoder()
        let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)

        let identityEntries = Array(0..<256)
        let identityTable = try JPEGLSMappingTable(id: 1, entryWidth: 1, entries: identityEntries)
        let tableWriter = JPEGLSBitstreamWriter()
        encoder.writeMappingTable(identityTable, to: tableWriter)
        let lseData = try tableWriter.getData()

        let patched = try patchBitstreamWithTableAndReference(
            encoded: encoded,
            lseData: lseData,
            tableID: 1
        )

        let decoded = try JPEGLSDecoder().decode(patched)
        #expect(decoded.components[0].pixels[0] == [42, 100, 200])
    }

    // MARK: - Helpers

    /// Insert an LSE segment before the SOS marker and patch the SOS component
    /// selector to reference the given `tableID`.
    ///
    /// The SOS component selector's Tdi byte (second byte of each component entry) is
    /// updated from 0 to `tableID`.
    private func patchBitstreamWithTableAndReference(
        encoded: Data,
        lseData: Data,
        tableID: UInt8
    ) throws -> Data {
        var bytes = Array(encoded)
        
        // Find SOS marker position
        var sosPos: Int?
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDA {
                sosPos = i
                break
            }
            i += 1
        }
        guard let pos = sosPos else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS marker not found")
        }
        
        // Insert LSE before SOS
        let preamble = Array(bytes.prefix(pos))
        let rest = Array(bytes.suffix(from: pos))
        bytes = preamble + Array(lseData) + rest
        
        // Find SOS again (position has shifted)
        sosPos = nil
        i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0xFF && bytes[i + 1] == 0xDA {
                sosPos = i
                break
            }
            i += 1
        }
        guard let newSosPos = sosPos else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS marker not found after splice")
        }
        
        // SOS layout: FF DA | Ll(2) | Ns(1) | [Cs(1) Td(1)]×Ns | Ss(1) | Se(1) | Ah|Al(1)
        // Patch first component Tdi (mapping table ID, offset 6 from SOS marker)
        let tdOffset = newSosPos + 2 + 2 + 1 + 0 + 1  // FF DA | Ll | Ns | Cs1
        guard tdOffset < bytes.count else {
            throw JPEGLSError.invalidBitstreamStructure(reason: "SOS too short to patch")
        }
        bytes[tdOffset] = tableID
        
        return Data(bytes)
    }
}

// MARK: - Mapping Table Continuation Tests

@Suite("Mapping Table Continuation Parsing Tests")
struct MappingTableContinuationTests {

    @Test("Parser reads continuation entries appended to table")
    func testParserReadsContinuationEntries() throws {
        // Build a bitstream with LSE type 2 (first 4 entries) + LSE type 3 (4 more entries)
        // then a SOS to satisfy the parser.
        let imageData = try MultiComponentImageData.grayscale(
            pixels: [[0, 1, 2, 3]],
            bitsPerSample: 8
        )
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        
        // Build LSE type 2 with 4 entries
        let writer = JPEGLSBitstreamWriter()
        writer.writeMarker(.jpegLSExtension)
        // Ll = 2 + 1(Id) + 1(TID) + 1(Wt) + 4(entries) = 9
        writer.writeUInt16(9)
        writer.writeByte(JPEGLSExtensionType.mappingTable.rawValue)
        writer.writeByte(1)    // Table ID
        writer.writeByte(1)    // Wt = 1 byte
        writer.writeByte(10)   // Entry 0
        writer.writeByte(20)   // Entry 1
        writer.writeByte(30)   // Entry 2
        writer.writeByte(40)   // Entry 3
        
        // Build LSE type 3 with 4 more entries
        writer.writeMarker(.jpegLSExtension)
        // Ll = 2 + 1(Id) + 1(TID) + 4(entries) = 8
        writer.writeUInt16(8)
        writer.writeByte(JPEGLSExtensionType.mappingTableContinuation.rawValue)
        writer.writeByte(1)    // Table ID
        writer.writeByte(50)   // Entry 4
        writer.writeByte(60)   // Entry 5
        writer.writeByte(70)   // Entry 6
        writer.writeByte(80)   // Entry 7
        let lseData = try writer.getData()
        
        // Splice before SOS
        var bytes = Array(encoded)
        var sosPos = 0
        var j = 0
        while j < bytes.count - 1 {
            if bytes[j] == 0xFF && bytes[j + 1] == 0xDA {
                sosPos = j; break
            }
            j += 1
        }
        let patched = Data(Array(bytes.prefix(sosPos)) + Array(lseData) + Array(bytes.suffix(from: sosPos)))
        
        let parser = JPEGLSParser(data: patched)
        let result = try parser.parse()
        guard let table = result.mappingTables[1] else {
            Issue.record("Expected mapping table with ID 1")
            return
        }
        #expect(table.count == 8)
        #expect(table.entries == [10, 20, 30, 40, 50, 60, 70, 80])
    }

    @Test("Continuation without initial table is skipped gracefully")
    func testContinuationWithoutInitialTableSkipped() throws {
        // Build a bitstream with only LSE type 3 (no type 2 for the same table)
        let imageData = try MultiComponentImageData.grayscale(
            pixels: [[0]],
            bitsPerSample: 8
        )
        let encoded = try JPEGLSEncoder().encode(imageData, near: 0, interleaveMode: .none)
        
        let writer = JPEGLSBitstreamWriter()
        writer.writeMarker(.jpegLSExtension)
        writer.writeUInt16(7)  // Ll = 2 + 1 + 1 + 3
        writer.writeByte(JPEGLSExtensionType.mappingTableContinuation.rawValue)
        writer.writeByte(1)    // TID
        writer.writeByte(10)
        writer.writeByte(20)
        writer.writeByte(30)
        let lseData = try writer.getData()
        
        var bytes = Array(encoded)
        var sosPos = 0
        var j = 0
        while j < bytes.count - 1 {
            if bytes[j] == 0xFF && bytes[j + 1] == 0xDA {
                sosPos = j; break
            }
            j += 1
        }
        let patched = Data(Array(bytes.prefix(sosPos)) + Array(lseData) + Array(bytes.suffix(from: sosPos)))
        
        // Should not throw
        let parser = JPEGLSParser(data: patched)
        let result = try parser.parse()
        // Continuation without initial table is silently skipped
        #expect(result.mappingTables.isEmpty)
    }
}
