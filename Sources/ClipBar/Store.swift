import AppKit

struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case text, link, color, image, files }

    var id = UUID()
    /// The copied text, the text recognized inside an image, or the copied file paths.
    var text = ""
    /// File name of the stored image inside `Paths.images`.
    var image: String?
    var files: [String]?
    /// Bundle identifier of the app the content was copied from.
    var source: String?
    var date = Date()
    var pinned = false
    var uses = 0
    /// Inline image data written by ClipBar 1.x; moved into `Paths.images` on load.
    var imageData: Data?

    var kind: Kind {
        if image != nil { return .image }
        if files != nil { return .files }
        if color != nil { return .color }
        if url != nil { return .link }
        return .text
    }

    var preview: String {
        switch kind {
        case .image: text.isEmpty ? "Image" : "Image — " + Self.collapsed(text)
        case .files: (files ?? []).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        default: Self.collapsed(text)
        }
    }

    var url: URL? {
        guard image == nil, files == nil, text.utf8.count < 2048 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else { return nil }
        return (["http", "https"].contains(scheme) && url.host != nil) || scheme == "mailto" ? url : nil
    }

    /// Parses `#rgb`, `#rrggbb` and `#rrggbbaa` hex colors.
    var color: NSColor? {
        guard image == nil, files == nil, text.utf8.count <= 12 else { return nil }
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit),
              let value = UInt64(hex, radix: 16) else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt64) -> CGFloat { CGFloat(rgba >> shift & 0xFF) / 255 }
        return NSColor(srgbRed: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    func hasSameContent(as other: ClipItem) -> Bool {
        if let image { return image == other.image }
        if let files { return files == other.files }
        return other.image == nil && other.files == nil && text == other.text
    }

    private static func collapsed(_ text: String) -> String {
        text.prefix(160).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum Paths {
    static let support = directory(URL.applicationSupportDirectory.appending(path: "ClipBar"))
    static let images = directory(support.appending(path: "Images"))
    static let history = support.appending(path: "history.json")

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class ClipStore: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", pinned = "Pinned", text = "Text", links = "Links", images = "Images", files = "Files"

        var id: Self { self }

        func matches(_ item: ClipItem) -> Bool {
            switch self {
            case .all: true
            case .pinned: item.pinned
            case .text: item.kind == .text || item.kind == .color
            case .links: item.kind == .link
            case .images: item.kind == .image
            case .files: item.kind == .files
            }
        }

        var empty: (title: String, symbol: String) {
            switch self {
            case .all: ("Nothing copied yet", "clipboard")
            case .pinned: ("No pinned items", "pin")
            case .text: ("No text", "text.alignleft")
            case .links: ("No links", "link")
            case .images: ("No images", "photo")
            case .files: ("No files", "doc")
            }
        }
    }

    @Published private(set) var items: [ClipItem] = [] { didSet { refresh() } }
    @Published var query = "" { didSet { refresh() } }
    @Published var filter = Filter.all { didSet { refresh() } }
    @Published private(set) var visible: [ClipItem] = []
    @Published var selection: UUID?
    @Published var paused = false
    @Published private(set) var toast: String?
    @Published private(set) var focusRequest = 0

    private static let maxTextBytes = 4_000_000
    private static let maxImageBytes = 50_000_000

    private var lastChangeCount = 0
    private let io = DispatchQueue(label: "clipbar.io", qos: .utility)
    private var settings: Settings { .shared }

    var selectedItem: ClipItem? { visible.first { $0.id == selection } }

    // MARK: - Capture

    func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !paused, let types = pasteboard.types,
              !Clipboard.shouldIgnore(types, skipConcealed: settings.skipSensitive) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let urls = Clipboard.fileURLs(pasteboard) {
            let paths = urls.map(\.path)
            insert(ClipItem(text: paths.joined(separator: "\n"), files: paths, source: source))
        } else if let text = pasteboard.string(forType: .string) {
            guard text.contains(where: { !$0.isWhitespace }), text.utf8.count <= Self.maxTextBytes,
                  !(settings.skipSensitive && Clipboard.looksSensitive(text)) else { return }
            insert(ClipItem(text: text, source: source))
        } else if let image = Clipboard.image(pasteboard), image.data.count <= Self.maxImageBytes {
            captureImage(image.data, isPNG: image.isPNG, source: source)
        }
    }

    private func captureImage(_ data: Data, isPNG: Bool, source: String?) {
        Task {
            // Stored on the io queue so it can't race with deletions of the same file.
            let name: String? = await withCheckedContinuation { continuation in
                io.async { continuation.resume(returning: ImageStore.store(data, isPNG: isPNG)) }
            }
            guard let name else { return }
            insert(ClipItem(image: name, source: source))
            if items.first(where: { $0.image == name })?.text.isEmpty == true {
                await recognizeText(inImage: name)
            }
        }
    }

    func recognizeText(inImage name: String) async {
        let text = await ImageStore.recognizeText(name)
        guard !text.isEmpty else { return }
        mutate { list in
            for index in list.indices where list[index].image == name { list[index].text = text }
        }
    }

    private func insert(_ new: ClipItem) {
        mutate { list in
            var item = new
            if let index = list.firstIndex(where: { $0.hasSameContent(as: new) }) {
                let old = list.remove(at: index)
                item.id = old.id
                item.pinned = old.pinned
                item.uses = old.uses
                if item.text.isEmpty { item.text = old.text }
            }
            list.insert(item, at: Self.insertionIndex(for: item, in: list))
        }
    }

    // MARK: - Actions

    func copy(_ item: ClipItem) {
        Clipboard.write(item)
        lastChangeCount = NSPasteboard.general.changeCount
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
            list[index].uses += 1
            list[index].date = .now
        }
    }

    func togglePin(_ item: ClipItem) {
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
            var moved = list.remove(at: index)
            moved.pinned.toggle()
            list.insert(moved, at: Self.insertionIndex(for: moved, in: list))
        }
    }

    func moveToTop(_ item: ClipItem) {
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == item.id }) else { return }
            let moved = list.remove(at: index)
            list.insert(moved, at: Self.insertionIndex(for: moved, in: list))
        }
        selection = item.id
    }

    /// Moves `id` next to `target`, adopting the target's pinned state.
    func move(_ id: UUID, nextTo target: UUID, after: Bool) {
        mutate { list in
            guard id != target, let from = list.firstIndex(where: { $0.id == id }) else { return }
            var moved = list.remove(at: from)
            guard let to = list.firstIndex(where: { $0.id == target }) else {
                list.insert(moved, at: from)
                return
            }
            moved.pinned = list[to].pinned
            list.insert(moved, at: after ? to + 1 : to)
        }
        selection = id
    }

    func updateText(_ id: UUID, to text: String) {
        mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index].text = text
        }
    }

    func remove(_ item: ClipItem) {
        if selection == item.id, let index = visible.firstIndex(where: { $0.id == item.id }) {
            let neighbor = visible.indices.contains(index + 1) ? index + 1 : index - 1
            selection = visible.indices.contains(neighbor) ? visible[neighbor].id : nil
        }
        mutate { $0.removeAll { $0.id == item.id } }
    }

    func clear(includingPinned: Bool) {
        mutate { $0.removeAll { includingPinned || !$0.pinned } }
    }

    func applyLimits() {
        mutate { _ in }
    }

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if toast == message { toast = nil }
        }
    }

    // MARK: - Panel state

    func prepareForDisplay() {
        query = ""
        filter = .all
        applyLimits()
        selection = visible.first?.id
        focusRequest += 1
    }

    func moveSelection(by delta: Int) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == selection }.map { $0 + delta } ?? 0
        selection = visible[min(max(index, 0), visible.count - 1)].id
    }

    func cycleFilter(by delta: Int) {
        let all = Filter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + delta + all.count) % all.count]
    }

    private func refresh() {
        let terms = query.split(whereSeparator: \.isWhitespace)
        visible = items.filter { item in
            filter.matches(item) && terms.allSatisfy { item.text.localizedStandardContains($0) }
        }
        if !visible.contains(where: { $0.id == selection }) { selection = visible.first?.id }
    }

    // MARK: - Persistence

    /// Applies a change, enforces the cleanup limits, and saves.
    private func mutate(_ change: (inout [ClipItem]) -> Void) {
        var list = items
        change(&list)
        list = pruned(list)
        guard list != items else { return }
        let removedImages = Set(items.compactMap(\.image)).subtracting(list.compactMap(\.image))
        items = list
        save(removingImages: removedImages)
    }

    private func pruned(_ list: [ClipItem]) -> [ClipItem] {
        let cutoff = Date.now.addingTimeInterval(-Double(settings.keepDays) * 86_400)
        let keepPinned = !settings.cleanPinned
        let maxItems = settings.maxItems
        var kept = 0
        return list.filter { item in
            if item.pinned && keepPinned { return true }
            guard item.date >= cutoff else { return false }
            kept += 1
            return kept <= maxItems
        }
    }

    private static func insertionIndex(for item: ClipItem, in list: [ClipItem]) -> Int {
        item.pinned ? 0 : list.prefix(while: \.pinned).count
    }

    func load() {
        guard let data = try? Data(contentsOf: Paths.history) else { return }
        guard var list = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            // Keep the unreadable file around instead of overwriting it on the next save.
            try? FileManager.default.moveItem(at: Paths.history, to: Paths.support.appending(path: "history.corrupt.json"))
            return
        }
        var migrated = false
        for index in list.indices {
            guard let legacy = list[index].imageData else { continue }
            list[index].image = ImageStore.store(legacy, isPNG: legacy.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            list[index].imageData = nil
            migrated = true
        }
        list.removeAll { $0.image == nil && $0.files == nil && $0.text.isEmpty }
        items = list.filter(\.pinned) + list.filter { !$0.pinned }

        let referenced = Set(items.compactMap(\.image))
        io.async { ImageStore.purge(keeping: referenced) }
        if migrated { save() }
    }

    private func save(removingImages removed: Set<String> = []) {
        let snapshot = items
        io.async {
            ImageStore.delete(removed)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Paths.history, options: .atomic)
        }
    }

    /// Blocks until pending writes are on disk.
    func flush() {
        io.sync {}
    }
}
