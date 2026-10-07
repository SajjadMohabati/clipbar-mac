import Foundation

/// Reports new screenshots (⇧⌘3 / ⇧⌘4 / ⇧⌘5) using Spotlight's screen-capture flag,
/// so it works wherever screenshots are saved and whatever they're named.
@MainActor
final class ScreenshotWatcher {
    private let query = NSMetadataQuery()
    private let onScreenshot: (URL) -> Void
    private var seen: Set<String> = []
    private var startDate = Date.now
    private var observers: [NSObjectProtocol] = []

    init(onScreenshot: @escaping (URL) -> Void) {
        self.onScreenshot = onScreenshot
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
    }

    func start() {
        guard !query.isStarted else { return }
        startDate = .now
        seen = []
        let center = NotificationCenter.default
        observers = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate].map { name in
            center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
        }
        query.start()
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func scan() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  seen.insert(path).inserted,
                  let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  created >= startDate else { continue }
            onScreenshot(URL(fileURLWithPath: path))
        }
    }
}
