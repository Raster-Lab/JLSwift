import Testing
@testable import JLSwift

@Suite("String Extension Tests")
struct JLSStringExtensionsTests {
    // MARK: - trimmed

    @Test("Trimming removes leading and trailing whitespace")
    func trimmed() {
        #expect("  hello  ".trimmed() == "hello")
        #expect("\n\thello\t\n".trimmed() == "hello")
        #expect("hello".trimmed() == "hello")
        #expect("   ".trimmed() == "")
        #expect("".trimmed() == "")
    }

    // MARK: - capitalizedFirst

    @Test("First letter is capitalized")
    func capitalizedFirst() {
        #expect("hello world".capitalizedFirst() == "Hello world")
        #expect("swift".capitalizedFirst() == "Swift")
    }

    @Test("Already capitalized string stays the same")
    func alreadyCapitalized() {
        #expect("Hello".capitalizedFirst() == "Hello")
    }

    @Test("Empty string stays empty when capitalizing")
    func capitalizedFirstEmpty() {
        #expect("".capitalizedFirst() == "")
    }

    @Test("Single character is capitalized")
    func capitalizedFirstSingleChar() {
        #expect("a".capitalizedFirst() == "A")
    }

    // MARK: - isAlphanumeric

    @Test("Alphanumeric strings return true")
    func alphanumericValid() {
        #expect("abc123".isAlphanumeric)
        #expect("Hello".isAlphanumeric)
        #expect("42".isAlphanumeric)
    }

    @Test("Non-alphanumeric strings return false")
    func alphanumericInvalid() {
        #expect(!"hello world".isAlphanumeric)
        #expect(!"hello!".isAlphanumeric)
        #expect(!"@#$".isAlphanumeric)
    }

    @Test("Empty string is not alphanumeric")
    func alphanumericEmpty() {
        #expect(!"".isAlphanumeric)
    }

    // MARK: - repeated

    @Test("String is repeated the given number of times")
    func repeated() {
        #expect("ab".repeated(3) == "ababab")
        #expect("x".repeated(1) == "x")
    }

    @Test("Zero or negative repeat count returns empty string")
    func repeatedZero() {
        #expect("hello".repeated(0) == "")
        #expect("hello".repeated(-1) == "")
    }

    // MARK: - wordCount

    @Test("Word count returns correct number of words")
    func wordCount() {
        #expect("hello world".wordCount == 2)
        #expect("one".wordCount == 1)
        #expect("a b c d".wordCount == 4)
    }

    @Test("Empty string has zero words")
    func wordCountEmpty() {
        #expect("".wordCount == 0)
    }

    @Test("Whitespace-only string has zero words")
    func wordCountWhitespace() {
        #expect("   ".wordCount == 0)
        #expect("\n\t".wordCount == 0)
    }
}
