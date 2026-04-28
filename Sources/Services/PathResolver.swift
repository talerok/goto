import Foundation

/// Resolves user-typed path strings into absolute file URLs.
///
/// Handles: `~`, `~user`, `$VAR`, `${VAR}`, relative paths, whitespace trimming.
enum PathResolver {

    /// Resolve a user-entered path string to an absolute URL.
    /// - Parameters:
    ///   - input: The raw path string from the address bar.
    ///   - currentDirectory: The current working directory for relative path resolution.
    /// - Returns: An absolute file URL, or `nil` if the input is empty after trimming.
    static func resolve(_ input: String, relativeTo currentDirectory: URL) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var path = expandEnvironmentVariables(in: trimmed)
        path = expandTilde(in: path)

        if !path.hasPrefix("/") {
            let base = currentDirectory.path(percentEncoded: false)
            path = (base as NSString).appendingPathComponent(path)
        }

        // Normalize: resolve `.`, `..`, double slashes
        path = (path as NSString).standardizingPath

        return URL(filePath: path, directoryHint: .checkFileSystem)
    }

    /// Expand `~` and `~username` at the start of a path.
    private static func expandTilde(in path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        return (path as NSString).expandingTildeInPath
    }

    private static let bracedPattern = try! NSRegularExpression(pattern: #"\$\{(\w+)\}"#)
    private static let simplePattern = try! NSRegularExpression(pattern: #"\$(\w+)"#)

    /// Expand `$VAR` and `${VAR}` patterns using the current process environment.
    private static func expandEnvironmentVariables(in path: String) -> String {
        var result = path
        let environment = ProcessInfo.processInfo.environment

        // Handle ${VAR} form
        for match in bracedPattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(fullRange, with: environment[String(result[nameRange])] ?? "")
        }

        // Handle $VAR form
        for match in simplePattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(fullRange, with: environment[String(result[nameRange])] ?? "")
        }

        return result
    }
}
