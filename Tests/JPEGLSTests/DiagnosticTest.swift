import Foundation
import Testing
@testable import JPEGLS

@Suite("Diagnostic Test")
struct DiagnosticTest {
    @Test("Debug decode t16e0 with position tracking") 
    func testDebugDecodeT16e0() throws {
        let data = try TestFixtureLoader.loadFixture(named: "t16e0.jls")
        
        let parser = JPEGLSParser(data: data)
        let parseResult = try parser.parse()
        
        // Extract scan data manually
        // SOF is at offset 2, SOS at offset 15 (from our analysis)
        // SOS length = 8, so scan data starts at offset 15 + 2 + 8 = 25
        let sosOffset = 15
        let sosLength = Int(data[sosOffset + 2]) << 8 | Int(data[sosOffset + 3])
        let scanDataStart = sosOffset + 2 + sosLength
        
        // Find scan data end
        var scanDataEnd = scanDataStart
        while scanDataEnd < data.count - 1 {
            if data[scanDataEnd] == 0xFF {
                let next = data[scanDataEnd + 1]
                if next >= 0x80 {
                    break
                }
                scanDataEnd += 2
            } else {
                scanDataEnd += 1
            }
        }
        
        let scanData = Data(data[scanDataStart..<scanDataEnd])
        print("Scan data: \(scanData.count) bytes (from \(scanDataStart) to \(scanDataEnd))")
        
        let reader = JPEGLSBitstreamReader(data: scanData)
        let parameters = try parseResult.presetParameters ?? JPEGLSPresetParameters.defaultParameters(
            bitsPerSample: parseResult.frameHeader.bitsPerSample
        )
        let scanHeader = parseResult.scanHeaders[0]
        
        print("Parameters: MAXVAL=\(parameters.maxValue), T1=\(parameters.threshold1), T2=\(parameters.threshold2), T3=\(parameters.threshold3), RESET=\(parameters.reset)")
        print("Scan: near=\(scanHeader.near), bps=\(parseResult.frameHeader.bitsPerSample)")
        
        let decoder = try JPEGLSRegularModeDecoder(parameters: parameters, near: scanHeader.near)
        let runDecoder = try JPEGLSRunModeDecoder(parameters: parameters, near: scanHeader.near)
        var context = try JPEGLSContextModel(parameters: parameters, near: scanHeader.near)
        
        let width = parseResult.frameHeader.width
        let height = parseResult.frameHeader.height
        var pixels = Array(repeating: Array(repeating: 0, count: width), count: height)
        
        // Try decoding with position tracking
        var lastRow = 0
        var lastCol = 0
        var pixelCount = 0
        
        // Compute LIMIT and qbppBits
        let range = parameters.maxValue + 1
        var qbppBits = 0
        var r = range - 1
        while r > 0 {
            qbppBits += 1
            r >>= 1
        }
        qbppBits = max(qbppBits, 2)
        let limit = 2 * (qbppBits + 8)
        
        print("RANGE=\(range), qbppBits=\(qbppBits), LIMIT=\(limit)")
        
        do {
            for row in 0..<height {
                context.setRunIndex(0)
                var col = 0
                while col < width {
                    lastRow = row
                    lastCol = col
                    
                    let a: Int, b: Int, c: Int, d: Int
                    if row == 0 && col == 0 {
                        (a, b, c, d) = (0, 0, 0, 0)
                    } else if row == 0 {
                        let left = pixels[row][col - 1]
                        (a, b, c, d) = (left, 0, 0, 0)
                    } else if col == 0 {
                        let top = pixels[row - 1][col]
                        let topRight = (col + 1 < width) ? pixels[row - 1][col + 1] : top
                        (a, b, c, d) = (top, top, top, topRight)
                    } else {
                        let left = pixels[row][col - 1]
                        let top = pixels[row - 1][col]
                        let tl = pixels[row - 1][col - 1]
                        let tr = (col + 1 < width) ? pixels[row - 1][col + 1] : top
                        (a, b, c, d) = (left, top, tl, tr)
                    }
                    
                    let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c, d: d)
                    let q1 = decoder.quantizeGradient(d1)
                    let q2 = decoder.quantizeGradient(d2)
                    let q3 = decoder.quantizeGradient(d3)
                    
                    if q1 == 0 && q2 == 0 && q3 == 0 {
                        // Run mode
                        var runLength = 0
                        var runIndex = context.currentRunIndex
                        
                        while runLength < (width - col) {
                            let j = runDecoder.computeJ(runIndex: runIndex)
                            let blockSize = 1 << j
                            
                            let bit = try reader.readBits(1)
                            if bit == 1 {
                                runLength += blockSize
                                if runIndex < 31 { runIndex += 1 }
                            } else {
                                let remainder = j > 0 ? Int(try reader.readBits(j)) : 0
                                runLength += remainder
                                if runIndex > 0 { runIndex -= 1 }
                                context.setRunIndex(runIndex)
                                
                                runLength = min(runLength, width - col)
                                
                                // Decode interruption pixel
                                let rik = context.computeRunInterruptionGolombK()
                                let mappedError = try readGolomb(reader: reader, k: rik, limit: limit, qbppBits: qbppBits)
                                let interruption = runDecoder.decodeRunInterruption(
                                    mappedError: mappedError,
                                    runValue: a
                                )
                                context.updateRunInterruptionContext(absError: abs(interruption.error))
                                
                                // Fill run
                                for i in 0..<runLength {
                                    if col + i < width {
                                        pixels[row][col + i] = a
                                    }
                                }
                                col += runLength
                                
                                if col < width {
                                    pixels[row][col] = interruption.sample
                                    col += 1
                                }
                                
                                break  // Exit run loop
                            }
                        }
                        
                        // If we consumed all remaining in line (full run)
                        if runLength >= (width - col) && col <= width - runLength {
                            context.setRunIndex(runIndex)
                            for i in 0..<min(runLength, width - col) {
                                if col + i < width {
                                    pixels[row][col + i] = a
                                }
                            }
                            col += min(runLength, width - col)
                        }
                    } else {
                        // Regular mode
                        let contextIndex = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
                        let k = context.computeGolombParameter(contextIndex: contextIndex)
                        let mappedError = try readGolomb(reader: reader, k: k, limit: limit, qbppBits: qbppBits)
                        
                        let result = decoder.decodePixel(
                            mappedError: mappedError,
                            a: a, b: b, c: c, d: d,
                            context: context
                        )
                        
                        context.updateContext(
                            contextIndex: contextIndex,
                            predictionError: result.error,
                            sign: result.sign
                        )
                        
                        pixels[row][col] = result.sample
                        col += 1
                    }
                    
                    pixelCount += 1
                }
            }
            print("Decoded all \(pixelCount) pixels successfully!")
        } catch {
            let readerPos = reader.currentPosition
            let remaining = reader.bytesRemaining
            print("FAILED at row=\(lastRow), col=\(lastCol), pixelCount=\(pixelCount)")
            print("Reader position: \(readerPos)/\(scanData.count) bytes, remaining=\(remaining)")
            print("Error: \(error)")
            #expect(Bool(false), "Decoding failed at pixel (\(lastRow), \(lastCol))")
        }
    }
    
    func readGolomb(reader: JPEGLSBitstreamReader, k: Int, limit: Int, qbppBits: Int) throws -> Int {
        let limitThreshold = limit - qbppBits - 1
        var unaryCount = 0
        while true {
            let bit = try reader.readBits(1)
            if bit == 1 { break }
            unaryCount += 1
        }
        if unaryCount >= limitThreshold {
            let rawValue = Int(try reader.readBits(qbppBits))
            return rawValue + 1
        }
        let remainder = k > 0 ? Int(try reader.readBits(k)) : 0
        return (unaryCount << k) | remainder
    }
}
