import SwiftUI
import ImageIO
import UniformTypeIdentifiers

public struct ClipboardTabView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @State private var copiedEntryID: UUID?
    @State private var copyError: String?

    private let clipboardAccent = Color(red: 0.46, green: 0.64, blue: 1)

    public init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [clipboardAccent.opacity(0.95), .purple.opacity(0.82)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: clipboardAccent.opacity(0.28), radius: 7, x: 0, y: 2)

                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text("\(clipboardManager.entries.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(.white.opacity(0.075)))
                    .overlay(Capsule().stroke(.white.opacity(0.07), lineWidth: 0.5))

                Spacer(minLength: 8)

                Button {
                    clipboardManager.clearHistory()
                    copiedEntryID = nil
                    copyError = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(ClipboardActionButtonStyle(accent: .pink, cornerRadius: 7))
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
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(message)
                        .lineLimit(1)
                }
                .font(.system(size: 9))
                .foregroundStyle(.orange.opacity(0.92))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(.orange.opacity(0.09)))
                .overlay(Capsule().stroke(.orange.opacity(0.16), lineWidth: 0.5))
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
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .cyan.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [clipboardAccent.opacity(0.25), .purple.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(Circle().stroke(.white.opacity(0.09), lineWidth: 0.7))
                .shadow(color: clipboardAccent.opacity(0.18), radius: 10, x: 0, y: 3)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.065), clipboardAccent.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.075), lineWidth: 0.6)
        )
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let copied: Bool
    let onCopy: () -> Void
    let onRemove: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        switch entry.kind {
        case .text: return Color(red: 0.47, green: 0.68, blue: 1)
        case .richText: return Color(red: 0.77, green: 0.52, blue: 1)
        case .image: return Color(red: 1, green: 0.53, blue: 0.68)
        case .files: return Color(red: 0.39, green: 0.76, blue: 1)
        case .url: return Color(red: 0.35, green: 0.88, blue: 0.76)
        case .data: return Color(red: 1, green: 0.68, blue: 0.34)
        }
    }

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
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(entry.kind == .files ? .middle : .tail)

                        Text(detailText)
                            .font(.system(size: 9))
                            .foregroundStyle(entry.isComplete ? Color.white.opacity(0.5) : Color.orange.opacity(0.86))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if copied {
                        Text(entry.isComplete ? "Copied" : "Partial")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(entry.isComplete ? Color.green.opacity(0.95) : Color.orange.opacity(0.95))
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(
                                Capsule()
                                    .fill((entry.isComplete ? Color.green : Color.orange).opacity(0.11))
                            )
                    } else {
                        Text(entry.copiedAt, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.43))
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
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(ClipboardActionButtonStyle(accent: .pink, cornerRadius: 6))
            .help("Remove Entry")
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(copied ? 0.17 : (isHovered ? 0.13 : 0.085)),
                            .white.opacity(isHovered ? 0.075 : 0.045)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(copied ? 0.34 : 0.18), .white.opacity(0.055)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.6
                )
        )
        .shadow(color: accent.opacity(copied ? 0.13 : 0), radius: 8, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: copied)
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.94), accent.opacity(0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.24), accent.opacity(0.075)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 0.6)
            )

            if entry.fileURLs.count > 1, !copied {
                Text("\(entry.fileURLs.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(accent.opacity(0.92)))
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
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

private struct ClipboardActionButtonStyle: ButtonStyle {
    let accent: Color
    let cornerRadius: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accent.opacity(configuration.isPressed ? 0.2 : (isHovered ? 0.105 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(isHovered ? 0.075 : 0), lineWidth: 0.5)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.92 : 1))
            .opacity(isEnabled ? 1 : 0.32)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
