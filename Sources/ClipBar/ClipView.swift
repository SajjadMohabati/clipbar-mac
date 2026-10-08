import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipView: View {
    /// Transparent room around the card for its shadow.
    static let margin: CGFloat = 24
    static let size = CGSize(width: 400 + margin * 2, height: 540 + margin * 2)

    @ObservedObject var store: ClipStore
    @ObservedObject private var settings = Settings.shared
    let paste: (ClipItem, _ direct: Bool) -> Void
    let edit: (ClipItem) -> Void
    let openSettings: () -> Void

    @FocusState private var searchFocused: Bool
    @Namespace private var chips
    @State private var confirmingClear = false
    @State private var dragging: UUID?
    @State private var dropTarget: DropTarget?
    @State private var canPaste = Clipboard.canPaste
    @State private var addingSaved = false

    private var showingSaved: Bool { store.mode == .saved }

    var body: some View {
        VStack(spacing: 10) {
            header
            searchField
            if !showingSaved { filterBar }
            list
            if settings.autoPaste && !canPaste { accessBanner }
            footer
        }
        .padding(12)
        .frame(width: Self.size.width - Self.margin * 2, height: Self.size.height - Self.margin * 2)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .padding(Self.margin)
        .onChange(of: store.focusRequest, initial: true) {
            searchFocused = true
            confirmingClear = false
            canPaste = Clipboard.canPaste
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ModeSwitch(mode: $store.mode)
            if store.paused {
                Button("Paused") { store.paused = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.15)))
                    .help("Not recording new copies. Click to resume.")
            }
            Spacer()
            if showingSaved {
                IconButton(symbol: "plus", help: "Add a saved item") { addingSaved = true }
                    .popover(isPresented: $addingSaved, arrowEdge: .bottom) {
                        SavedItemForm { title, value, locked in
                            store.addSaved(title: title, text: value, locked: locked)
                            addingSaved = false
                        }
                    }
            } else {
                clearButtons
            }
            IconButton(symbol: "gearshape", help: "Settings (⌘,)", action: openSettings)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .task(id: confirmingClear) {
            guard confirmingClear else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.snappy(duration: 0.2)) { confirmingClear = false }
        }
    }

    @ViewBuilder
    private var clearButtons: some View {
            if confirmingClear {
                Button("Clear unpinned") {
                    store.clear(includingPinned: false)
                    confirmingClear = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.red))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            IconButton(symbol: "trash", help: "Clear history", tint: .red) {
                withAnimation(.snappy(duration: 0.2)) { confirmingClear.toggle() }
            }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(showingSaved ? "Search saved items" : "Search clipboard history", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var filterBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 2) {
                ForEach(ClipStore.Filter.allCases) { filter in
                    let active = store.filter == filter
                    Button {
                        withAnimation(.smooth(duration: 0.4)) { store.filter = filter }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? Color.primary : Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .contentShape(Capsule())
                            .chipGlass(active, id: filter, in: chips)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if store.visible.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(store.visible.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 2) {
                                if let title = sectionTitle(at: index) {
                                    Text(title)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .textCase(.uppercase)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.top, index == 0 ? 0 : 6)
                                }
                                row(item, index: index)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: store.focusRequest, initial: true) {
                    proxy.scrollTo(store.visible.first?.id, anchor: .top)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
            .animation(.snappy(duration: 0.25), value: store.visible.map(\.id))
            .task(id: dropTarget) {
                // dropExited isn't always delivered when a drag is cancelled.
                guard dropTarget != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { dropTarget = nil }
            }
        }
    }

    private func sectionTitle(at index: Int) -> String? {
        let items = store.visible
        guard !showingSaved, store.filter == .all, items.first?.pinned == true else { return nil }
        if index == 0 { return "Pinned" }
        return items[index - 1].pinned && !items[index].pinned ? "Recent" : nil
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        ClipRow(
            item: item,
            shortcut: index < 9 ? index + 1 : nil,
            selected: store.selection == item.id,
            saved: showingSaved,
            dropEdge: dropTarget?.id == item.id ? dropTarget?.edge : nil,
            onTap: { paste(item, true) },
            onPin: { store.togglePin(item) },
            onSave: { store.save(item) },
            onEdit: { edit(item) },
            onDelete: { store.remove(item) }
        )
        .onDrag {
            dragging = item.id
            return item.itemProvider
        }
        .onDrop(
            of: [.clipbarItem],
            delegate: RowDropDelegate(target: item.id, dragging: $dragging, dropTarget: $dropTarget) { id, after in
                store.move(id, nextTo: item.id, after: after)
            }
        )
        .contextMenu { menu(for: item) }
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button(settings.autoPaste ? "Paste" : "Copy and Close") { paste(item, true) }
        Button("Copy") { store.copyUnlocking(item) }
        if item.kind == .image, !item.text.isEmpty {
            Button("Copy Text from Image") { Clipboard.write(item.text) }
        }
        if let url = item.url {
            Button("Open Link") { NSWorkspace.shared.open(url) }
        }
        if let files = item.files {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(files.map { URL(fileURLWithPath: $0) })
            }
        }
        Divider()
        if showingSaved {
            Button("Edit…") { edit(item) }
            if !item.isLocked {
                Button("Move to History") { store.unsave(item) }
            }
        } else {
            Button("Move to Saved") { store.save(item) }
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("View and Edit…") { edit(item) }
            Button("Move to Top") { store.moveToTop(item) }
        }
        Divider()
        Button("Delete", role: .destructive) { store.remove(item) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if showingSaved && store.query.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No saved items")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Keep things you paste again and again,\nlike a card number or student ID.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Add Item", systemImage: "plus") { addingSaved = true }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            historyEmptyState
        }
    }

    private var historyEmptyState: some View {
        let searching = !store.query.isEmpty
        let empty = store.filter.empty
        return VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : empty.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? "No matches for “\(store.query)”" : empty.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if store.items.isEmpty && !showingSaved {
                Text("Copy something and it will show up here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Allow ClipBar in Accessibility to paste into apps. Until then items are only copied.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Allow…", action: Clipboard.requestPastePermission)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
        .task {
            // Pick up the permission as soon as it's granted in System Settings.
            while !Task.isCancelled && !canPaste {
                try? await Task.sleep(for: .seconds(1))
                canPaste = Clipboard.canPaste
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if let toast = store.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text(countText)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .animation(.snappy(duration: 0.25), value: store.toast)

            Spacer()

            if let item = store.selectedItem {
                Button { paste(item, true) } label: {
                    HStack(spacing: 6) {
                        Text(settings.autoPaste ? "Paste" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                        KeyCap(key: "↩")
                    }
                    .padding(.trailing, -6)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            ShortcutsButton()
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }

    private var countText: String {
        let total = showingSaved ? store.saved.count : store.items.count
        let shown = store.visible.count
        if shown != total { return "\(shown) of \(total)" }
        return total == 1 ? "1 item" : "\(total) items"
    }
}

/// A keyboard key, drawn like the key caps in Apple's menus.
struct KeyCap: View {
    enum Size { case regular, large }

    let key: String
    var size = Size.regular

    var body: some View {
        let height: CGFloat = size == .large ? 24 : 18
        Text(key)
            .font(.system(size: size == .large ? 12 : 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, size == .large ? 7 : 4)
            .frame(minWidth: height, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .shadow(color: .black.opacity(0.15), radius: 0, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: height * 0.28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
    }
}

/// Keyboard icon that reveals every panel shortcut in a popover.
private struct ShortcutsButton: View {
    @State private var showing = false
    @State private var hover = false

    private let shortcuts: [([String], String)] = [
        (["↩"], "Paste selected item"),
        (["⌥", "↩"], "Copy without pasting"),
        (["⌘", "1–9"], "Paste item 1–9"),
        (["↑", "↓"], "Move selection"),
        (["⇥"], "Next filter"),
        (["⌘", "["], "History"),
        (["⌘", "]"], "Saved items"),
        (["⌘", "S"], "Move to Saved"),
        (["⌘", "P"], "Pin or unpin"),
        (["⌘", "E"], "View and edit"),
        (["⌘", "⌫"], "Delete"),
        (["⌘", ","], "Settings"),
        (["esc"], "Clear search / close"),
    ]

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover || showing ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background(Color.primary.opacity(hover || showing ? 0.08 : 0), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Keyboard shortcuts")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                ForEach(shortcuts, id: \.1) { keys, title in
                    GridRow {
                        HStack(spacing: 3) {
                            ForEach(keys, id: \.self) { KeyCap(key: $0) }
                        }
                        .gridColumnAlignment(.trailing)
                        Text(title)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Row

struct ClipRow: View {
    static let height: CGFloat = 46

    let item: ClipItem
    let shortcut: Int?
    let selected: Bool
    var saved = false
    let dropEdge: VerticalEdge?
    let onTap: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: item)
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.preview)
                        .font(.system(size: 11, design: item.isLocked ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(item.preview)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    ItemMeta(item: item)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if hover {
                HStack(spacing: 0) {
                    if !saved {
                        IconButton(symbol: item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Unpin" : "Pin", action: onPin)
                        IconButton(symbol: "bookmark", help: "Move to Saved (⌘S)", action: onSave)
                    }
                    IconButton(symbol: "square.and.pencil", help: "View and edit", action: onEdit)
                    IconButton(symbol: "trash", help: "Delete", tint: .red, action: onDelete)
                }
                .transition(.opacity)
            } else if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1)
                }
        }
        .overlay(alignment: dropEdge == .top ? .top : .bottom) {
            if dropEdge != nil {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                    .shadow(color: .accentColor.opacity(0.5), radius: 4)
                    .offset(y: dropEdge == .top ? -2 : 2)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture(perform: onTap)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
        .animation(.snappy(duration: 0.15), value: selected)
        .animation(.snappy(duration: 0.15), value: dropEdge)
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.2) }
        if hover || dropEdge != nil { return Color.primary.opacity(0.06) }
        return .clear
    }
}

struct ItemIcon: View {
    let item: ClipItem
    var size: CGFloat = 30

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 4, y: -4)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if item.isLocked {
            symbol("lock.fill", .orange)
        } else {
            kindContent
        }
    }

    @ViewBuilder
    private var kindContent: some View {
        switch item.kind {
        case .image:
            if let name = item.image, let thumbnail = ImageStore.thumbnail(name) {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                symbol("photo", .purple)
            }
        case .color:
            Color(nsColor: item.color ?? .clear)
        case .files:
            Image(nsImage: Icons.file(item.files?.first ?? "/"))
                .resizable()
                .scaledToFit()
        case .link:
            symbol("link", .blue)
        case .text:
            symbol("text.alignleft", .gray)
        }
    }

    private func symbol(_ name: String, _ tint: Color) -> some View {
        ZStack {
            tint.opacity(0.15)
            Image(systemName: name)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

/// "Safari · 2 min ago · 3×"
struct ItemMeta: View {
    let item: ClipItem

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        HStack(spacing: 4) {
            if let app = Icons.app(item.source) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 12, height: 12)
                Text(app.name)
                Text("·")
            }
            Text(Self.formatter.localizedString(for: item.date, relativeTo: .now))
            if item.uses > 0 {
                Text("·")
                Text("\(item.uses)×")
            }
        }
        .lineLimit(1)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? (tint ?? .primary) : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.snappy(duration: 0.15), value: hover)
    }
}

// MARK: - Drag and drop

extension UTType {
    static let clipbarItem = UTType(exportedAs: "local.clipbar.item")
}

extension ClipItem {
    /// Exposes the real content to other apps, plus a private type for reordering inside ClipBar.
    var itemProvider: NSItemProvider {
        let provider: NSItemProvider = switch kind {
        case .image: image.flatMap { NSItemProvider(contentsOf: ImageStore.url($0)) } ?? NSItemProvider()
        case .files: files?.first.flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
        default: NSItemProvider(object: text as NSString)
        }
        let id = Data(self.id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.clipbarItem.identifier, visibility: .ownProcess) {
            $0(id, nil)
            return nil
        }
        return provider
    }
}

struct DropTarget: Equatable {
    let id: UUID
    let edge: VerticalEdge
}

private struct RowDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    @Binding var dropTarget: DropTarget?
    let move: (UUID, _ after: Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && dragging != target && info.hasItemsConforming(to: [.clipbarItem])
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.id == target { dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            dropTarget = nil
        }
        guard let dragging, validateDrop(info: info) else { return false }
        move(dragging, info.location.y > ClipRow.height / 2)
        return true
    }

    private func update(_ info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTarget = DropTarget(id: target, edge: info.location.y < ClipRow.height / 2 ? .top : .bottom)
    }
}

// MARK: - Saved items

/// History | Saved switch at the top of the panel.
private struct ModeSwitch: View {
    @Binding var mode: ClipStore.Mode
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            segment(.history, title: "History", symbol: "clock")
            segment(.saved, title: "Saved", symbol: "bookmark.fill")
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: .capsule)
    }

    private func segment(_ value: ClipStore.Mode, title: String, symbol: String) -> some View {
        let active = mode == value
        return Button {
            withAnimation(.snappy(duration: 0.25)) { mode = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Color.primary : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    if active {
                        Capsule()
                            .fill(Color.primary.opacity(0.13))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "mode", in: selection)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(value == .history ? "Clipboard history (⌘[)" : "Saved items (⌘])")
    }
}

/// Small form for adding something to Saved.
private struct SavedItemForm: View {
    let onAdd: (_ title: String, _ value: String, _ locked: Bool) -> Void

    @State private var title = ""
    @State private var value = ""
    @State private var locked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New Saved Item", systemImage: "bookmark.fill")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                TextField("Title, e.g. Card number", text: $title)
                TextField("Value to paste", text: $value, axis: .vertical)
                    .lineLimit(2...6)
            }
            .textFieldStyle(.roundedBorder)
            Toggle(isOn: $locked) {
                Label("Lock with Touch ID", systemImage: "lock.fill")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("The value is kept in the Keychain and needs Touch ID or your password to use.")
            HStack {
                Spacer()
                Button("Add") { onAdd(title, value, locked) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!value.contains { !$0.isWhitespace })
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

private extension View {
    /// The selected filter wears the glass; the container morphs it from chip to chip.
    @ViewBuilder
    func chipGlass(_ active: Bool, id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if active {
            glassEffect(.regular.tint(.accentColor.opacity(0.18)).interactive(), in: .capsule)
                .glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
