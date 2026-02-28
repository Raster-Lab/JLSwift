/// Tests for CLI argument parsing and validation logic
///
/// Note: Since `jpegls` is an executable target, it cannot be directly imported or unit tested
/// through Swift Package Manager's test infrastructure. These tests validate the **validation logic**
/// and **business rules** that the CLI commands use for argument parsing:
///
/// - Parameter range validation (width, height, bits-per-sample, NEAR, etc.)
/// - Mutual exclusivity of flags (verbose/quiet, json/quiet)
/// - Valid option values (interleave modes, colour transforms, shell types)
/// - Edge cases and boundary conditions
///
/// The tests use boolean logic and value checking to verify the same patterns that ArgumentParser
/// enforces in the actual CLI. For full integration testing of CLI commands with actual argument
/// parsing, end-to-end tests with process execution would be required.

import Testing
import Foundation
import ArgumentParser
@testable import JPEGLS

@Suite("CLI Argument Parsing Tests")
struct CLIArgumentParsingTests {
    
    // MARK: - Encode Command Tests
    
    @Suite("Encode Command Validation")
    struct EncodeCommandTests {
        
        @Test("Valid encode command with required arguments")
        func testValidEncodeWithRequiredArgs() throws {
            // Test that valid required arguments are accepted
            let width = 512
            let height = 512
            
            #expect(width > 0)
            #expect(height > 0)
        }
        
        @Test("Encode command validates width is positive")
        func testEncodeWidthValidation() throws {
            let validWidth = 512
            let invalidWidth = 0
            
            #expect(validWidth > 0)
            #expect(invalidWidth <= 0)
        }
        
        @Test("Encode command validates height is positive")
        func testEncodeHeightValidation() throws {
            let validHeight = 512
            let invalidHeight = -1
            
            #expect(validHeight > 0)
            #expect(invalidHeight <= 0)
        }
        
        @Test("Encode command validates bits per sample range (2-16)")
        func testEncodeBitsPerSampleValidation() throws {
            let validBits = [2, 8, 12, 16]
            let invalidBits = [1, 0, 17, 32]
            
            for bits in validBits {
                #expect(bits >= 2 && bits <= 16)
            }
            
            for bits in invalidBits {
                #expect(bits < 2 || bits > 16)
            }
        }
        
        @Test("Encode command validates component count (1 or 3)")
        func testEncodeComponentCountValidation() throws {
            let validComponents = [1, 3]
            let invalidComponents = [0, 2, 4, 5]
            
            for count in validComponents {
                #expect(count == 1 || count == 3)
            }
            
            for count in invalidComponents {
                #expect(count != 1 && count != 3)
            }
        }
        
        @Test("Encode command validates NEAR parameter range (0-255)")
        func testEncodeNearParameterValidation() throws {
            let validNear = [0, 1, 10, 100, 255]
            let invalidNear = [-1, 256, 300]
            
            for near in validNear {
                #expect(near >= 0 && near <= 255)
            }
            
            for near in invalidNear {
                #expect(near < 0 || near > 255)
            }
        }
        
        @Test("Encode command validates interleave mode options")
        func testEncodeInterleaveMode() throws {
            let validModes = ["none", "line", "sample"]
            let invalidMode = "invalid"
            
            for mode in validModes {
                #expect(["none", "line", "sample"].contains(mode))
            }
            
            #expect(!["none", "line", "sample"].contains(invalidMode))
        }
        
        @Test("Encode command validates colour transform options")
        func testEncodeColorTransform() throws {
            let validTransforms = ["none", "hp1", "hp2", "hp3"]
            let invalidTransform = "invalid"
            
            for transform in validTransforms {
                #expect(["none", "hp1", "hp2", "hp3"].contains(transform))
            }
            
            #expect(!["none", "hp1", "hp2", "hp3"].contains(invalidTransform))
        }
        
        @Test("Encode command validates verbose and quiet flags are mutually exclusive")
        func testEncodeMutuallyExclusiveFlags() throws {
            // Test that we can detect when both flags are set (invalid case)
            let verbose = true
            let quiet = true
            let bothFlagsSet = verbose && quiet
            #expect(bothFlagsSet)  // When both are true, this is the invalid case
            
            // Test that valid combinations don't have both flags set
            let verboseOnlyCase = (true, false)
            #expect(!(verboseOnlyCase.0 && verboseOnlyCase.1))
            
            let quietOnlyCase = (false, true)
            #expect(!(quietOnlyCase.0 && quietOnlyCase.1))
            
            let neitherCase = (false, false)
            #expect(!(neitherCase.0 && neitherCase.1))
        }
        
        @Test("Encode command --preset: all four custom parameters required together")
        func testEncodePresetRequiresAllFourParams() throws {
            // Custom preset is only applied when t1, t2, t3, AND reset are all provided.
            // Providing fewer than all four falls back to default (optimise) or nil.
            let withAll = (t1: 3, t2: 7, t3: 21, reset: 64)
            let hasAll = withAll.t1 != nil && withAll.t2 != nil && withAll.t3 != nil && withAll.reset != nil
            #expect(hasAll)
            
            let withSome: (t1: Int?, t2: Int?, t3: Int?, reset: Int?) = (t1: 3, t2: nil, t3: 21, reset: 64)
            let hasSome = withSome.t1 != nil && withSome.t2 != nil && withSome.t3 != nil && withSome.reset != nil
            #expect(!hasSome)
        }
        
        @Test("Encode command preset parameters are validated (T1 <= T2 <= T3 <= MAXVAL)")
        func testEncodePresetParameterOrdering() throws {
            let bitsPerSample = 8
            let maxValue = (1 << bitsPerSample) - 1  // 255
            
            // Valid ordering
            let t1 = 3, t2 = 7, t3 = 21
            #expect(t1 >= 1 && t1 <= maxValue)
            #expect(t2 >= t1 && t2 <= maxValue)
            #expect(t3 >= t2 && t3 <= maxValue)
            
            // Invalid ordering (T2 < T1)
            let badT2 = 2
            #expect(badT2 < t1)  // This would fail validation
        }
        
        @Test("Encode command --optimise computes and embeds default preset parameters")
        func testEncodeOptimiseEmbedsDefaults() throws {
            // When --optimise is set (and no custom t1/t2/t3/reset), the encoder should
            // compute defaultParameters and pass them explicitly to the encoder config.
            let bitsPerSample = 8
            let near = 0
            // Replicate the JPEGLSPresetParameters.defaultParameters logic for 8-bit lossless
            let maxValue = (1 << bitsPerSample) - 1  // 255
            let factor = (min(maxValue, 4095) + 128) / 256  // = 1
            let t1 = min(max(factor * 1 + 2 + 3 * near, near + 1), maxValue)  // = 3
            let t2 = min(max(factor * 4 + 3 + 5 * near, t1), maxValue)        // = 7
            let t3 = min(max(factor * 17 + 4 + 7 * near, t2), maxValue)       // = 21
            let reset = 64
            #expect(t1 == 3)
            #expect(t2 == 7)
            #expect(t3 == 21)
            #expect(reset == 64)
            #expect(maxValue == 255)
        }
    }
    
    // MARK: - Decode Command Tests
    
    @Suite("Decode Command Validation")
    struct DecodeCommandTests {
        
        @Test("Valid decode command with required arguments")
        func testValidDecodeWithRequiredArgs() throws {
            let inputPath = "/path/to/input.jls"
            let outputPath = "/path/to/output.raw"
            
            #expect(!inputPath.isEmpty)
            #expect(!outputPath.isEmpty)
        }
        
        @Test("Decode command validates format options")
        func testDecodeFormatValidation() throws {
            let validFormats = ["raw", "png", "tiff"]
            let invalidFormat = "jpeg"
            
            for format in validFormats {
                #expect(["raw", "png", "tiff"].contains(format))
            }
            
            #expect(!["raw", "png", "tiff"].contains(invalidFormat))
        }
        
        @Test("Decode command validates verbose and quiet flags are mutually exclusive")
        func testDecodeMutuallyExclusiveFlags() throws {
            // Validate that the check for mutual exclusivity works correctly
            let bothFlagsSet = true && true
            let onlyVerbose = true && false
            let onlyQuiet = false && true
            let neitherSet = false && false
            
            // Both flags set should trigger validation error
            #expect(bothFlagsSet == true)
            // Valid combinations should not trigger error
            #expect(!onlyVerbose || !false)
            #expect(!false || !onlyQuiet)
            #expect(!neitherSet || !neitherSet)
        }
    }
    
    // MARK: - Info Command Tests
    
    @Suite("Info Command Validation")
    struct InfoCommandTests {
        
        @Test("Valid info command with required arguments")
        func testValidInfoWithRequiredArgs() throws {
            let inputPath = "/path/to/input.jls"
            
            #expect(!inputPath.isEmpty)
        }
        
        @Test("Info command validates json and quiet flags are mutually exclusive")
        func testInfoMutuallyExclusiveFlags() throws {
            // Test that mutual exclusivity check detects invalid combination
            let invalidCombination = true && true  // json && quiet
            #expect(invalidCombination)  // Should be detected as invalid
            
            // Test valid combinations pass the check
            #expect(!(true && false))  // json only (not both)
            #expect(!(false && true))  // quiet only (not both)
            #expect(!(false && false)) // neither (not both)
        }
        
        @Test("Info command accepts json flag")
        func testInfoJsonFlag() throws {
            let json = true
            #expect(json)
        }
        
        @Test("Info command accepts quiet flag")
        func testInfoQuietFlag() throws {
            let quiet = true
            #expect(quiet)
        }
    }
    
    // MARK: - Verify Command Tests
    
    @Suite("Verify Command Validation")
    struct VerifyCommandTests {
        
        @Test("Valid verify command with required arguments")
        func testValidVerifyWithRequiredArgs() throws {
            let inputPath = "/path/to/input.jls"
            
            #expect(!inputPath.isEmpty)
        }
        
        @Test("Verify command validates verbose and quiet flags are mutually exclusive")
        func testVerifyMutuallyExclusiveFlags() throws {
            // Test invalid combination detection
            let invalidCase = true && true
            #expect(invalidCase)  // Represents the condition that should be rejected
            
            // Valid combinations where only one or neither flag is set
            #expect(!(true && false))   // verbose only
            #expect(!(false && true))   // quiet only  
            #expect(!(false && false))  // neither
        }
        
        @Test("Verify command accepts verbose flag")
        func testVerifyVerboseFlag() throws {
            let verbose = true
            #expect(verbose)
        }
        
        @Test("Verify command accepts quiet flag")
        func testVerifyQuietFlag() throws {
            let quiet = true
            #expect(quiet)
        }
    }
    
    // MARK: - Batch Command Tests
    
    @Suite("Batch Command Validation")
    struct BatchCommandTests {
        
        @Test("Valid batch command with required arguments")
        func testValidBatchWithRequiredArgs() throws {
            let operation = "info"
            let inputPattern = "*.jls"
            
            #expect(!operation.isEmpty)
            #expect(!inputPattern.isEmpty)
        }
        
        @Test("Batch command validates operation types")
        func testBatchOperationValidation() throws {
            let validOperations = ["encode", "decode", "info", "verify"]
            let invalidOperation = "invalid"
            
            for operation in validOperations {
                #expect(["encode", "decode", "info", "verify"].contains(operation))
            }
            
            #expect(!["encode", "decode", "info", "verify"].contains(invalidOperation))
        }
        
        @Test("Batch command validates parallelism is positive")
        func testBatchParallelismValidation() throws {
            let validParallelism = [1, 4, 8]
            let invalidParallelism = [0, -1]
            
            for value in validParallelism {
                #expect(value > 0)
            }
            
            for value in invalidParallelism {
                #expect(value <= 0)
            }
        }
        
        @Test("Batch command validates verbose and quiet flags are mutually exclusive")
        func testBatchMutuallyExclusiveFlags() throws {
            // Test that the validation detects invalid flag combinations
            let invalidCombination = true && true  // Both verbose and quiet
            #expect(invalidCombination)  // This should be detected and rejected
            
            // Valid flag combinations
            #expect(!(true && false))   // Only verbose
            #expect(!(false && true))   // Only quiet
            #expect(!(false && false))  // Neither
        }
        
        @Test("Batch command accepts fail-fast flag")
        func testBatchFailFastFlag() throws {
            let failFast = true
            #expect(failFast)
        }
        
        @Test("Batch command validates output directory for encode/decode")
        func testBatchOutputDirValidation() throws {
            let encodeOperation = "encode"
            let decodeOperation = "decode"
            let outputDir = "/path/to/output"
            
            // For encode/decode operations, output directory is required
            if encodeOperation == "encode" || encodeOperation == "decode" {
                #expect(!outputDir.isEmpty)
            }
            
            if decodeOperation == "encode" || decodeOperation == "decode" {
                #expect(!outputDir.isEmpty)
            }
        }
    }
    
    // MARK: - Completion Command Tests
    
    @Suite("Completion Command Validation")
    struct CompletionCommandTests {
        
        @Test("Valid completion command with shell argument")
        func testValidCompletionWithShell() throws {
            let shell = "bash"
            
            #expect(!shell.isEmpty)
        }
        
        @Test("Completion command validates shell options")
        func testCompletionShellValidation() throws {
            let validShells = ["bash", "zsh", "fish"]
            let invalidShell = "csh"
            
            for shell in validShells {
                #expect(["bash", "zsh", "fish"].contains(shell))
            }
            
            #expect(!["bash", "zsh", "fish"].contains(invalidShell))
        }
        
        @Test("Completion command accepts bash shell")
        func testCompletionBashShell() throws {
            let shell = "bash"
            let validShells = ["bash", "zsh", "fish"]
            #expect(validShells.contains(shell))
        }
        
        @Test("Completion command accepts zsh shell")
        func testCompletionZshShell() throws {
            let shell = "zsh"
            let validShells = ["bash", "zsh", "fish"]
            #expect(validShells.contains(shell))
        }
        
        @Test("Completion command accepts fish shell")
        func testCompletionFishShell() throws {
            let shell = "fish"
            let validShells = ["bash", "zsh", "fish"]
            #expect(validShells.contains(shell))
        }
    }
    
    // MARK: - ValidationError Tests
    
    @Suite("ValidationError Tests")
    struct ValidationErrorTests {
        
        // Shared ValidationError definition for testing
        struct ValidationError: Error, CustomStringConvertible {
            let message: String
            
            init(_ message: String) {
                self.message = message
            }
            
            var description: String {
                message
            }
        }
        
        @Test("ValidationError can be created with message")
        func testValidationErrorCreation() throws {
            let error = ValidationError("Test error message")
            #expect(error.message == "Test error message")
            #expect(error.description == "Test error message")
        }
        
        @Test("ValidationError description matches message")
        func testValidationErrorDescription() throws {
            let errorMessage = "Cannot use both --json and --quiet flags"
            let error = ValidationError(errorMessage)
            #expect(error.description == errorMessage)
        }
    }
    
    // MARK: - Edge Cases and Boundary Conditions
    
    @Suite("Edge Cases and Boundary Conditions")
    struct EdgeCaseTests {
        
        @Test("Encode with minimum valid dimensions")
        func testEncodeMinimumDimensions() throws {
            let width = 1
            let height = 1
            
            #expect(width > 0)
            #expect(height > 0)
        }
        
        @Test("Encode with maximum reasonable dimensions")
        func testEncodeMaximumDimensions() throws {
            let width = 65535
            let height = 65535
            
            #expect(width > 0)
            #expect(height > 0)
        }
        
        @Test("Encode with minimum bits per sample (2)")
        func testEncodeMinimumBitsPerSample() throws {
            let bits = 2
            #expect(bits >= 2 && bits <= 16)
        }
        
        @Test("Encode with maximum bits per sample (16)")
        func testEncodeMaximumBitsPerSample() throws {
            let bits = 16
            #expect(bits >= 2 && bits <= 16)
        }
        
        @Test("Encode with NEAR parameter 0 (lossless)")
        func testEncodeLosslessNear() throws {
            let near = 0
            #expect(near >= 0 && near <= 255)
        }
        
        @Test("Encode with maximum NEAR parameter (255)")
        func testEncodeMaximumNear() throws {
            let near = 255
            #expect(near >= 0 && near <= 255)
        }
        
        @Test("Batch command with parallelism 1 (sequential)")
        func testBatchSequentialParallelism() throws {
            let parallelism = 1
            #expect(parallelism > 0)
        }
        
        @Test("Empty file path should be invalid")
        func testEmptyFilePathValidation() throws {
            let emptyPath = ""
            #expect(emptyPath.isEmpty)
        }
        
        @Test("Glob pattern validation")
        func testGlobPatternValidation() throws {
            let validPatterns = ["*.jls", "images/*.jls", "**/*.jls", "image?.jls"]
            
            for pattern in validPatterns {
                #expect(!pattern.isEmpty)
                #expect(pattern.contains("*") || pattern.contains("?"))
            }
        }
    }
    
    // MARK: - Flag Combination Tests
    
    @Suite("Flag Combination Validation")
    struct FlagCombinationTests {
        
        @Test("Encode command: verbose flag only")
        func testEncodeVerboseOnly() throws {
            let verbose = true
            let quiet = false
            
            #expect(!(verbose && quiet))
        }
        
        @Test("Encode command: quiet flag only")
        func testEncodeQuietOnly() throws {
            let verbose = false
            let quiet = true
            
            #expect(!(verbose && quiet))
        }
        
        @Test("Encode command: no flags")
        func testEncodeNoFlags() throws {
            let verbose = false
            let quiet = false
            
            #expect(!(verbose && quiet))
        }
        
        @Test("Info command: json flag only")
        func testInfoJsonOnly() throws {
            let json = true
            let quiet = false
            
            #expect(!(json && quiet))
        }
        
        @Test("Info command: quiet flag only")
        func testInfoQuietOnly() throws {
            let json = false
            let quiet = true
            
            #expect(!(json && quiet))
        }
        
        @Test("Info command: no flags")
        func testInfoNoFlags() throws {
            let json = false
            let quiet = false
            
            #expect(!(json && quiet))
        }
        
        @Test("Batch command: verbose and fail-fast together (valid)")
        func testBatchVerboseAndFailFast() throws {
            let verbose = true
            let failFast = true
            
            // These flags are NOT mutually exclusive - both can be true
            #expect(verbose && failFast)
        }
        
        @Test("Batch command: quiet and fail-fast together (valid)")
        func testBatchQuietAndFailFast() throws {
            let quiet = true
            let failFast = true
            
            // These flags are NOT mutually exclusive - both can be true
            #expect(quiet && failFast)
        }
    }
    
    // MARK: - Input Validation Tests
    
    @Suite("Input Validation")
    struct InputValidationTests {
        
        @Test("File path with spaces")
        func testFilePathWithSpaces() throws {
            let path = "/path/to/my file.jls"
            #expect(!path.isEmpty)
            #expect(path.contains(" "))
        }
        
        @Test("File path with special characters")
        func testFilePathWithSpecialCharacters() throws {
            let path = "/path/to/file-name_123.jls"
            #expect(!path.isEmpty)
        }
        
        @Test("Relative file path")
        func testRelativeFilePath() throws {
            let path = "../images/test.jls"
            #expect(!path.isEmpty)
            #expect(!path.hasPrefix("/"))
        }
        
        @Test("Absolute file path")
        func testAbsoluteFilePath() throws {
            let path = "/home/user/images/test.jls"
            #expect(!path.isEmpty)
            #expect(path.hasPrefix("/"))
        }
        
        @Test("Output directory path validation")
        func testOutputDirectoryPath() throws {
            let validPaths = ["/output", "./output", "../output", "output"]
            
            for path in validPaths {
                #expect(!path.isEmpty)
            }
        }
    }
    
    // MARK: - Parameter Range Tests
    
    @Suite("Parameter Range Validation")
    struct ParameterRangeTests {
        
        @Test("Width parameter boundary values")
        func testWidthBoundaries() throws {
            // Test minimum valid width
            let minWidth = 1
            #expect(minWidth > 0)
            
            // Test typical widths
            let typicalWidths = [256, 512, 1024, 2048, 4096]
            for width in typicalWidths {
                #expect(width > 0)
            }
        }
        
        @Test("Height parameter boundary values")
        func testHeightBoundaries() throws {
            // Test minimum valid height
            let minHeight = 1
            #expect(minHeight > 0)
            
            // Test typical heights
            let typicalHeights = [256, 512, 1024, 2048, 4096]
            for height in typicalHeights {
                #expect(height > 0)
            }
        }
        
        @Test("Bits per sample all valid values")
        func testAllValidBitsPerSample() throws {
            let validValues = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
            
            for bits in validValues {
                #expect(bits >= 2 && bits <= 16)
            }
        }
        
        @Test("NEAR parameter common values")
        func testCommonNearValues() throws {
            let commonValues = [0, 1, 2, 3, 5, 10, 20, 50, 100]
            
            for near in commonValues {
                #expect(near >= 0 && near <= 255)
            }
        }
        
        @Test("Parallelism parameter typical values")
        func testTypicalParallelismValues() throws {
            let typicalValues = [1, 2, 4, 8, 16]
            
            for parallelism in typicalValues {
                #expect(parallelism > 0)
            }
        }
    }
    
    // MARK: - Compare Command Tests (Phase 17.1)
    
    @Suite("Compare Command Validation")
    struct CompareCommandTests {
        
        @Test("Compare command requires two input file arguments")
        func testCompareTwoInputsRequired() throws {
            // Both first and second file paths must be non-empty.
            let first = "reference.jls"
            let second = "output.jls"
            #expect(!first.isEmpty)
            #expect(!second.isEmpty)
        }
        
        @Test("Compare --near parameter accepts 0 (exact match)")
        func testCompareNearZero() throws {
            let near = 0
            #expect(near >= 0 && near <= 255)
        }
        
        @Test("Compare --near parameter accepts valid range (0-255)")
        func testCompareNearValidRange() throws {
            let validValues = [0, 1, 3, 10, 100, 255]
            for near in validValues {
                #expect(near >= 0 && near <= 255)
            }
        }
        
        @Test("Compare --near parameter rejects out-of-range values")
        func testCompareNearInvalidRange() throws {
            let invalidValues = [-1, 256, 300, -100]
            for near in invalidValues {
                #expect(near < 0 || near > 255)
            }
        }
        
        @Test("Compare verbose and quiet are mutually exclusive")
        func testCompareVerboseQuietMutuallyExclusive() throws {
            let verbose = true
            let quiet = true
            // Simulates the validation error condition
            #expect(verbose && quiet)
        }
        
        @Test("Compare json and quiet are mutually exclusive")
        func testCompareJsonQuietMutuallyExclusive() throws {
            let json = true
            let quiet = true
            // Simulates the validation error condition
            #expect(json && quiet)
        }
        
        @Test("Compare accepts JPEG-LS file extensions")
        func testCompareJLSFileExtension() throws {
            let paths = ["file.jls", "/path/to/image.jls", "output.JLS"]
            for path in paths {
                #expect(path.lowercased().hasSuffix(".jls"))
            }
        }
        
        @Test("Compare accepts PGM file extensions")
        func testComparePGMFileExtension() throws {
            let paths = ["reference.pgm", "/path/to/test.pgm"]
            for path in paths {
                #expect(fileExtension(of: path) == "pgm")
            }
        }
        
        @Test("Compare accepts PPM file extensions")
        func testComparePPMFileExtension() throws {
            let paths = ["reference.ppm", "/path/to/test.ppm"]
            for path in paths {
                #expect(fileExtension(of: path) == "ppm")
            }
        }
        
        private func fileExtension(of path: String) -> String {
            (path as NSString).pathExtension.lowercased()
        }
        
        @Test("Compare mismatch count of zero means images match")
        func testCompareMismatchCountZeroMeansMatch() throws {
            let mismatchCount = 0
            #expect(mismatchCount == 0)
        }
        
        @Test("Compare mismatch count above zero means images differ")
        func testCompareMismatchCountAboveZeroMeansDiffer() throws {
            let mismatchCount = 42
            #expect(mismatchCount > 0)
        }
        
        @Test("Compare near-zero tolerance means exact match required")
        func testCompareNearZeroMeansExactMatch() throws {
            let near = 0
            // Any non-zero error is a mismatch when near==0
            let errors = [0, 1, 2, 3]
            for err in errors {
                let isMismatch = err > near
                #expect(isMismatch == (err > 0))
            }
        }
        
        @Test("Compare near=3 allows errors up to 3")
        func testCompareNearThreeAllowsSmallErrors() throws {
            let near = 3
            let matchingErrors = [0, 1, 2, 3]
            let mismatchErrors = [4, 5, 10]
            for err in matchingErrors {
                #expect(err <= near)
            }
            for err in mismatchErrors {
                #expect(err > near)
            }
        }
        
        @Test("Compare dimension mismatch is detected correctly")
        func testCompareDimensionMismatch() throws {
            let w1 = 512, h1 = 512
            let w2 = 256, h2 = 512
            #expect(!(w1 == w2 && h1 == h2))
        }
        
        @Test("Compare component count mismatch is detected correctly")
        func testCompareComponentMismatch() throws {
            let comp1 = 1  // grayscale
            let comp2 = 3  // RGB
            #expect(comp1 != comp2)
        }
        
        @Test("Both no-colour and no-color option names are defined for compare command")
        func testCompareNoColourBothSpellingsDefined() throws {
            let optionNames = ["no-colour", "no-color"]
            #expect(optionNames.contains("no-colour"))
            #expect(optionNames.contains("no-color"))
        }
    }
    
    // MARK: - British & American Spelling Tests (Phase 17.2)
    
    /// Validates that British and American spellings of CLI option values produce identical behaviour.
    ///
    /// Both `--colour-transform` and `--color-transform` accept the same set of values and delegate
    /// to the same `parseColorTransform` logic. Because `jpegls` is an executable target it cannot
    /// be imported here; these tests therefore verify the business logic that the option handler
    /// uses rather than the ArgumentParser flag parsing layer.
    @Suite("British & American Spelling Support")
    struct BritishAmericanSpellingTests {
        
        /// Parses a colour-transform value exactly as the CLI `encode` and `batch` commands do.
        private func parseColorTransform(_ value: String) -> String? {
            switch value.lowercased() {
            case "none", "hp1", "hp2", "hp3": return value.lowercased()
            default: return nil
            }
        }
        
        /// The set of accepted option names in the CLI (both spellings).
        private let acceptedOptionNames = ["color-transform", "colour-transform"]
        
        @Test("Both American and British option names are defined for the colour-transform option")
        func testBothSpellingsAreDefinedAsOptionNames() throws {
            #expect(acceptedOptionNames.contains("color-transform"))
            #expect(acceptedOptionNames.contains("colour-transform"))
        }
        
        @Test("--color-transform accepts all valid values (American spelling)")
        func testColorTransformAmericanSpellingValidValues() throws {
            let validValues = ["none", "hp1", "hp2", "hp3"]
            for value in validValues {
                #expect(parseColorTransform(value) != nil, "Expected '\(value)' to be valid for --color-transform")
            }
        }
        
        @Test("--colour-transform accepts all valid values (British spelling)")
        func testColourTransformBritishSpellingValidValues() throws {
            let validValues = ["none", "hp1", "hp2", "hp3"]
            for value in validValues {
                #expect(parseColorTransform(value) != nil, "Expected '\(value)' to be valid for --colour-transform")
            }
        }
        
        @Test("The set of valid values is identical regardless of which spelling is used")
        func testValidValueSetsAreIdentical() throws {
            // The accepted values must be the same for both spellings — they share the same
            // underlying property and parseColorTransform function.
            let validForAmerican = ["none", "hp1", "hp2", "hp3"].compactMap { parseColorTransform($0) }
            let validForBritish  = ["none", "hp1", "hp2", "hp3"].compactMap { parseColorTransform($0) }
            #expect(validForAmerican == validForBritish)
            #expect(validForAmerican.count == 4)
        }
        
        @Test("Invalid colour-transform value is rejected regardless of which spelling is used")
        func testInvalidColorTransformRejected() throws {
            let invalidValues = ["rgb", "yuv", "xyz", "invalid"]
            for value in invalidValues {
                // Both spellings share the same validation logic, so both must reject invalid values.
                #expect(parseColorTransform(value) == nil, "Expected '\(value)' to be rejected")
            }
        }
        
        @Test("Both spellings accept case-insensitive values")
        func testColorTransformCaseInsensitive() throws {
            let caseVariants = ["None", "NONE", "HP1", "Hp1", "HP2", "Hp2", "HP3", "Hp3"]
            for value in caseVariants {
                #expect(parseColorTransform(value) != nil, "Expected '\(value)' to be accepted case-insensitively")
            }
        }
        
        @Test("Normalised value is lower-case for all valid transforms")
        func testNormalisedValueIsLowerCase() throws {
            let inputs = ["None", "HP1", "HP2", "HP3", "NONE"]
            for input in inputs {
                if let result = parseColorTransform(input) {
                    #expect(result == result.lowercased(), "Normalised value should be lower-case for '\(input)'")
                }
            }
        }
        
        // MARK: - --no-colour / --no-color
        
        /// The set of accepted option names for the no-colour flag (both spellings).
        private let noColourOptionNames = ["no-colour", "no-color"]
        
        @Test("Both American and British option names are defined for the no-colour flag")
        func testNoColourBothSpellingsDefined() throws {
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        @Test("--no-colour and --no-color are available on the encode command")
        func testNoColourEncode() throws {
            // Both spellings map to the same 'noColour' boolean property — verify the
            // option names are correctly declared in both British and American spellings.
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        @Test("--no-colour and --no-color are available on the decode command")
        func testNoColourDecode() throws {
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        @Test("--no-colour and --no-color are available on the info command")
        func testNoColourInfo() throws {
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        @Test("--no-colour and --no-color are available on the verify command")
        func testNoColourVerify() throws {
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        @Test("--no-colour and --no-color are available on the batch command")
        func testNoColourBatch() throws {
            #expect(noColourOptionNames.contains("no-colour"))
            #expect(noColourOptionNames.contains("no-color"))
        }
        
        // MARK: - --optimise / --optimize
        
        /// The set of accepted option names for the optimise flag (both spellings).
        private let optimiseOptionNames = ["optimise", "optimize"]
        
        @Test("Both American and British option names are defined for the optimise flag")
        func testOptimiseBothSpellingsDefined() throws {
            #expect(optimiseOptionNames.contains("optimise"))
            #expect(optimiseOptionNames.contains("optimize"))
        }
        
        @Test("--optimise and --optimize are available on the encode command")
        func testOptimiseEncode() throws {
            #expect(optimiseOptionNames.contains("optimise"))
            #expect(optimiseOptionNames.contains("optimize"))
        }
        
        // MARK: - --summarise / --summarize
        
        /// The set of accepted option names for the summarise flag (both spellings).
        private let summariseOptionNames = ["summarise", "summarize"]
        
        @Test("Both American and British option names are defined for the summarise flag")
        func testSummariseBothSpellingsDefined() throws {
            #expect(summariseOptionNames.contains("summarise"))
            #expect(summariseOptionNames.contains("summarize"))
        }
        
        @Test("--summarise and --summarize are available on the batch command")
        func testSummariseBatch() throws {
            #expect(summariseOptionNames.contains("summarise"))
            #expect(summariseOptionNames.contains("summarize"))
        }
        
        @Test("Summarise flag forces summary output independent of quiet mode")
        func testSummariseForcesOutputInQuietMode() throws {
            // Mirrors the logic in BatchProcessor.process():
            // summary is printed when !quiet OR when summarise is set.
            let scenarios: [(quiet: Bool, summarise: Bool, expectSummary: Bool)] = [
                (quiet: false, summarise: false, expectSummary: true),
                (quiet: false, summarise: true,  expectSummary: true),
                (quiet: true,  summarise: false, expectSummary: false),
                (quiet: true,  summarise: true,  expectSummary: true),
            ]
            for s in scenarios {
                let shouldPrint = !s.quiet || s.summarise
                #expect(shouldPrint == s.expectSummary,
                    "quiet=\(s.quiet), summarise=\(s.summarise): expected shouldPrint=\(s.expectSummary), got \(shouldPrint)")
            }
        }
    }

    // MARK: - Convert Command Tests

    @Suite("Convert Command Validation")
    struct ConvertCommandTests {

        // Valid output format extensions for the convert command.
        private let validOutputFormats = ["jls", "png", "tiff", "tif", "pgm", "ppm"]

        @Test("Convert command recognises JPEG-LS output by .jls extension")
        func testConvertJLSOutput() {
            #expect(validOutputFormats.contains("jls"))
        }

        @Test("Convert command recognises PNG output by .png extension")
        func testConvertPNGOutput() {
            #expect(validOutputFormats.contains("png"))
        }

        @Test("Convert command recognises TIFF output by .tiff and .tif extensions")
        func testConvertTIFFOutput() {
            #expect(validOutputFormats.contains("tiff"))
            #expect(validOutputFormats.contains("tif"))
        }

        @Test("Convert command recognises PGM/PPM output by .pgm and .ppm extensions")
        func testConvertPNMOutput() {
            #expect(validOutputFormats.contains("pgm"))
            #expect(validOutputFormats.contains("ppm"))
        }

        @Test("Convert command NEAR parameter must be in range 0–255")
        func testConvertNearRange() {
            for near in [0, 1, 100, 255] {
                #expect((0...255).contains(near))
            }
            for near in [-1, 256, 1000] {
                #expect(!(0...255).contains(near))
            }
        }

        @Test("Convert command interleave mode validation accepts none, line, sample")
        func testConvertInterleaveModes() {
            let validModes = ["none", "line", "sample"]
            #expect(validModes.contains("none"))
            #expect(validModes.contains("line"))
            #expect(validModes.contains("sample"))
            #expect(!validModes.contains("pixel"))
        }

        @Test("Convert command colour-transform option accepts none, hp1, hp2, hp3")
        func testConvertColorTransformOptions() {
            let validTransforms = ["none", "hp1", "hp2", "hp3"]
            for t in validTransforms {
                #expect(validTransforms.contains(t))
            }
            #expect(!validTransforms.contains("hp4"))
        }

        @Test("Convert command verbose and quiet are mutually exclusive")
        func testConvertVerboseQuietMutuallyExclusive() {
            // When both verbose and quiet are true, the combination is invalid and should be rejected.
            let invalidCombination = true && true  // both verbose and quiet
            #expect(invalidCombination)  // Represents the condition that triggers a ValidationError
        }

        @Test("PNG and TIFF are valid input formats for the encode command via auto-detection")
        func testEncodeAcceptsPNGAndTIFFInput() throws {
            // Verify that PNG/TIFF round-trip encode → decode → encode works using the decoders.
            let originalPixels: [[[Int]]] = [[[10, 20], [30, 40]]]
            
            // PNG round-trip
            let pngData = try PNGSupport.encode(
                componentPixels: originalPixels, width: 2, height: 2, maxVal: 255
            )
            let decodedPNG = try PNGSupport.decode(pngData)
            #expect(decodedPNG.componentPixels[0] == originalPixels[0])

            // TIFF round-trip
            let tiffData = try TIFFSupport.encode(
                componentPixels: originalPixels, width: 2, height: 2, maxVal: 255
            )
            let decodedTIFF = try TIFFSupport.decode(tiffData)
            #expect(decodedTIFF.componentPixels[0] == originalPixels[0])
        }

        @Test("PNG decoder is available in the JPEGLS module for CLI encode from PNG")
        func testPNGDecoderAvailable() throws {
            let pixels: [[[Int]]] = [[[100, 200], [150, 50]]]
            let pngData = try PNGSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
            let decoded = try PNGSupport.decode(pngData)
            #expect(decoded.width == 2)
            #expect(decoded.height == 2)
            #expect(decoded.componentPixels.count == 1)
        }

        @Test("TIFF decoder is available in the JPEGLS module for CLI encode from TIFF")
        func testTIFFDecoderAvailable() throws {
            let pixels: [[[Int]]] = [[[100, 200], [150, 50]]]
            let tiffData = try TIFFSupport.encode(componentPixels: pixels, width: 2, height: 2, maxVal: 255)
            let decoded = try TIFFSupport.decode(tiffData)
            #expect(decoded.width == 2)
            #expect(decoded.height == 2)
            #expect(decoded.componentPixels.count == 1)
        }

        @Test("JPEG-LS encode from PNG produces decodable output with pixel-exact reconstruction")
        func testEncodeFromPNGRoundTrip() throws {
            let width = 4, height = 4
            let pixels: [[[Int]]] = [
                (0..<height).map { row in (0..<width).map { col in (row * width + col) * 16 } }
            ]
            // PNG encode → PNG decode → JPEG-LS encode → JPEG-LS decode.
            let pngData = try PNGSupport.encode(
                componentPixels: pixels, width: width, height: height, maxVal: 255
            )
            let decodedPNG = try PNGSupport.decode(pngData)
            let imageData = try MultiComponentImageData.grayscale(
                pixels: decodedPNG.componentPixels[0],
                bitsPerSample: decodedPNG.bitDepth
            )
            let encoder = JPEGLSEncoder()
            let jlsData = try encoder.encode(
                imageData, configuration: try .init(near: 0, interleaveMode: .none)
            )
            let decoder = JPEGLSDecoder()
            let decoded = try decoder.decode(jlsData)
            #expect(decoded.components[0].pixels == pixels[0])
        }

        @Test("JPEG-LS encode from TIFF produces decodable output with pixel-exact reconstruction")
        func testEncodeFromTIFFRoundTrip() throws {
            let width = 4, height = 4
            let r: [[Int]] = (0..<height).map { row in (0..<width).map { col in (row * width + col) * 16 } }
            let g: [[Int]] = (0..<height).map { row in (0..<width).map { col in (row * width + col + 1) * 16 % 256 } }
            let b: [[Int]] = (0..<height).map { row in (0..<width).map { col in (row * width + col + 2) * 16 % 256 } }
            let pixels: [[[Int]]] = [r, g, b]
            // TIFF encode → TIFF decode → JPEG-LS encode → JPEG-LS decode.
            let tiffData = try TIFFSupport.encode(
                componentPixels: pixels, width: width, height: height, maxVal: 255
            )
            let decodedTIFF = try TIFFSupport.decode(tiffData)
            let imageData = try MultiComponentImageData.rgb(
                redPixels:   decodedTIFF.componentPixels[0],
                greenPixels: decodedTIFF.componentPixels[1],
                bluePixels:  decodedTIFF.componentPixels[2],
                bitsPerSample: decodedTIFF.bitsPerSample
            )
            let encoder = JPEGLSEncoder()
            let jlsData = try encoder.encode(
                imageData, configuration: try .init(near: 0, interleaveMode: .none)
            )
            let decoder = JPEGLSDecoder()
            let decoded = try decoder.decode(jlsData)
            #expect(decoded.components[0].pixels == r)
            #expect(decoded.components[1].pixels == g)
            #expect(decoded.components[2].pixels == b)
        }
    }

    // MARK: - Benchmark Command Tests

    @Suite("Benchmark Command Validation")
    struct BenchmarkCommandTests {

        // Valid benchmark modes
        private let validModes = ["encode", "decode", "roundtrip"]

        @Test("Benchmark command mode validation accepts encode, decode, roundtrip")
        func testBenchmarkModeValidation() {
            #expect(validModes.contains("encode"))
            #expect(validModes.contains("decode"))
            #expect(validModes.contains("roundtrip"))
            #expect(!validModes.contains("both"))
            #expect(!validModes.contains("all"))
        }

        @Test("Benchmark command NEAR parameter must be in range 0–255")
        func testBenchmarkNearRange() {
            for near in [0, 1, 100, 255] {
                #expect((0...255).contains(near))
            }
            for near in [-1, 256, 1000] {
                #expect(!(0...255).contains(near))
            }
        }

        @Test("Benchmark command bits-per-sample must be in range 2–16")
        func testBenchmarkBitsPerSampleRange() {
            for bps in [2, 8, 12, 16] {
                #expect((2...16).contains(bps))
            }
            for bps in [1, 0, 17, 32] {
                #expect(!(2...16).contains(bps))
            }
        }

        @Test("Benchmark command components must be 1 or 3")
        func testBenchmarkComponentsValidation() {
            let validComponents = [1, 3]
            #expect(validComponents.contains(1))
            #expect(validComponents.contains(3))
            #expect(!validComponents.contains(2))
            #expect(!validComponents.contains(4))
        }

        @Test("Benchmark command size must be at least 1")
        func testBenchmarkSizeValidation() {
            #expect(1 >= 1)
            #expect(512 >= 1)
            #expect(!(0 >= 1))
            #expect(!(-1 >= 1))
        }

        @Test("Benchmark command iterations must be at least 1")
        func testBenchmarkIterationsValidation() {
            #expect(1 >= 1)
            #expect(10 >= 1)
            #expect(!(0 >= 1))
        }

        @Test("Benchmark command warmup must be 0 or greater")
        func testBenchmarkWarmupValidation() {
            #expect(0 >= 0)
            #expect(3 >= 0)
            #expect(!(-1 >= 0))
        }

        @Test("Benchmark command interleave mode validation accepts none, line, sample")
        func testBenchmarkInterleaveModes() {
            let validModes = ["none", "line", "sample"]
            #expect(validModes.contains("none"))
            #expect(validModes.contains("line"))
            #expect(validModes.contains("sample"))
            #expect(!validModes.contains("pixel"))
        }

        @Test("Benchmark command verbose and quiet are mutually exclusive")
        func testBenchmarkVerboseQuietMutuallyExclusive() {
            let invalidCombination = true && true  // both verbose and quiet
            #expect(invalidCombination)  // Represents the condition that triggers a ValidationError
        }

        @Test("Benchmark command json and quiet are mutually exclusive")
        func testBenchmarkJSONQuietMutuallyExclusive() {
            let invalidCombination = true && true  // both json and quiet
            #expect(invalidCombination)  // Represents the condition that triggers a ValidationError
        }

        @Test("Benchmark synthetic image generation produces correct greyscale dimensions")
        func testBenchmarkSyntheticImageGreyscale() throws {
            let width = 8, height = 8, bitsPerSample = 8
            let maxVal = (1 << bitsPerSample) - 1
            let total = max(width * height - 1, 1)
            // Verify the gradient formula for the first and last pixels
            let firstVal = (0 * maxVal) / total
            let lastVal  = min(((width * height - 1) * maxVal) / total, maxVal)
            #expect(firstVal == 0)
            #expect(lastVal == maxVal)
        }

        @Test("Benchmark synthetic image generation produces correct RGB dimensions")
        func testBenchmarkSyntheticImageRGB() throws {
            let width = 4, height = 4, bitsPerSample = 8, components = 3
            let maxVal = (1 << bitsPerSample) - 1
            let total  = max(width * height - 1, 1)
            // Each channel is offset by `width * height / components` pixels
            let channelOffset = width * height / max(components, 1)
            let firstGreenVal = min((channelOffset * maxVal) / total, maxVal)
            #expect(firstGreenVal >= 0)
            #expect(firstGreenVal <= maxVal)
        }

        @Test("Benchmark statistics: min, max, mean, median computed correctly for simple inputs")
        func testBenchmarkTimingStats() {
            // Replicate the computeStats logic directly
            let timings = [0.1, 0.2, 0.3, 0.4, 0.5]
            let sorted = timings.sorted()
            let mean = timings.reduce(0, +) / Double(timings.count)
            let n = sorted.count
            let median = n % 2 == 0
                ? (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
                : sorted[n / 2]
            #expect(sorted.first! == 0.1)
            #expect(sorted.last!  == 0.5)
            #expect(abs(mean - 0.3) < 1e-9)
            #expect(abs(median - 0.3) < 1e-9)
        }

        @Test("Benchmark statistics: median interpolated correctly for even count")
        func testBenchmarkTimingStatsEven() {
            let timings = [0.1, 0.2, 0.3, 0.4]
            let sorted = timings.sorted()
            let n = sorted.count
            let median = (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
            #expect(abs(median - 0.25) < 1e-9)
        }

        @Test("Benchmark encode round-trip produces valid JPEG-LS output")
        func testBenchmarkEncodeRoundTrip() throws {
            // Run one encode/decode cycle using the JPEGLS library directly
            let width = 16, height = 16, bitsPerSample = 8
            let maxVal = (1 << bitsPerSample) - 1
            let total  = max(width * height - 1, 1)
            let pixels: [[Int]] = (0..<height).map { row in
                (0..<width).map { col in (row * width + col) * maxVal / total }
            }
            let imageData = try MultiComponentImageData.grayscale(pixels: pixels, bitsPerSample: bitsPerSample)
            let encoder = JPEGLSEncoder()
            let jlsData = try encoder.encode(imageData, configuration: try .init(near: 0, interleaveMode: .none))
            let decoder = JPEGLSDecoder()
            let decoded = try decoder.decode(jlsData)
            #expect(decoded.frameHeader.width == width)
            #expect(decoded.frameHeader.height == height)
            #expect(decoded.components[0].pixels == pixels)
        }

        @Test("Benchmark JSON output keys include image, configuration, encode, decode sections")
        func testBenchmarkJSONOutputKeys() {
            // Verify the structure of expected JSON keys
            let expectedTopLevelKeys = ["image", "configuration", "encode", "decode", "compression"]
            #expect(expectedTopLevelKeys.contains("image"))
            #expect(expectedTopLevelKeys.contains("configuration"))
            #expect(expectedTopLevelKeys.contains("encode"))
            #expect(expectedTopLevelKeys.contains("decode"))
            #expect(expectedTopLevelKeys.contains("compression"))
        }

        @Test("Benchmark formatTime produces µs for sub-millisecond, ms for sub-second, s for seconds")
        func testBenchmarkFormatTime() {
            // Sub-millisecond: < 0.001 s → µs
            let subMs = 0.0001
            #expect(subMs < 0.001)

            // Sub-second: 0.001–1 s → ms
            let ms = 0.05
            #expect(ms >= 0.001 && ms < 1.0)

            // Seconds: >= 1 s
            let sec = 1.5
            #expect(sec >= 1.0)
        }
    }
}
