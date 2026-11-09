import SwiftUI
import ImageIO
import UniformTypeIdentifiers

public struct ClipboardTabView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @State private var copiedEntryID: UUID?
    @State private var copyError: String?

    public init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(clipboardManager.entries.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer(minLength: 8)

                Button {
                    clipboardManager.clearHistory()
                    copiedEntryID = nil
                    copyError = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(IslandHoverButtonStyle(cornerRadius: 7))
                .disabled(clipboardManager.entries.isEmpty)
                .help("Clear History")
            }

            if clipboardManager.entries.isEmpty {
                emptyState(
                    icon: "doc.on.clipboard",
                    title: "Copy text, an image, or a file",
                    subtitle: "Up to 50 entries · Click an entry to copy"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(clipboardManager.entries) { entry in
                            ClipboardEntryRow(
                                entry: entry,
                                copied: copiedEntryID == entry.id,
                                onCopy: { copy(entry) },
                                onRemove: { clipboardManager.remove(entry) }
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let message = copyError ?? clipboardManager.captureError {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: copiedEntryID) {
            guard copiedEntryID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.4))
                copiedEntryID = nil
            } catch {
                // Новое копирование отменяет предыдущий индикатор.
            }
        }
    }

    private func copy(_ entry: ClipboardEntry) {
        if clipboardManager.copy(entry) {
            copiedEntryID = entry.id
            copyError = entry.isComplete ? nil : "Available formats copied. The source app did not provide all data."
        } else {
            copiedEntryID = nil
            copyError = "Could not restore this clipboard entry."
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(.cyan.opacity(0.7))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let copied: Bool
    let onCopy: () -> Void
    let onRemove: () -> Void
    @State private var thumbnail: NSImage?

    private var iconName: String {
        switch entry.kind {
        case .text: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .files: return entry.fileURLs.first?.hasDirectoryPath == true ? "folder.fill" : "doc.fill"
        case .url: return "link"
        case .data:
            let types = entry.typeNames.compactMap { UTType($0) }
            if types.contains(where: { $0.conforms(to: .pdf) }) { return "doc.richtext" }
            if types.contains(where: { $0.conforms(to: .audio) }) { return "waveform" }
            if types.contains(where: { $0.conforms(to: .movie) }) { return "film" }
            if types.contains(where: { $0.conforms(to: .archive) }) { return "archivebox" }
            return "shippingbox"
        }
    }

    private var detailText: String {
        let group = entry.itemCount > 1 && entry.kind != .files ? " · Items: \(entry.itemCount)" : ""
        let unavailable = entry.isComplete ? "" : " · Some data is unavailable"
        return entry.subtitle + group + unavailable
    }

    var body: some View {
        return HStack(spacing: 4) {
            Button(action: onCopy) {
                HStack(spacing: 9) {
                    preview

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(entry.kind == .files ? .middle : .tail)

                        Text(detailText)
                            .font(.system(size: 9))
                            .foregroundStyle(entry.isComplete ? Color.white.opacity(0.4) : Color.orange.opacity(0.8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if copied {
                        Text(entry.isComplete ? "Copied" : "Partial")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(entry.isComplete ? Color.green : Color.orange)
                    } else {
                        Text(entry.copiedAt, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.leading, 9)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.canRestore)
            .opacity(entry.canRestore ? 1 : 0.55)
            .help(entry.canRestore
                ? "Copy: \(String(entry.title.prefix(200)))\n\(entry.subtitle)"
                : "The source app did not provide data to copy.")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(IslandHoverButtonStyle(cornerRadius: 6))
            .help("Remove Entry")
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(copied ? 0.1 : 0.055)))
        .task(id: entry.id) {
            await loadPreview()
        }
    }

    private var preview: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(entry.isComplete ? Color.green : Color.orange)
                } else if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if entry.fileURLs.count > 1, !copied {
                Text("\(entry.fileURLs.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(.black.opacity(0.85)))
                    .offset(x: 3, y: 2)
            }
        }
    }

    @MainActor
    private func loadPreview() async {
        // ImageIO уменьшает изображение при декодировании, вместо загрузки всех пикселей.
        let imageData = entry.imageData
        let fileURL = entry.fileURLs.first
        let imageFileURL = fileURL.flatMap { url in
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? url : nil
        }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            let source: CGImageSource?
            if let imageData {
                source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions)
            } else if let imageFileURL {
                source = CGImageSourceCreateWithURL(imageFileURL as CFURL, sourceOptions)
            } else {
                return nil
            }
            guard let source else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard !Task.isCancelled else { return }
        if let image {
            thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } else if let fileURL {
            thumbnail = NSWorkspace.shared.icon(forFile: fileURL.path)
        }
    }
}
