import Testing
@testable import JLSwift

@Suite("MathUtils Tests")
struct MathUtilsTests {
    // MARK: - clamp

    @Test("Value within range is unchanged")
    func clampWithinRange() {
        #expect(MathUtils.clamp(5, lower: 1, upper: 10) == 5)
    }

    @Test("Value below range is clamped to lower bound")
    func clampBelowRange() {
        #expect(MathUtils.clamp(-5, lower: 0, upper: 10) == 0)
    }

    @Test("Value above range is clamped to upper bound")
    func clampAboveRange() {
        #expect(MathUtils.clamp(15, lower: 0, upper: 10) == 10)
    }

    @Test("Value at bounds is unchanged")
    func clampAtBounds() {
        #expect(MathUtils.clamp(0, lower: 0, upper: 10) == 0)
        #expect(MathUtils.clamp(10, lower: 0, upper: 10) == 10)
    }

    // MARK: - factorial

    @Test("Factorial of non-negative integers")
    func factorialValid() {
        #expect(MathUtils.factorial(0) == 1)
        #expect(MathUtils.factorial(1) == 1)
        #expect(MathUtils.factorial(5) == 120)
        #expect(MathUtils.factorial(3) == 6)
    }

    @Test("Factorial of negative number returns nil")
    func factorialNegative() {
        #expect(MathUtils.factorial(-1) == nil)
        #expect(MathUtils.factorial(-10) == nil)
    }

    // MARK: - gcd

    @Test("GCD of positive integers")
    func gcdPositive() {
        #expect(MathUtils.gcd(12, 8) == 4)
        #expect(MathUtils.gcd(7, 13) == 1)
        #expect(MathUtils.gcd(100, 75) == 25)
    }

    @Test("GCD with zero")
    func gcdWithZero() {
        #expect(MathUtils.gcd(5, 0) == 5)
        #expect(MathUtils.gcd(0, 5) == 5)
        #expect(MathUtils.gcd(0, 0) == 0)
    }

    @Test("GCD with negative numbers")
    func gcdNegative() {
        #expect(MathUtils.gcd(-12, 8) == 4)
        #expect(MathUtils.gcd(12, -8) == 4)
        #expect(MathUtils.gcd(-12, -8) == 4)
    }

    // MARK: - isPrime

    @Test("Prime numbers are identified correctly")
    func primeNumbers() {
        #expect(MathUtils.isPrime(2))
        #expect(MathUtils.isPrime(3))
        #expect(MathUtils.isPrime(5))
        #expect(MathUtils.isPrime(7))
        #expect(MathUtils.isPrime(11))
        #expect(MathUtils.isPrime(13))
        #expect(MathUtils.isPrime(29))
    }

    @Test("Non-prime numbers are identified correctly")
    func nonPrimeNumbers() {
        #expect(!MathUtils.isPrime(0))
        #expect(!MathUtils.isPrime(1))
        #expect(!MathUtils.isPrime(4))
        #expect(!MathUtils.isPrime(9))
        #expect(!MathUtils.isPrime(15))
        #expect(!MathUtils.isPrime(25))
    }

    @Test("Negative numbers are not prime")
    func negativePrime() {
        #expect(!MathUtils.isPrime(-1))
        #expect(!MathUtils.isPrime(-7))
    }
}
