/// A collection of mathematical utility functions.
public enum MathUtils {
    /// Clamps the given value to the specified range.
    ///
    /// - Parameters:
    ///   - value: The value to clamp.
    ///   - lower: The lower bound of the range.
    ///   - upper: The upper bound of the range.
    /// - Returns: The clamped value.
    public static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        Swift.min(Swift.max(value, lower), upper)
    }

    /// Computes the factorial of a non-negative integer.
    ///
    /// - Parameter n: A non-negative integer.
    /// - Returns: The factorial of `n`, or `nil` if `n` is negative.
    public static func factorial(_ n: Int) -> Int? {
        guard n >= 0 else { return nil }
        if n <= 1 { return 1 }
        return n * (factorial(n - 1) ?? 1)
    }

    /// Computes the greatest common divisor of two integers using the Euclidean algorithm.
    ///
    /// - Parameters:
    ///   - a: The first integer.
    ///   - b: The second integer.
    /// - Returns: The greatest common divisor.
    public static func gcd(_ a: Int, _ b: Int) -> Int {
        let a = abs(a)
        let b = abs(b)
        if b == 0 { return a }
        return gcd(b, a % b)
    }

    /// Checks whether the given integer is a prime number.
    ///
    /// - Parameter n: The integer to check.
    /// - Returns: `true` if `n` is prime, `false` otherwise.
    public static func isPrime(_ n: Int) -> Bool {
        guard n > 1 else { return false }
        if n <= 3 { return true }
        if n % 2 == 0 || n % 3 == 0 { return false }

        var i = 5
        while i * i <= n {
            if n % i == 0 || n % (i + 2) == 0 {
                return false
            }
            i += 6
        }
        return true
    }
}
