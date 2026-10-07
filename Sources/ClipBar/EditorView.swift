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

    init(store: ClipStore, item: ClipItem, paste: @escaping (ClipItem) -> Void, close: @escaping () -> Void) {
        self.store = store
        self.id = item.id
        self.paste = paste
        self.close = close
        _draft = State(initialValue: item.text)
    }

    private var item: ClipItem? { store.items.first { $0.id == id } }

    private var isText: Bool { [.text, .link, .color].contains(item?.kind) }
    private var dirty: Bool { isText && draft != item?.text }

    var body: some View {
        VStack(spacing: 0) {
            if let item {
                header(item)
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                footer(item)
            } else {
                ContentUnavailableView("This item was deleted", systemImage: "trash")
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(VisualEffect().ignoresSafeArea())
        .onExitCommand(perform: close)
        .task(id: message) {
            guard message != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                message = nil
            } catch {}
        }
    }

    // MARK: - Header

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(item))
                    .font(.system(size: 15, weight: .semibold))
                ItemMeta(item: item)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.kind == .image {
                Picker("Zoom", selection: $actualSize) {
                    Text("Fit").tag(false)
                    Text("Actual Size").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
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
        case .image: imageContent(item)
        case .files: filesContent(item.files ?? [])
        case .text, .link, .color:
            VStack(alignment: .leading, spacing: 12) {
                if let color = item.color { ColorDetails(color: color) }
                TextEditor(text: $draft)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .panelBackground()
            }
        }
    }

    private func imageContent(_ item: ClipItem) -> some View {
        VStack(spacing: 12) {
            Group {
                if let image {
                    if actualSize {
                        ScrollView([.horizontal, .vertical]) { Image(nsImage: image) }
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .panelBackground()
            .onTapGesture(count: 2) { actualSize.toggle() }

            recognizedText(item)
        }
        .task(id: item.image) {
            image = item.image.flatMap { NSImage(contentsOf: ImageStore.url($0)) }
        }
    }

    @ViewBuilder
    private func recognizedText(_ item: ClipItem) -> some View {
        if item.text.isEmpty {
            HStack {
                Label("Text inside the image can be copied after recognition", systemImage: "text.viewfinder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(recognizing ? "Recognizing…" : "Recognize Text") {
                    recognize(item)
                }
                .disabled(recognizing)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Text in image", systemImage: "text.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Text") {
                        Clipboard.write(item.text)
                        message = "Text copied"
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    Text(item.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
            .padding(12)
            .panelBackground()
        }
    }

    private func filesContent(_ paths: [String]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(paths, id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(nsImage: Icons.file(path))
                            .resizable()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 13))
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
                        IconButton(symbol: "magnifyingglass", help: "Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .panelBackground()
    }

    // MARK: - Footer

    private func footer(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            switch item.kind {
            case .text, .link, .color:
                Menu("Transform") {
                    ForEach(TextTransform.groups.indices, id: \.self) { index in
                        Section {
                            ForEach(TextTransform.groups[index]) { transform in
                                Button(transform.rawValue) { apply(transform) }
                            }
                        }
                    }
                }
                .fixedSize()
                if let url = item.url {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                }
            case .image:
                Button("Save As…") { saveImage(item) }
            case .files:
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting((item.files ?? []).map { URL(fileURLWithPath: $0) })
                }
            }

            Spacer()

            Text(message ?? stats(item))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.snappy, value: message)

            if dirty {
                Button("Revert") { draft = item.text }
            }
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
            Button("Copy") {
                commit()
                store.copy(self.item ?? item)
                message = "Copied"
            }
            Button("Paste") {
                commit()
                paste(self.item ?? item)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help("Paste into the previous app (⌘↩)")
            if isText {
                Button("Save") {
                    commit()
                    message = "Saved"
                }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
                .disabled(!dirty || !draft.contains { !$0.isWhitespace })
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func stats(_ item: ClipItem) -> String {
        switch item.kind {
        case .image:
            guard let rep = image?.representations.first else { return "" }
            return "\(rep.pixelsWide) × \(rep.pixelsHigh) px"
        case .files:
            return item.files?.count == 1 ? "1 item" : "\(item.files?.count ?? 0) items"
        default:
            let lines = draft.reduce(1) { $1.isNewline ? $0 + 1 : $0 }
            return "\(draft.count) characters · \(lines) \(lines == 1 ? "line" : "lines")"
        }
    }

    // MARK: - Actions

    private func commit() {
        guard dirty, draft.contains(where: { !$0.isWhitespace }) else { return }
        store.updateText(id, to: draft)
    }

    private func apply(_ transform: TextTransform) {
        if let result = transform.apply(draft) {
            draft = result
        } else {
            message = "Couldn't apply “\(transform.rawValue)” to this text"
        }
    }

    private func recognize(_ item: ClipItem) {
        guard let name = item.image else { return }
        recognizing = true
        Task {
            await store.recognizeText(inImage: name)
            recognizing = false
            if self.item?.text.isEmpty == true { message = "No text found in this image" }
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
            message = "Image saved"
        } catch {
            message = "Couldn't save the image"
        }
    }
}

private struct ColorDetails: View {
    let color: NSColor

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(width: 64, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                }
            Text(rgb)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var rgb: String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let channels = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        let rgb = channels.map(String.init).joined(separator: ", ")
        return c.alphaComponent < 1
            ? "rgba(\(rgb), \(String(format: "%.2f", c.alphaComponent)))"
            : "rgb(\(rgb))"
    }
}

private extension View {
    func panelBackground() -> some View {
        background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
            .clipShape(.rect(cornerRadius: 12))
    }
}

/// Frosted, behind-window background for regular windows.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
