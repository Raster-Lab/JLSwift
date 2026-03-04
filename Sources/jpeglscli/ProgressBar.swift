import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A simple, in-place terminal progress bar for long-running CLI operations.
///
/// Writes updates to standard error using a carriage-return (`\r`) to overwrite
/// the current line on every call to `update(completed:label:)`, giving an
/// animated non-scrolling display.  Output is suppressed automatically when
/// `quiet` is `true` or when standard error is not connected to a TTY (e.g.
/// when the output is piped to a file).
///
/// Usage:
/// ```swift
/// let bar = ProgressBar(total: 10, quiet: false)
/// for i in 0..<10 {
///     // … do work …
///     bar.update(completed: i + 1)
/// }
/// bar.finish()
/// ```
struct ProgressBar: Sendable {

    /// Total number of steps.
    let total: Int

    /// When `true`, all output is suppressed.
    let quiet: Bool

    /// Width of the filled/empty portion of the bar in characters.
    let barWidth: Int

    /// Whether the progress bar is active (not quiet and stderr is a TTY).
    let active: Bool

    // MARK: - Initialisation

    /// Create a new progress bar.
    ///
    /// - Parameters:
    ///   - total: Total number of steps to completion.
    ///   - quiet: When `true`, suppress all output.
    ///   - barWidth: Width of the `#`/` ` bar in characters (default: 30).
    init(total: Int, quiet: Bool, barWidth: Int = 30) {
        self.total    = total
        self.quiet    = quiet
        self.barWidth = barWidth
        self.active   = !quiet && isatty(STDERR_FILENO) != 0
    }

    // MARK: - Output

    /// Write a progress update to standard error, overwriting the current line.
    ///
    /// - Parameters:
    ///   - completed: Number of steps completed so far.
    ///   - label: Optional short label appended after the counter (e.g. a filename).
    func update(completed: Int, label: String = "") {
        guard active else { return }
        let line = buildLine(completed: completed, label: label)
        FileHandle.standardError.write(Data(("\r" + line).utf8))
    }

    /// Clear the progress bar line from standard error.
    ///
    /// Call this after the final `update` so the terminal is left clean for
    /// subsequent output.
    func finish() {
        guard active else { return }
        // ANSI erase-to-end-of-line (\e[K) clears leftover characters after \r.
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }

    // MARK: - Line Builder

    /// Build the rendered progress line string (without the leading `\r`).
    ///
    /// This method is `internal` so that unit tests can verify the rendered
    /// output without needing a TTY.
    ///
    /// - Parameters:
    ///   - completed: Number of steps completed so far.
    ///   - label: Optional label appended after the counter.
    /// - Returns: A single-line string such as `[########              ] 40% (4/10)`.
    func buildLine(completed: Int, label: String = "") -> String {
        let clamped  = max(0, min(completed, total))
        let fraction = total > 0 ? Double(clamped) / Double(total) : 0.0
        let filled   = Int(fraction * Double(barWidth))
        let empty    = barWidth - filled
        let bar      = String(repeating: "#", count: filled) + String(repeating: " ", count: empty)
        let percent  = Int(fraction * 100)
        let counter  = "(\(clamped)/\(total))"
        if label.isEmpty {
            return "[\(bar)] \(percent)% \(counter)"
        } else {
            return "[\(bar)] \(percent)% \(counter) \(label)"
        }
    }
}
