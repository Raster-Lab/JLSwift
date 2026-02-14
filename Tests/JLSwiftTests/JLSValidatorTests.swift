import Testing
import Foundation
@testable import JLSwift

@Suite("JLSValidator Tests")
struct JLSValidatorTests {
    // MARK: - isValidEmail

    @Test("Valid email addresses are accepted")
    func validEmails() {
        #expect(JLSValidator.isValidEmail("user@example.com"))
        #expect(JLSValidator.isValidEmail("test.user@domain.co"))
        #expect(JLSValidator.isValidEmail("a@b.c"))
    }

    @Test("Email without @ is rejected")
    func emailWithoutAt() {
        #expect(!JLSValidator.isValidEmail("userexample.com"))
    }

    @Test("Email with multiple @ is rejected")
    func emailWithMultipleAt() {
        #expect(!JLSValidator.isValidEmail("user@@example.com"))
        #expect(!JLSValidator.isValidEmail("u@s@example.com"))
    }

    @Test("Email with empty local part is rejected")
    func emailEmptyLocal() {
        #expect(!JLSValidator.isValidEmail("@example.com"))
    }

    @Test("Email with empty domain is rejected")
    func emailEmptyDomain() {
        #expect(!JLSValidator.isValidEmail("user@"))
    }

    @Test("Email without dot in domain is rejected")
    func emailNoDotInDomain() {
        #expect(!JLSValidator.isValidEmail("user@example"))
    }

    @Test("Email with empty domain segment is rejected")
    func emailEmptyDomainSegment() {
        #expect(!JLSValidator.isValidEmail("user@.com"))
        #expect(!JLSValidator.isValidEmail("user@example."))
    }

    @Test("Empty string is not a valid email")
    func emailEmpty() {
        #expect(!JLSValidator.isValidEmail(""))
    }

    // MARK: - isNonEmpty

    @Test("Non-empty strings return true")
    func nonEmptyStrings() {
        #expect(JLSValidator.isNonEmpty("hello"))
        #expect(JLSValidator.isNonEmpty("a"))
    }

    @Test("Empty and whitespace-only strings return false")
    func emptyStrings() {
        #expect(!JLSValidator.isNonEmpty(""))
        #expect(!JLSValidator.isNonEmpty("   "))
        #expect(!JLSValidator.isNonEmpty("\n\t"))
    }

    // MARK: - isLengthValid

    @Test("String within length range is valid")
    func lengthValid() {
        #expect(JLSValidator.isLengthValid("abc", min: 1, max: 5))
        #expect(JLSValidator.isLengthValid("ab", min: 2, max: 2))
    }

    @Test("String below minimum length is invalid")
    func lengthTooShort() {
        #expect(!JLSValidator.isLengthValid("a", min: 2, max: 5))
        #expect(!JLSValidator.isLengthValid("", min: 1, max: 5))
    }

    @Test("String above maximum length is invalid")
    func lengthTooLong() {
        #expect(!JLSValidator.isLengthValid("abcdef", min: 1, max: 5))
    }
}
