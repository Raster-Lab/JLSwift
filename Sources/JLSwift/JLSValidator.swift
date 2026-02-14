import Foundation

/// A collection of common validation utilities.
public enum JLSValidator {
    /// Checks whether the given string is a valid email address.
    ///
    /// The validation checks for:
    /// - Non-empty local part and domain
    /// - Exactly one `@` symbol
    /// - At least one `.` in the domain part
    ///
    /// - Parameter email: The string to validate.
    /// - Returns: `true` if the string is a valid email format, `false` otherwise.
    public static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]

        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard domain.contains(".") else { return false }

        let domainParts = domain.split(separator: ".", omittingEmptySubsequences: false)
        for part in domainParts {
            if part.isEmpty { return false }
        }

        return true
    }

    /// Checks whether the given string is non-empty and not just whitespace.
    ///
    /// - Parameter value: The string to validate.
    /// - Returns: `true` if the string contains non-whitespace characters.
    public static func isNonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checks whether the given string length falls within the specified range.
    ///
    /// - Parameters:
    ///   - value: The string to validate.
    ///   - min: The minimum allowed length (inclusive).
    ///   - max: The maximum allowed length (inclusive).
    /// - Returns: `true` if the string length is within the range.
    public static func isLengthValid(_ value: String, min: Int, max: Int) -> Bool {
        value.count >= min && value.count <= max
    }
}
