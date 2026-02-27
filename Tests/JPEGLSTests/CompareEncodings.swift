import Foundation
import Testing
@testable import JPEGLS

@Test("Trace flat 3x3 encoding/decoding")
func traceFlatImage() throws {
    // Flat 3x3, all 128
    let pixels: [[Int]] = [
        [128, 128, 128],
        [128, 128, 128],
        [128, 128, 128]
    ]
    
    let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: 8)
    let encoder = JPEGLSEncoder()
    let encoded = try encoder.encode(imageData, near: 0, interleaveMode: .none)
    
    // Extract scan data
    var scanStart = 0
    for i in 0..<encoded.count - 1 {
        if encoded[i] == 0xFF && encoded[i+1] == 0xDA {
            let sosLen = Int(encoded[i+2]) << 8 | Int(encoded[i+3])
            scanStart = i + 2 + sosLen
            break
        }
    }
    var scanEnd = scanStart
    while scanEnd < encoded.count - 1 {
        if encoded[scanEnd] == 0xFF && encoded[scanEnd+1] >= 0x80 { break }
        if encoded[scanEnd] == 0xFF { scanEnd += 2 } else { scanEnd += 1 }
    }
    let scanData = encoded[scanStart..<scanEnd]
    let scanBytes = scanData.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("Scan data (\(scanData.count) bytes): \(scanBytes)")
    
    // Show as bits
    var bits = ""
    for byte in scanData {
        bits += String(byte, radix: 2).padLeft(to: 8) + " "
    }
    print("Bits: \(bits)")
    
    // Now manually decode with the reader
    let reader = JPEGLSBitstreamReader(data: Data(scanData))
    let params = try JPEGLSPresetParameters.defaultParameters(bitsPerSample: 8)
    let decoder = try JPEGLSRegularModeDecoder(parameters: params, near: 0)
    let runDecoder = try JPEGLSRunModeDecoder(parameters: params, near: 0)
    var context = try JPEGLSContextModel(parameters: params, near: 0)
    
    // LIMIT and qbppBits for 8-bit
    let limit = 2 * (8 + max(8, 8))  // 32
    let qbppBits = 8
    
    print("\nLIMIT=\(limit), qbppBits=\(qbppBits)")
    
    var decodedPixels = Array(repeating: Array(repeating: 0, count: 3), count: 3)
    
    for row in 0..<3 {
        context.setRunIndex(0)
        var col = 0
        while col < 3 {
            // Get neighbors
            let a: Int, b: Int, c: Int, d: Int
            if row == 0 && col == 0 { (a, b, c, d) = (0, 0, 0, 0) }
            else if row == 0 { (a, b, c, d) = (decodedPixels[row][col-1], 0, 0, 0) }
            else if col == 0 {
                let top = decodedPixels[row-1][col]
                let topRight = (col + 1 < 3) ? decodedPixels[row-1][col+1] : top
                (a, b, c, d) = (top, top, top, topRight)
            } else {
                (a, b, c, d) = (
                    decodedPixels[row][col-1],
                    decodedPixels[row-1][col],
                    decodedPixels[row-1][col-1],
                    (col + 1 < 3) ? decodedPixels[row-1][col+1] : decodedPixels[row-1][col]
                )
            }
            
            let (d1, d2, d3) = decoder.computeGradients(a: a, b: b, c: c, d: d)
            let q1 = decoder.quantizeGradient(d1)
            let q2 = decoder.quantizeGradient(d2)
            let q3 = decoder.quantizeGradient(d3)
            
            print("  [\(row),\(col)]: a=\(a), b=\(b), c=\(c), d=\(d) | q=(\(q1),\(q2),\(q3)) | pos=\(reader.currentPosition) remain=\(reader.bytesRemaining)")
            
            if q1 == 0 && q2 == 0 && q3 == 0 {
                print("    → Run mode (runIndex=\(context.currentRunIndex))")
                var runLength = 0
                var runIndex = context.currentRunIndex
                while runLength < (3 - col) {
                    let j = runDecoder.computeJ(runIndex: runIndex)
                    let blockSize = 1 << j
                    let bit = try reader.readBits(1)
                    print("    Read bit: \(bit) (j=\(j), blockSize=\(blockSize))")
                    if bit == 1 {
                        runLength += blockSize
                        if runIndex < 31 { runIndex += 1 }
                    } else {
                        let remainder = j > 0 ? Int(try reader.readBits(j)) : 0
                        runLength += remainder
                        print("    Run terminated: remainder=\(remainder)")
                        if runIndex > 0 { runIndex -= 1 }
                        context.setRunIndex(runIndex)
                        break
                    }
                }
                let actualRun = min(runLength, 3 - col)
                print("    Run length=\(actualRun) (remaining in line=\(3 - col))")
                
                for i in 0..<actualRun {
                    decodedPixels[row][col + i] = a
                }
                
                if runLength < (3 - col) {
                    let iCol = col + actualRun
                    let ra = a
                    let rb = row > 0 ? decodedPixels[row-1][iCol] : 0
                    let riType = (abs(ra - rb) <= 0) ? 1 : 0
                    print("    Run interruption at col \(iCol): Ra=\(ra), Rb=\(rb), RItype=\(riType)")
                    
                    let k = context.computeRunInterruptionGolombK(riType: riType)
                    let j = runDecoder.computeJ(runIndex: context.currentRunIndex)
                    let adjustedLimit = limit - j - 1
                    let limitThreshold = adjustedLimit - qbppBits - 1
                    print("    k=\(k), j=\(j), adjustedLimit=\(adjustedLimit), limitThreshold=\(limitThreshold)")
                    
                    var unaryCount = 0
                    while true {
                        let bit = try reader.readBits(1)
                        if bit == 1 { break }
                        unaryCount += 1
                    }
                    print("    Unary count: \(unaryCount)")
                    
                    let eMappedErrorValue: Int
                    if unaryCount >= limitThreshold {
                        let rawValue = Int(try reader.readBits(qbppBits))
                        eMappedErrorValue = rawValue + 1
                        print("    Limited binary: rawValue=\(rawValue), eMapped=\(eMappedErrorValue)")
                    } else {
                        let rem = k > 0 ? Int(try reader.readBits(k)) : 0
                        eMappedErrorValue = (unaryCount << k) | rem
                        print("    Standard Golomb: rem=\(rem), eMapped=\(eMappedErrorValue)")
                    }
                    
                    let errorValue = context.computeRunInterruptionErrorValue(
                        temp: eMappedErrorValue + riType, k: k, riType: riType
                    )
                    print("    errorValue=\(errorValue)")
                    
                    let sample: Int
                    if riType == 1 {
                        sample = runDecoder.reconstructSample(prediction: ra, error: errorValue)
                    } else {
                        let signCorrectedError = errorValue * (rb >= ra ? 1 : -1)
                        sample = runDecoder.reconstructSample(prediction: rb, error: signCorrectedError)
                    }
                    print("    decoded sample=\(sample)")
                    
                    context.updateRunInterruptionContext(
                        errorValue: errorValue, eMappedErrorValue: eMappedErrorValue, riType: riType
                    )
                    decodedPixels[row][iCol] = sample
                    col = iCol + 1
                } else {
                    context.setRunIndex(runIndex)
                    col += actualRun
                }
            } else {
                // Regular mode - decode single pixel
                let contextIndex = context.computeContextIndex(q1: q1, q2: q2, q3: q3)
                let k = context.computeGolombParameter(contextIndex: contextIndex)
                let limitThreshold = limit - qbppBits - 1
                var unaryCount = 0
                while true {
                    let bit = try reader.readBits(1)
                    if bit == 1 { break }
                    unaryCount += 1
                }
                let mappedError: Int
                if unaryCount >= limitThreshold {
                    let rawValue = Int(try reader.readBits(qbppBits))
                    mappedError = rawValue + 1
                } else {
                    let rem = k > 0 ? Int(try reader.readBits(k)) : 0
                    mappedError = (unaryCount << k) | rem
                }
                let errorCorrection = context.getErrorCorrection(contextIndex: contextIndex, k: k)
                let result = decoder.decodePixel(
                    mappedError: mappedError, a: a, b: b, c: c, d: d,
                    context: context, errorCorrection: errorCorrection
                )
                context.updateContext(contextIndex: contextIndex, predictionError: result.error, sign: result.sign)
                decodedPixels[row][col] = result.sample
                print("    → Regular: ctx=\(contextIndex), k=\(k), mapped=\(mappedError), pixel=\(result.sample)")
                col += 1
            }
        }
    }
    
    print("\nDecoded pixels:")
    for row in decodedPixels { print("  \(row)") }
    print("Expected: [[128,128,128],[128,128,128],[128,128,128]]")
}

private extension String {
    func padLeft(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - self.count)) + self
    }
}
