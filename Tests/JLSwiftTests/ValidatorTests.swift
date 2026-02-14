import Testing
import Foundation
@testable import JLSwift

@Suite("Validator Tests")
struct ValidatorTests {
    // MARK: - isValidEmail

    @Test("Valid email addresses are accepted")
    func validEmails() {
        #expect(Validator.isValidEmail("user@example.com"))
        #expect(Validator.isValidEmail("test.user@domain.co"))
        #expect(Validator.isValidEmail("a@b.c"))
    }

    @Test("Email without @ is rejected")
    func emailWithoutAt() {
        #expect(!Validator.isValidEmail("userexample.com"))
    }

    @Test("Email with multiple @ is rejected")
    func emailWithMultipleAt() {
        #expect(!Validator.isValidEmail("user@@example.com"))
        #expect(!Validator.isValidEmail("u@s@example.com"))
    }

    @Test("Email with empty local part is rejected")
    func emailEmptyLocal() {
        #expect(!Validator.isValidEmail("@example.com"))
    }

    @Test("Email with empty domain is rejected")
    func emailEmptyDomain() {
        #expect(!Validator.isValidEmail("user@"))
    }

    @Test("Email without dot in domain is rejected")
    func emailNoDotInDomain() {
        #expect(!Validator.isValidEmail("user@example"))
    }

    @Test("Email with empty domain segment is rejected")
    func emailEmptyDomainSegment() {
        #expect(!Validator.isValidEmail("user@.com"))
        #expect(!Validator.isValidEmail("user@example."))
    }

    @Test("Empty string is not a valid email")
    func emailEmpty() {
        #expect(!Validator.isValidEmail(""))
    }

    // MARK: - isNonEmpty

    @Test("Non-empty strings return true")
    func nonEmptyStrings() {
        #expect(Validator.isNonEmpty("hello"))
        #expect(Validator.isNonEmpty("a"))
    }

    @Test("Empty and whitespace-only strings return false")
    func emptyStrings() {
        #expect(!Validator.isNonEmpty(""))
        #expect(!Validator.isNonEmpty("   "))
        #expect(!Validator.isNonEmpty("\n\t"))
    }

    // MARK: - isLengthValid

    @Test("String within length range is valid")
    func lengthValid() {
        #expect(Validator.isLengthValid("abc", min: 1, max: 5))
        #expect(Validator.isLengthValid("ab", min: 2, max: 2))
    }

    @Test("String below minimum length is invalid")
    func lengthTooShort() {
        #expect(!Validator.isLengthValid("a", min: 2, max: 5))
        #expect(!Validator.isLengthValid("", min: 1, max: 5))
    }

    @Test("String above maximum length is invalid")
    func lengthTooLong() {
        #expect(!Validator.isLengthValid("abcdef", min: 1, max: 5))
    }
}
