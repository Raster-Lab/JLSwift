import Testing
@testable import JLSwift

@Suite("JLSMathUtils Tests")
struct JLSMathUtilsTests {
    // MARK: - clamp

    @Test("Value within range is unchanged")
    func clampWithinRange() {
        #expect(JLSMathUtils.clamp(5, lower: 1, upper: 10) == 5)
    }

    @Test("Value below range is clamped to lower bound")
    func clampBelowRange() {
        #expect(JLSMathUtils.clamp(-5, lower: 0, upper: 10) == 0)
    }

    @Test("Value above range is clamped to upper bound")
    func clampAboveRange() {
        #expect(JLSMathUtils.clamp(15, lower: 0, upper: 10) == 10)
    }

    @Test("Value at bounds is unchanged")
    func clampAtBounds() {
        #expect(JLSMathUtils.clamp(0, lower: 0, upper: 10) == 0)
        #expect(JLSMathUtils.clamp(10, lower: 0, upper: 10) == 10)
    }

    // MARK: - factorial

    @Test("Factorial of non-negative integers")
    func factorialValid() {
        #expect(JLSMathUtils.factorial(0) == 1)
        #expect(JLSMathUtils.factorial(1) == 1)
        #expect(JLSMathUtils.factorial(5) == 120)
        #expect(JLSMathUtils.factorial(3) == 6)
    }

    @Test("Factorial of negative number returns nil")
    func factorialNegative() {
        #expect(JLSMathUtils.factorial(-1) == nil)
        #expect(JLSMathUtils.factorial(-10) == nil)
    }

    // MARK: - gcd

    @Test("GCD of positive integers")
    func gcdPositive() {
        #expect(JLSMathUtils.gcd(12, 8) == 4)
        #expect(JLSMathUtils.gcd(7, 13) == 1)
        #expect(JLSMathUtils.gcd(100, 75) == 25)
    }

    @Test("GCD with zero")
    func gcdWithZero() {
        #expect(JLSMathUtils.gcd(5, 0) == 5)
        #expect(JLSMathUtils.gcd(0, 5) == 5)
        #expect(JLSMathUtils.gcd(0, 0) == 0)
    }

    @Test("GCD with negative numbers")
    func gcdNegative() {
        #expect(JLSMathUtils.gcd(-12, 8) == 4)
        #expect(JLSMathUtils.gcd(12, -8) == 4)
        #expect(JLSMathUtils.gcd(-12, -8) == 4)
    }

    // MARK: - isPrime

    @Test("Prime numbers are identified correctly")
    func primeNumbers() {
        #expect(JLSMathUtils.isPrime(2))
        #expect(JLSMathUtils.isPrime(3))
        #expect(JLSMathUtils.isPrime(5))
        #expect(JLSMathUtils.isPrime(7))
        #expect(JLSMathUtils.isPrime(11))
        #expect(JLSMathUtils.isPrime(13))
        #expect(JLSMathUtils.isPrime(29))
    }

    @Test("Non-prime numbers are identified correctly")
    func nonPrimeNumbers() {
        #expect(!JLSMathUtils.isPrime(0))
        #expect(!JLSMathUtils.isPrime(1))
        #expect(!JLSMathUtils.isPrime(4))
        #expect(!JLSMathUtils.isPrime(9))
        #expect(!JLSMathUtils.isPrime(15))
        #expect(!JLSMathUtils.isPrime(25))
    }

    @Test("Negative numbers are not prime")
    func negativePrime() {
        #expect(!JLSMathUtils.isPrime(-1))
        #expect(!JLSMathUtils.isPrime(-7))
    }
}
