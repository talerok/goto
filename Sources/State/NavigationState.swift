import Foundation

/// Manages the current directory, back/forward history stacks, and address bar path history.
@Observable
@MainActor
final class NavigationState {
    private(set) var currentDirectory: URL
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []

    /// Paths typed into the address bar, persisted across launches.
    var addressBarHistory: [String] {
        didSet { persistHistory() }
    }

    private static let historyKey = "addressBarHistory"
    private static let maxHistory = 100

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentDirectory.path(percentEncoded: false) != "/" }

    init(startingDirectory: URL? = nil) {
        let home = URL(filePath: NSHomeDirectory())
        self.currentDirectory = startingDirectory ?? home
        self.addressBarHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
    }

    /// Navigate to a new directory, pushing the current one onto the back stack.
    func navigate(to url: URL) {
        guard url != currentDirectory else { return }
        backStack.append(currentDirectory)
        forwardStack.removeAll()
        currentDirectory = url
    }

    /// Navigate to a path typed in the address bar. Also records it in address bar history.
    func navigateFromAddressBar(to url: URL) {
        navigate(to: url)

        let path = url.path(percentEncoded: false)
        addressBarHistory.removeAll { $0 == path }
        addressBarHistory.insert(path, at: 0)
        if addressBarHistory.count > Self.maxHistory {
            addressBarHistory = Array(addressBarHistory.prefix(Self.maxHistory))
        }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectory)
        currentDirectory = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectory)
        currentDirectory = next
    }

    func goUp() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent != currentDirectory else { return }
        navigate(to: parent)
    }

    private func persistHistory() {
        UserDefaults.standard.set(addressBarHistory, forKey: Self.historyKey)
    }
}
