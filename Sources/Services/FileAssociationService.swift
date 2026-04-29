import AppKit

/// Manages user-configured file extension → application associations.
/// Stored in UserDefaults as [String: String] mapping extension (lowercase) or "folder" to bundle identifier.
enum FileAssociationService {

    private static let defaultsKey = "fileAssociations"

    // MARK: - Read

    /// Get all stored associations.
    static func allAssociations() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// Get the configured app bundle ID for a file extension (lowercase) or "folder", or nil.
    static func defaultApp(forKey key: String) -> String? {
        allAssociations()[key.lowercased()]
    }

    // MARK: - Write

    /// Set the default app for a key (extension or "folder").
    static func setDefaultApp(bundleID: String, forKey key: String) {
        var associations = allAssociations()
        associations[key.lowercased()] = bundleID
        UserDefaults.standard.set(associations, forKey: defaultsKey)
    }

    /// Remove an association entirely.
    static func removeAssociation(forKey key: String) {
        var associations = allAssociations()
        associations.removeValue(forKey: key.lowercased())
        UserDefaults.standard.set(associations, forKey: defaultsKey)
    }

    // MARK: - App Resolution

    /// Resolve a bundle identifier to an application URL, or nil if not installed.
    static func appURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Get the display name of an app from its URL.
    static func appDisplayName(at url: URL) -> String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// Get recommended apps for a given file URL using the system API.
    @MainActor
    static func recommendedApps(for fileURL: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
    }

    /// Open a file with a specific application URL.
    @MainActor
    static func open(_ fileURL: URL, withAppAt appURL: URL) {
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
