import Foundation

/// Reports new screenshots (⇧⌘3 / ⇧⌘4 / ⇧⌘5) by watching the folder macOS saves them to.
/// Opening the folder is also what makes macOS ask for Desktop access the first time.
@MainActor
final class ScreenshotWatcher {
    private let onScreenshot: (URL) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var locationCheck: Timer?
    private var folder: URL?
    private var seen: Set<String> = []
    private var startDate = Date.now

    init(onScreenshot: @escaping (URL) -> Void) {
        self.onScreenshot = onScreenshot
    }

    /// The location chosen in the ⇧⌘5 Options menu, or the Desktop.
    private static var screenshotFolder: URL {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = (custom.map { NSString(string: $0).expandingTildeInPath }) ?? ""
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.desktopDirectory
    }

    func start() {
        guard locationCheck == nil else { return }
        watch(Self.screenshotFolder)
        // The save location can change at any time in ⇧⌘5 → Options; follow it.
        locationCheck = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.screenshotFolder != self.folder else { return }
                self.watch(Self.screenshotFolder)
            }
        }
    }

    func stop() {
        locationCheck?.invalidate()
        locationCheck = nil
        source?.cancel()
        source = nil
        folder = nil
    }

    private func watch(_ folder: URL) {
        source?.cancel()
        source = nil
        self.folder = folder
        let descriptor = open(folder.path, O_EVTONLY)
        // Not readable (yet): forget it so the next location check tries again.
        guard descriptor >= 0 else { return self.folder = nil }
        startDate = .now
        seen = Set(files(in: folder).map(\.path))

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func scan() {
        guard let folder else { return }
        for url in files(in: folder) where !seen.contains(url.path) && Self.isNewScreenshot(url, since: startDate) {
            seen.insert(url.path)
            onScreenshot(url)
        }
    }

    private func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        )) ?? []
    }

    /// macOS tags screenshots with this extended attribute, whatever their name or language.
    private static func isNewScreenshot(_ url: URL, since date: Date) -> Bool {
        guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
              created >= date else { return false }
        return getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }
}
