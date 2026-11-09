import AppKit
import Combine
import UniformTypeIdentifiers

fileprivate struct ClipboardRepresentation: Equatable {
    let type: String
    let data: Data
}

fileprivate struct ClipboardSnapshotItem: Equatable {
    let representations: [ClipboardRepresentation]
    let unavailableTypes: [String]

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        representations.first { $0.type == type.rawValue }?.data
    }

    static func == (lhs: ClipboardSnapshotItem, rhs: ClipboardSnapshotItem) -> Bool {
        guard lhs.representations.count == rhs.representations.count,
              Set(lhs.unavailableTypes) == Set(rhs.unavailableTypes) else { return false }
        // Representation declaration order can differ for the same copy. Item order cannot.
        let left = Dictionary(uniqueKeysWithValues: lhs.representations.map { ($0.type, $0.data) })
        let right = Dictionary(uniqueKeysWithValues: rhs.representations.map { ($0.type, $0.data) })
        return left == right
    }
}

public struct ClipboardEntry: Identifiable, Equatable {
    public enum Kind: Equatable {
        case text, image, files, url, richText, data
    }

    public let id: UUID
    public let copiedAt: Date
    public let text: String
    public let title: String
    public let subtitle: String
    public let kind: Kind
    public let fileURLs: [URL]
    public let imageData: Data?
    public let typeNames: [String]
    public let unavailableTypeNames: [String]
    public let byteCount: Int
    public var itemCount: Int { snapshot.count }
    public var isComplete: Bool { unavailableTypeNames.isEmpty }
    public var canRestore: Bool { snapshot.contains { !$0.representations.isEmpty } }
    fileprivate let snapshot: [ClipboardSnapshotItem]

    fileprivate init(id: UUID = UUID(), copiedAt: Date = Date(), snapshot: [ClipboardSnapshotItem]) {
        self.id = id
        self.copiedAt = copiedAt
        self.snapshot = snapshot
        let representations = snapshot.flatMap(\.representations)
        byteCount = representations.reduce(0) { $0 + $1.data.count }
        var types: [String] = []
        for type in representations.map(\.type) + snapshot.flatMap(\.unavailableTypes) where !types.contains(type) {
            types.append(type)
        }
        typeNames = types
        unavailableTypeNames = Array(Set(snapshot.flatMap(\.unavailableTypes))).sorted()
        fileURLs = Self.fileURLs(in: snapshot)

        let plainText = snapshot.compactMap { item in
            item.data(for: .string).flatMap { String(data: $0, encoding: .utf8) }
        }.joined(separator: "\n")
        let richText = snapshot.compactMap { item -> String? in
            guard let data = item.data(for: .rtf), data.count <= 1_048_576 else { return nil }
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        }.joined(separator: "\n")
        // HTML is preserved as bytes without invoking an importer or loading external content.
        let link = snapshot.compactMap { $0.data(for: .URL) }.compactMap(Self.url(from:)).first
        text = !plainText.isEmpty ? plainText : (!richText.isEmpty ? richText : link?.absoluteString ?? "")
        let imageRepresentations = representations.filter { UTType($0.type)?.conforms(to: .image) == true }
        imageData = imageRepresentations.first { $0.type == NSPasteboard.PasteboardType.png.rawValue }?.data
            ?? imageRepresentations.first?.data

        let size = Int64(byteCount).formatted(.byteCount(style: .memory).locale(Locale(identifier: "en_US")))
        let displayTitle: String
        if !fileURLs.isEmpty {
            kind = .files
            displayTitle = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
            if fileURLs.count == 1, let first = fileURLs.first {
                // Inspect the extension only; large files and remote volumes are not read.
                subtitle = first.hasDirectoryPath ? "Folder"
                    : Self.englishTypeName(UTType(filenameExtension: first.pathExtension))
            } else {
                subtitle = "Files: \(fileURLs.count)"
            }
        } else if let image = imageRepresentations.first {
            kind = .image
            displayTitle = "Image"
            subtitle = "\(Self.englishTypeName(UTType(image.type))) · \(size)"
        } else if let link = link ?? Self.webURL(in: text) {
            kind = .url
            displayTitle = text.isEmpty ? link.absoluteString : text
            subtitle = "Link · \(link.host ?? link.scheme ?? "URL")"
        } else if types.contains(NSPasteboard.PasteboardType.rtf.rawValue)
                    || types.contains(NSPasteboard.PasteboardType.rtfd.rawValue)
                    || types.contains(NSPasteboard.PasteboardType.html.rawValue) {
            kind = .richText
            displayTitle = text.isEmpty ? "Rich Text" : text
            subtitle = "Rich Text · \(size)"
        } else if !text.isEmpty {
            kind = .text
            displayTitle = text
            subtitle = "Text · \(size)"
        } else {
            kind = .data
            displayTitle = representations.isEmpty ? "Data is not available yet"
                : types.compactMap { UTType($0) }.first.map(Self.englishTypeName) ?? "App Data"
            subtitle = representations.isEmpty ? "Save the file in the source app and copy it again"
                : "Formats: \(types.count) · \(size)"
        }
        title = String(displayTitle.prefix(300))
    }

    fileprivate func refreshed() -> ClipboardEntry {
        ClipboardEntry(id: id, snapshot: snapshot)
    }

    private static func englishTypeName(_ type: UTType?) -> String {
        guard let type else { return "File" }
        if type.conforms(to: .directory) { return "Folder" }
        if type.conforms(to: .pdf) { return "PDF document" }
        let format = type.preferredFilenameExtension?.uppercased()
        if type.conforms(to: .image) { return format.map { "\($0) image" } ?? "Image" }
        if type.conforms(to: .audio) { return format.map { "\($0) audio" } ?? "Audio" }
        if type.conforms(to: .movie) { return format.map { "\($0) video" } ?? "Video" }
        if type.conforms(to: .archive) { return format.map { "\($0) archive" } ?? "Archive" }
        return format.map { "\($0) file" } ?? "File"
    }

    private static func url(from data: Data) -> URL? {
        if let string = String(data: data, encoding: .utf8), let url = URL(string: string), url.scheme != nil {
            return url
        }
        if let string = try? PropertyListSerialization.propertyList(from: data, format: nil) as? String {
            guard let url = URL(string: string), url.scheme != nil else { return nil }
            return url
        }
        return nil
    }

    private static func webURL(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp", "mailto"].contains(scheme) else { return nil }
        return url
    }

    private static func fileURLs(in items: [ClipboardSnapshotItem]) -> [URL] {
        var urls: [URL] = []
        for item in items {
            if let data = item.data(for: .fileURL), let url = url(from: data), url.isFileURL {
                urls.append(url)
            }
            let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            if let data = item.data(for: legacy),
               let paths = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] {
                urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
            }
        }
        var unique: [URL] = []
        for url in urls where !unique.contains(url) { unique.append(url) }
        return unique
    }
}

/// Представления хранятся в памяти; файлы сохраняются как ссылки на оригиналы.
@MainActor
public final class ClipboardManager: ObservableObject {
    @Published public private(set) var entries: [ClipboardEntry] = []
    @Published public private(set) var captureError: String?

    private let pasteboard: NSPasteboard
    private let maxEntries: Int
    private let maxHistoryBytes: Int
    private let maxTextBytes: Int?
    private var lastChangeCount: Int = -1
    private var monitoringTimer: Timer?

    // https://nspasteboard.org/: эти маркеры запрещают сохранение истории содержимого.
    private static let ignoredTypes = Set([
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping", "Pasteboard generator type"
    ].map { NSPasteboard.PasteboardType($0) })
    private static let ownershipTypes = Set(["org.nspasteboard.source"].map { NSPasteboard.PasteboardType($0) })
    // A promise is a live source-process transfer, not the contents of an existing file.
    private static let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes + [
        "com.apple.pasteboard.promised-file-content-type", "com.apple.pasteboard.promised-file-url",
        "com.apple.NSFilePromiseItemMetaData", "NSFilesPromisePboardType"
    ])

    public init(pasteboard: NSPasteboard = .general,
                maxEntries: Int = 50,
                maxHistoryBytes: Int = 128 * 1024 * 1024,
                maxTextBytes: Int? = nil,
                startMonitoring: Bool = true) {
        self.pasteboard = pasteboard
        self.maxEntries = max(1, maxEntries)
        self.maxHistoryBytes = max(1, maxHistoryBytes)
        self.maxTextBytes = maxTextBytes.map { max(1, $0) }
        pollClipboard()
        if startMonitoring {
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pollClipboard() }
            }
        }
    }

    deinit { monitoringTimer?.invalidate() }

    public func pollClipboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        let items = pasteboard.pasteboardItems ?? []
        let allTypes = Set(pasteboard.types ?? []).union(items.flatMap(\.types))
        guard allTypes.isDisjoint(with: Self.ignoredTypes) else {
            lastChangeCount = changeCount
            captureError = nil
            return
        }

        func capture(types: [NSPasteboard.PasteboardType], read: (NSPasteboard.PasteboardType) -> Data?) -> ClipboardSnapshotItem {
            var representations: [ClipboardRepresentation] = []
            var unavailable: [String] = []
            for type in types where !Self.ownershipTypes.contains(type) {
                if Self.promiseTypes.contains(type.rawValue) {
                    unavailable.append(type.rawValue)
                } else if let data = read(type) {
                    representations.append(ClipboardRepresentation(type: type.rawValue, data: data))
                } else {
                    unavailable.append(type.rawValue)
                }
            }
            return ClipboardSnapshotItem(representations: representations, unavailableTypes: unavailable)
        }

        let snapshot: [ClipboardSnapshotItem]
        if !items.isEmpty {
            snapshot = items.map { item in capture(types: item.types, read: { item.data(forType: $0) }) }
        } else {
            // Legacy single-item producers may not expose pasteboardItems.
            snapshot = [capture(types: pasteboard.types ?? [], read: { pasteboard.data(forType: $0) })]
        }
        // Lazy providers may change the buffer while fulfilling a representation.
        guard pasteboard.changeCount == changeCount else { return }
        lastChangeCount = changeCount
        guard snapshot.contains(where: { !$0.representations.isEmpty || !$0.unavailableTypes.isEmpty }) else {
            captureError = nil
            return
        }
        let entry = ClipboardEntry(snapshot: snapshot)
        let onlyPlainText = entry.isComplete && snapshot.flatMap(\.representations).allSatisfy {
            $0.type == NSPasteboard.PasteboardType.string.rawValue
        }
        if onlyPlainText {
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  maxTextBytes.map({ entry.byteCount <= $0 }) ?? true else { captureError = nil; return }
        }
        captureError = entry.canRestore ? nil : "The source app did not provide data to restore this entry."
        record(entry)
    }

    @discardableResult
    public func copy(_ entry: ClipboardEntry) -> Bool {
        guard let current = entries.first(where: { $0.id == entry.id }), current.canRestore else {
            captureError = "This entry is not available to copy."
            return false
        }
        var requiresLegacyWrite = false
        let snapshots = current.snapshot.filter { !$0.representations.isEmpty }
        let items = snapshots.map { snapshot -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in snapshot.representations {
                if !item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type)) {
                    requiresLegacyWrite = true
                }
            }
            return item
        }
        guard !requiresLegacyWrite || snapshots.count == 1 else {
            captureError = "Could not restore one of the formats in this group."
            return false
        }
        // Associated NSPasteboardItems become stale. Every restore reconstructs fresh objects.
        pasteboard.clearContents()
        let copied: Bool
        if requiresLegacyWrite, let snapshot = snapshots.first {
            // A legacy single-item producer can declare non-UTI pasteboard names.
            // NSPasteboardItem accepts UTIs only; the original API preserves those old names.
            pasteboard.declareTypes(snapshot.representations.map { NSPasteboard.PasteboardType($0.type) }, owner: nil)
            var succeeded = true
            for representation in snapshot.representations {
                if !pasteboard.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type)) {
                    succeeded = false
                }
            }
            copied = succeeded
        } else {
            copied = pasteboard.writeObjects(items)
        }
        lastChangeCount = pasteboard.changeCount
        guard copied else { captureError = "Could not restore this clipboard entry."; return false }
        captureError = nil
        record(current.refreshed())
        return true
    }

    public func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    public func clearHistory() {
        entries.removeAll()
        captureError = nil
        lastChangeCount = pasteboard.changeCount
    }

    private func record(_ entry: ClipboardEntry) {
        let existing = entries.first { $0.snapshot == entry.snapshot }
        // Keep the newest source's type preference order while retaining its history identity.
        let stored = existing.map { ClipboardEntry(id: $0.id, copiedAt: entry.copiedAt, snapshot: entry.snapshot) } ?? entry
        entries.removeAll { $0.snapshot == stored.snapshot }
        entries.insert(stored, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        var bytes = entries.reduce(0) { $0 + $1.byteCount }
        // Keep the latest large image intact, evicting older entries first.
        while entries.count > 1 && bytes > maxHistoryBytes {
            bytes -= entries.removeLast().byteCount
        }
    }
}
