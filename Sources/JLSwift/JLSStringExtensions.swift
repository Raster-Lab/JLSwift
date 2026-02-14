import Foundation

extension String {
    /// Returns a new string with leading and trailing whitespace and newlines removed.
    ///
    /// Example:
    /// ```swift
    /// let result = "  hello  ".trimmed()
    /// // result == "hello"
    /// ```
    public func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a new string with the first letter capitalized and the rest unchanged.
    ///
    /// Example:
    /// ```swift
    /// let result = "hello world".capitalizedFirst()
    /// // result == "Hello world"
    /// ```
    public func capitalizedFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Checks whether the string contains only alphanumeric characters.
    ///
    /// - Returns: `true` if every character is a letter or digit, `false` otherwise.
    ///   Returns `false` for empty strings.
    public var isAlphanumeric: Bool {
        !isEmpty && allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Returns the string repeated the given number of times.
    ///
    /// - Parameter count: The number of times to repeat the string. Must be non-negative.
    /// - Returns: The repeated string, or an empty string if count is zero or negative.
    public func repeated(_ count: Int) -> String {
        guard count > 0 else { return "" }
        return String(repeating: self, count: count)
    }

    /// Returns the number of words in the string.
    ///
    /// Words are separated by whitespace and newline characters.
    ///
    /// - Returns: The number of words.
    public var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
