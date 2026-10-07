import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var store: ClipStore
    let id: UUID
    let paste: (ClipItem) -> Void
    let close: () -> Void

    @State private var draft: String
    @State private var image: NSImage?
    @State private var actualSize = false
    @State private var recognizing = false
    @State private var message: String?
    @State private var savedTitle: String
    @State private var locked: Bool
    /// What's stored right now, to tell whether there are unsaved edits.
    @State private var baseline: (text: String, title: String, locked: Bool)

    init(store: ClipStore, item: ClipItem, paste: @escaping (ClipItem) -> Void, close: @escaping () -> Void) {
        self.store = store
        self.id = item.id
        self.paste = paste
        self.close = close
        _draft = State(initialValue: item.text)
        _savedTitle = State(initialValue: item.title ?? "")
        _locked = State(initialValue: item.isLocked)
        _baseline = State(initialValue: (item.text, item.title ?? "", item.isLocked))
    }

    private var item: ClipItem? { store.item(with: id) }
    private var isText: Bool { [.text, .link, .color].contains(item?.kind) }
    private var isSaved: Bool { item.map(store.isSaved) ?? false }

    private var dirty: Bool {
        guard isText else { return false }
        return draft != baseline.text
            || (isSaved && (savedTitle != baseline.title || locked != baseline.locked))
    }

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        content(item)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        inspector(item)
                            .frame(width: 270)
                    }
                    bottomBar
                }
                .navigationTitle(title(item))
                .toolbar { toolbar(item) }
            } else {
                ContentUnavailableView("This item was deleted", systemImage: "trash")
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .overlay(alignment: .bottom) { toast }
        .onExitCommand(perform: close)
        .task(id: message) {
            guard message != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.8))
                withAnimation { message = nil }
            } catch {}
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ item: ClipItem) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isText {
                Menu {
                    ForEach(TextTransform.groups.indices, id: \.self) { index in
                        Section {
                            ForEach(TextTransform.groups[index]) { transform in
                                Button(transform.rawValue) { apply(transform) }
                            }
                        }
                    }
                } label: {
                    Label("Transform", systemImage: "wand.and.stars")
                }
                .help("Transform text")
            }
            if isSaved {
                if !item.isLocked {
                    Button { store.unsave(item) } label: {
                        Label("Move to History", systemImage: "bookmark.slash")
                    }
                    .help("Move to History")
                }
            } else {
                Button { store.togglePin(item) } label: {
                    Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
                }
                .help(item.pinned ? "Unpin" : "Pin")
                Button { store.save(item) } label: {
                    Label("Move to Saved", systemImage: "bookmark")
                }
                .help("Move to Saved")
            }
            Button {
                store.copy(current(item))
                flash("Copied to clipboard")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy (⇧⌘C)")
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(role: .destructive) {
                close()
                store.remove(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                paste(current(item))
            } label: {
                Label("Paste", systemImage: "arrow.turn.down.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Paste into the previous app (⌘↩)")
        }
    }

    private func title(_ item: ClipItem) -> String {
        switch item.kind {
        case .text: "Text"
        case .link: "Link"
        case .color: "Color"
        case .image: "Image"
        case .files: item.files?.count == 1 ? "File" : "\(item.files?.count ?? 0) Files"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text, .link, .color:
            TextEditor(text: $draft)
                .font(.system(size: 14))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color(nsColor: .textBackgroundColor))
        case .image:
            imageContent(item)
        case .files:
            filesContent(item.files ?? [])
        }
    }

    private func imageContent(_ item: ClipItem) -> some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let image {
                if actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).padding(24)
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        .padding(28)
                }
            } else {
                ProgressView()
            }
        }
        .onTapGesture(count: 2) { withAnimation(.snappy) { actualSize.toggle() } }
        .overlay(alignment: .bottom) {
            Picker("Zoom", selection: $actualSize.animation(.snappy)) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").tag(false)
                Image(systemName: "1.magnifyingglass").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Fit / actual size (double-click the image)")
            .padding(14)
        }
        .task(id: item.image) {
            image = item.image.flatMap { NSImage(contentsOf: ImageStore.url($0)) }
        }
    }

    private func filesContent(_ paths: [String]) -> some View {
        List(paths, id: \.self) { path in
            HStack(spacing: 12) {
                Image(nsImage: Icons.file(path))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !FileManager.default.fileExists(atPath: path) {
                    Text("Missing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                IconButton(symbol: "arrow.up.forward.app", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Inspector

    private func inspector(_ item: ClipItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isSaved {
                    InspectorSection("Saved Item") {
                        TextField("Title, e.g. Card number", text: $savedTitle)
                            .textFieldStyle(.roundedBorder)
                        Toggle(isOn: $locked) {
                            Label("Lock with Touch ID", systemImage: "lock.fill")
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        Text(locked
                             ? "Kept in the Keychain. Pasting, copying or opening it asks for Touch ID or your password."
                             : "Lock it to hide the value and protect it with Touch ID.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let color = item.color, isText {
                    ColorInspector(color: color, copy: copyValue)
                }

                InspectorSection("Details") {
                    InspectorRow("Type", value: title(item))
                    if let app = Icons.app(item.source) {
                        InspectorRow("Copied from") {
                            HStack(spacing: 5) {
                                Image(nsImage: app.icon).resizable().frame(width: 14, height: 14)
                                Text(app.name)
                            }
                        }
                    }
                    InspectorRow("Copied", value: item.date.formatted(date: .abbreviated, time: .shortened))
                    InspectorRow("Used", value: item.uses == 1 ? "Once" : "\(item.uses) times")
                    ForEach(stats(item), id: \.0) { InspectorRow($0.0, value: $0.1) }
                }

                if let url = item.url {
                    InspectorSection("Link") {
                        InspectorRow("Host", value: url.host() ?? url.absoluteString)
                        Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
                            .frame(maxWidth: .infinity)
                    }
                }

                switch item.kind {
                case .image: imageInspector(item)
                case .files:
                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting((item.files ?? []).map { URL(fileURLWithPath: $0) })
                    }
                    .frame(maxWidth: .infinity)
                default:
                    EmptyView()
                }
            }
            .padding(16)
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private func imageInspector(_ item: ClipItem) -> some View {
        InspectorSection("Text in Image") {
            if item.text.isEmpty {
                Text(recognizing ? "Looking for text…" : "No text recognized yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(recognizing ? "Recognizing…" : "Recognize Text", systemImage: "text.viewfinder") {
                    recognize(item)
                }
                .disabled(recognizing)
                .frame(maxWidth: .infinity)
            } else {
                Text(item.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy Text", systemImage: "doc.on.doc") { copyValue(item.text) }
                    .frame(maxWidth: .infinity)
            }
        }
        Button("Save Image…", systemImage: "square.and.arrow.down") { saveImage(item) }
            .frame(maxWidth: .infinity)
    }

    private func stats(_ item: ClipItem) -> [(String, String)] {
        switch item.kind {
        case .image:
            guard let name = item.image else { return [] }
            var rows: [(String, String)] = []
            if let rep = image?.representations.first {
                rows.append(("Dimensions", "\(rep.pixelsWide) × \(rep.pixelsHigh)"))
            }
            if let size = try? ImageStore.url(name).resourceValues(forKeys: [.fileSizeKey]).fileSize {
                rows.append(("File size", Int64(size).formatted(.byteCount(style: .file))))
            }
            return rows
        case .files:
            return [("Items", "\(item.files?.count ?? 0)")]
        default:
            let lines = draft.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
            var rows = [("Characters", draft.count.formatted()), ("Lines", lines.formatted())]
            if draft.utf8.count < 200_000 {
                rows.insert(("Words", draft.split(whereSeparator: { $0.isWhitespace }).count.formatted()), at: 1)
            }
            return rows
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private var canSave: Bool { dirty && draft.contains { !$0.isWhitespace } }

    private func save() {
        guard canSave else { return }
        if isSaved {
            store.updateSaved(id, title: savedTitle, text: draft, locked: locked)
        } else {
            store.updateText(id, to: draft)
        }
        baseline = (draft, savedTitle, locked)
    }

    /// The item as shown in the editor, including unsaved text, for copy and paste.
    private func current(_ item: ClipItem) -> ClipItem {
        var shown = self.item ?? item
        if isText {
            shown.text = draft
            shown.secret = locked ? true : nil
        }
        return shown
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if dirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.orange, .secondary)
                    .imageScale(.small)
            } else if isText {
                Text("Edit the text, then press Save.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if dirty {
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Save") {
                    save()
                    close()
                }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSave)
                .help("Save and close (⌘S)")
            } else {
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func flash(_ text: String) {
        withAnimation(.snappy) { message = text }
    }

    private func copyValue(_ text: String) {
        Clipboard.write(text)
        flash("Copied “\(text.prefix(40))”")
    }

    private func apply(_ transform: TextTransform) {
        if let result = transform.apply(draft) {
            draft = result
        } else {
            flash("Couldn't apply “\(transform.rawValue)”")
        }
    }

    private func recognize(_ item: ClipItem) {
        guard let name = item.image else { return }
        recognizing = true
        Task {
            await store.recognizeText(inImage: name)
            recognizing = false
            if self.item?.text.isEmpty == true { flash("No text found in this image") }
        }
    }

    private func saveImage(_ item: ClipItem) {
        guard let name = item.image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Clipboard Image.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: ImageStore.url(name), to: destination)
            flash("Image saved")
        } catch {
            flash("Couldn't save the image")
        }
    }
}

// MARK: - Inspector building blocks

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 9) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

private struct InspectorRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value.multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
    }
}

private extension InspectorRow where Value == Text {
    init(_ label: String, value: String) {
        self.init(label) { Text(value) }
    }
}

private struct ColorInspector: View {
    let color: NSColor
    let copy: (String) -> Void

    var body: some View {
        InspectorSection("Color") {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                }
            ForEach(formats, id: \.0) { name, value in
                InspectorRow(name) {
                    Button { copy(value) } label: {
                        HStack(spacing: 5) {
                            Text(value).font(.system(size: 12, design: .monospaced))
                            Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(name)")
                }
            }
        }
    }

    private var formats: [(String, String)] {
        let c = color.usingColorSpace(.sRGB) ?? color
        let (r, g, b, a) = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        let byte = { (v: CGFloat) in Int((v * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b)) + (a < 1 ? String(format: "%02X", byte(a)) : "")

        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let s = maxV == minV ? 0 : (maxV - l) / min(l, 1 - l)
        let hsl = "hsl(\(Int((c.hueComponent * 360).rounded())), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        let rgb = a < 1
            ? "rgba(\(byte(r)), \(byte(g)), \(byte(b)), \(String(format: "%.2f", a)))"
            : "rgb(\(byte(r)), \(byte(g)), \(byte(b)))"
        return [("HEX", hex), ("RGB", rgb), ("HSL", hsl)]
    }
}
