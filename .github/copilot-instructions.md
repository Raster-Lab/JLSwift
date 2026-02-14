# Copilot Instructions for JLSwift

## Project Overview

JLSwift is a Swift library built with Swift 6.2 and above. It provides core utilities including
validation, string manipulation, and mathematical operations.

## Swift Version

- **Minimum Swift version**: 6.2
- Use Swift 6.2+ features and concurrency model where appropriate.
- Follow the Swift 6.2 strict concurrency checking guidelines.

## Coding Standards

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Use `let` over `var` wherever possible.
- Prefer value types (`struct`, `enum`) over reference types (`class`) unless reference semantics are required.
- Use Swift's built-in error handling (`throws`, `Result`) instead of optional-based error handling.
- Mark types and methods with appropriate access control (`public`, `internal`, `private`).
- Use `Sendable` conformance for types shared across concurrency domains.

## Testing Requirements

- **Test code coverage must be greater than 95%.**
- All public APIs must have corresponding unit tests.
- Use `@Test` attribute (Swift Testing framework) for new tests.
- Tests should be placed in the `Tests/JLSwiftTests/` directory.
- Run tests with: `swift test`
- Generate coverage reports with: `swift test --enable-code-coverage`
- Test names should clearly describe the behavior being tested.
- Include edge cases, boundary conditions, and error paths in tests.

## Documentation Requirements

- When code changes are made, the following documents **must** be updated:
  - **README.md**: Update to reflect any new features, API changes, or usage instructions.
  - **MILESTONES.md**: Update to reflect progress on project milestones and goals.
- All public types and methods must have documentation comments using `///` syntax.
- Include usage examples in documentation comments where helpful.

## Project Structure

```
JLSwift/
├── Package.swift              # Swift Package Manager manifest (Swift 6.2+)
├── Sources/
│   └── JLSwift/               # Main library source code
├── Tests/
│   └── JLSwiftTests/          # Unit tests (>95% coverage required)
├── .github/
│   ├── copilot-instructions.md  # This file
│   └── workflows/
│       └── ci.yml             # CI pipeline with coverage enforcement
├── README.md                  # Project documentation
└── MILESTONES.md              # Project milestones and roadmap
```

## Build and Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run tests with code coverage
swift test --enable-code-coverage

# View coverage report JSON path (after running tests with coverage)
swift test --show-codecov-path
```

## CI/CD

- GitHub Actions CI runs on every push and pull request.
- The CI pipeline builds with Swift 6.2+ and enforces >95% test coverage.
- PRs that drop coverage below 95% will fail the CI check.

## Code Review Checklist

Before submitting or approving a PR, verify:

1. All tests pass (`swift test`).
2. Test coverage is above 95%.
3. README.md is updated if features or APIs changed.
4. MILESTONES.md is updated if milestone progress changed.
5. All public APIs have documentation comments.
6. Code follows Swift 6.2+ best practices and concurrency model.
