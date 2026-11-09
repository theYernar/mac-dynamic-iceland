import AppKit
import XCTest
@testable import DynamicIsland

final class ClipboardManagerTests: XCTestCase {
    @MainActor
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("IcelandClipboardTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @MainActor
    private func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
    }

    @MainActor
    private func writeItems(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects(items))
    }

    @MainActor
    private func item(_ representations: [NSPasteboard.PasteboardType: Data]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in representations {
            XCTAssertTrue(item.setData(data, forType: type))
        }
        return item
    }

    @MainActor
    private func pngData() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 8, bitsPerPixel: 32
        ))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for offset in stride(from: 0, to: 16, by: 4) {
            pixels[offset] = 255
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 255
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IcelandClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testCapturesCurrentTextAndOnlyProcessesChangedPasteboard() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        write("First", to: pasteboard)
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        XCTAssertEqual(manager.entries.map(\.text), ["First"])
        let first = manager.entries[0]

        manager.pollClipboard()
        XCTAssertEqual(manager.entries, [first], "An unchanged clipboard must not refresh the entry timestamp")
        write("Second", to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.map(\.text), ["Second", "First"])
    }

    @MainActor
    func testRepeatedTextMovesExistingEntryToFrontWithoutDuplicates() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        write("First", to: pasteboard)
        manager.pollClipboard()
        let firstID = manager.entries[0].id
        write("Second", to: pasteboard)
        manager.pollClipboard()
        write("First", to: pasteboard)
        manager.pollClipboard()

        XCTAssertEqual(manager.entries.map(\.text), ["First", "Second"])
        XCTAssertEqual(manager.entries[0].id, firstID)
    }

    @MainActor
    func testHistoryEvictsOldestEntriesAtConfiguredLimit() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, maxEntries: 2, startMonitoring: false)
        for text in ["First", "Second", "Third"] {
            write(text, to: pasteboard)
            manager.pollClipboard()
        }
        XCTAssertEqual(manager.entries.map(\.text), ["Third", "Second"])
    }

    @MainActor
    func testCopyRestoresExactWhitespaceAndPromotesEntry() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let originalText = "  \u{441}\u{442}\u{440}\u{43E}\u{43A}\u{430}\n\t\u{432}\u{442}\u{43E}\u{440}\u{430}\u{44F} \u{441}\u{442}\u{440}\u{43E}\u{43A}\u{430} 🙂  \n"
        write(originalText, to: pasteboard)
        manager.pollClipboard()
        let original = try XCTUnwrap(manager.entries.first)
        write("Later", to: pasteboard)
        manager.pollClipboard()

        XCTAssertTrue(manager.copy(original))
        XCTAssertEqual(pasteboard.string(forType: .string), originalText)
        XCTAssertEqual(manager.entries.map(\.text), [originalText, "Later"])
        XCTAssertEqual(manager.entries.first?.id, original.id)
        let afterCopy = manager.entries
        manager.pollClipboard()
        XCTAssertEqual(manager.entries, afterCopy, "Copying from history must not be imported a second time")
    }

    @MainActor
    func testClearHistoryPreservesSystemClipboardAndDoesNotImportItAgain() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        write("Keep in system clipboard", to: pasteboard)
        manager.pollClipboard()
        let changeCount = pasteboard.changeCount

        manager.clearHistory()
        manager.pollClipboard()
        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep in system clipboard")

        write("New copy", to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.map(\.text), ["New copy"])
    }

    @MainActor
    func testRemovedEntryCannotBeCopiedOrReappearWithoutNewCopy() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        write("Remove", to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        manager.remove(entry)
        manager.pollClipboard()

        XCTAssertTrue(manager.entries.isEmpty)
        XCTAssertFalse(manager.copy(entry))
        XCTAssertEqual(pasteboard.string(forType: .string), "Remove")
    }

    @MainActor
    func testIgnoresEmptyClipboardAndWhitespaceOnlyText() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        for text in ["", " \n\t "] {
            write(text, to: pasteboard)
            manager.pollClipboard()
        }
        pasteboard.clearContents()
        manager.pollClipboard()
        XCTAssertTrue(manager.entries.isEmpty)
    }

    @MainActor
    func testConfidentialTransientAndGeneratedTextAreNotRecorded() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            write("Excluded text", to: pasteboard)
            XCTAssertTrue(pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(marker)))
            manager.pollClipboard()
        }
        XCTAssertTrue(manager.entries.isEmpty)
        write("Normal copy", to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.map(\.text), ["Normal copy"])
    }

    @MainActor
    func testHistoryByteBudgetEvictsOldSnapshotsButKeepsNewestOversizedEntry() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, maxHistoryBytes: 10, startMonitoring: false)
        let type = NSPasteboard.PasteboardType("com.example.iceland.binary")
        writeItems([item([type: Data(repeating: 1, count: 6)])], to: pasteboard)
        manager.pollClipboard()
        let oldID = try XCTUnwrap(manager.entries.first?.id)
        writeItems([item([type: Data(repeating: 2, count: 6)])], to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertNotEqual(manager.entries.first?.id, oldID)

        let largeData = Data(repeating: 3, count: 32)
        writeItems([item([type: largeData])], to: pasteboard)
        manager.pollClipboard()
        let largeEntry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertTrue(manager.copy(largeEntry), "Large contents must not be silently dropped or truncated")
        XCTAssertEqual(pasteboard.data(forType: type), largeData)
    }

    @MainActor
    func testHistoryIsNotSharedWithAnotherManagerInstance() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        write("History exists only in memory", to: pasteboard)
        manager.pollClipboard()
        pasteboard.clearContents()

        let secondManager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertTrue(secondManager.entries.isEmpty)
    }

    @MainActor
    func testImageWithoutTextIsShownAndRestoredAsImageData() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let png = try pngData()
        writeItems([item([.png: png])], to: pasteboard)
        manager.pollClipboard()
        let imageEntry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(imageEntry.kind, .image)
        XCTAssertEqual(imageEntry.imageData, png)
        XCTAssertFalse(imageEntry.title.isEmpty)

        write("Replace image", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(imageEntry))
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        XCTAssertNil(pasteboard.string(forType: .string), "Restoring an image must not replace it with a text preview")
    }

    @MainActor
    func testSingleFileUsesNameAndRestoresOriginalFileURL() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("\u{414}\u{43E}\u{43A}\u{443}\u{43C}\u{435}\u{43D}\u{442}.pdf")
        try Data("%PDF-1.7\n".utf8).write(to: file)
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let fileURLData = Data(file.absoluteString.utf8)
        let filePreview = try pngData()
        writeItems([item([.fileURL: fileURLData, .png: filePreview])], to: pasteboard)
        manager.pollClipboard()

        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .files)
        XCTAssertEqual(entry.fileURLs.map(\.path), [file.path])
        XCTAssertTrue(entry.title.contains(file.lastPathComponent))
        write("Replace file", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        XCTAssertEqual(pasteboard.data(forType: .fileURL), fileURLData)
        XCTAssertEqual(pasteboard.data(forType: .png), filePreview)
    }

    @MainActor
    func testMultipleFilesAndFolderAreKeptTogetherInOriginalOrder() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let nestedFolder = folder.appendingPathComponent("\u{41F}\u{430}\u{43F}\u{43A}\u{430}", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        let urls = ["clip.mp4", "song.mp3", "archive.zip"].map { folder.appendingPathComponent($0) } + [nestedFolder]
        for file in urls.dropLast() { try Data().write(to: file) }
        let customType = NSPasteboard.PasteboardType("com.example.iceland.file-metadata")
        let originalItems = urls.enumerated().map { index, url in
            item([.fileURL: Data(url.absoluteString.utf8), customType: Data([UInt8(index)])])
        }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        writeItems(originalItems, to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .files)
        XCTAssertEqual(entry.fileURLs.map(\.path), urls.map(\.path))
        XCTAssertEqual(manager.entries.count, 1, "One multi-file copy is one history entry")

        write("Replace files", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, urls.count)
        for (index, restoredItem) in restored.enumerated() {
            XCTAssertEqual(restoredItem.string(forType: .fileURL), urls[index].absoluteString)
            XCTAssertEqual(restoredItem.data(forType: customType), Data([UInt8(index)]))
        }
    }

    @MainActor
    func testLegacyFinderFileListIsRecognizedAndRoundTrips() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let paths = ["/tmp/first.txt", "/tmp/second.png"]
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        pasteboard.declareTypes([legacyType], owner: nil)
        XCTAssertTrue(pasteboard.setPropertyList(paths, forType: legacyType))
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .files)
        XCTAssertEqual(entry.fileURLs.map(\.path), paths)
        write("Replace file list", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        XCTAssertEqual(pasteboard.propertyList(forType: legacyType) as? [String], paths)
    }

    @MainActor
    func testRichTextRestoresEveryRepresentationRatherThanOnlyPlainText() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let plain = Data("Bold text".utf8)
        let rtf = Data(#"{\rtf1\ansi {\b Bold text}}"#.utf8)
        let html = Data("<strong>Bold text</strong>".utf8)
        writeItems([item([.string: plain, .rtf: rtf, .html: html])], to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .richText)
        XCTAssertTrue(entry.title.contains("Bold text"))
        write("Replace rich text", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        let restored = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(restored.data(forType: .string), plain)
        XCTAssertEqual(restored.data(forType: .rtf), rtf)
        XCTAssertEqual(restored.data(forType: .html), html)
    }

    @MainActor
    func testSamePlainTextWithDifferentFormattingIsNotDeduplicated() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let plain = Data("Same words".utf8)
        let bold = Data(#"{\rtf1\ansi {\b Same words}}"#.utf8)
        let italic = Data(#"{\rtf1\ansi {\i Same words}}"#.utf8)
        writeItems([item([.string: plain, .rtf: bold])], to: pasteboard)
        manager.pollClipboard()
        let boldEntry = try XCTUnwrap(manager.entries.first)
        writeItems([item([.string: plain, .rtf: italic])], to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.count, 2)
        XCTAssertNotEqual(manager.entries[0].id, boldEntry.id)

        XCTAssertTrue(manager.copy(boldEntry))
        XCTAssertEqual(pasteboard.data(forType: .rtf), bold)
    }

    @MainActor
    func testUnknownBinaryAndEmptyCustomRepresentationArePreserved() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let binaryType = NSPasteboard.PasteboardType("com.example.iceland.binary")
        let emptyType = NSPasteboard.PasteboardType("com.example.iceland.empty")
        let binary = Data([0, 255, 13, 10, 128, 0])
        writeItems([item([binaryType: binary, emptyType: Data()])], to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .data)
        XCTAssertFalse(entry.title.isEmpty)

        write("Replace binary", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        XCTAssertEqual(pasteboard.data(forType: binaryType), binary)
        XCTAssertEqual(pasteboard.data(forType: emptyType), Data())
    }

    @MainActor
    func testWebURLKeepsBothLinkAndPlainTextRepresentations() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let url = "https://example.com/path?q=clipboard#item"
        let urlData = Data(url.utf8)
        writeItems([item([.URL: urlData, .string: urlData])], to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.kind, .url)
        XCTAssertFalse(entry.title.isEmpty)
        write("Replace URL", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        XCTAssertEqual(pasteboard.data(forType: .URL), urlData)
        XCTAssertEqual(pasteboard.string(forType: .string), url)
    }

    @MainActor
    func testMixedItemsRestoreAllTypesInTheirOriginalItemOrder() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let png = try pngData()
        let custom = NSPasteboard.PasteboardType("com.example.iceland.vector")
        let vector = Data("<svg/>".utf8)
        writeItems([
            item([.string: Data("Text item".utf8)]),
            item([.png: png]),
            item([custom: vector])
        ], to: pasteboard)
        manager.pollClipboard()
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(manager.entries.count, 1)
        write("Replace mixed items", to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.copy(entry))
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored[0].string(forType: .string), "Text item")
        XCTAssertEqual(restored[1].data(forType: .png), png)
        XCTAssertEqual(restored[2].data(forType: custom), vector)

        // History holds data, never one-shot NSPasteboardItem instances owned by a prior copy.
        write("Another later clipboard owner", to: pasteboard)
        XCTAssertTrue(manager.copy(entry))
        let restoredAgain = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restoredAgain.count, 3)
        XCTAssertEqual(restoredAgain[0].string(forType: .string), "Text item")
        XCTAssertEqual(restoredAgain[1].data(forType: .png), png)
        XCTAssertEqual(restoredAgain[2].data(forType: custom), vector)
    }

    @MainActor
    func testSensitiveMarkerOnAnyItemExcludesTheWholeCopy() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        writeItems([
            item([.string: Data("First item".utf8)]),
            item([.png: try pngData(), concealed: Data()])
        ], to: pasteboard)
        manager.pollClipboard()
        XCTAssertTrue(manager.entries.isEmpty, "A sensitive multi-item copy must not be partially retained")
    }

    @MainActor
    func testOwnershipMetadataDoesNotCreateDuplicateEntries() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
        let content = Data("Same copied content".utf8)
        writeItems([item([.string: content, sourceType: Data("app.one".utf8)])], to: pasteboard)
        manager.pollClipboard()
        let originalID = try XCTUnwrap(manager.entries.first?.id)
        writeItems([item([.string: content, sourceType: Data("app.two".utf8)])], to: pasteboard)
        manager.pollClipboard()
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.id, originalID)
    }

    @MainActor
    func testLiveFilePromisesRemainVisibleButAreNeverRestoredAsFileContents() async throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pasteboard, startMonitoring: false)
        let promise = NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type")
        let descriptor = Data("public.png".utf8)
        // A descriptor references a live source transfer; it is not a saved image.
        writeItems([item([.string: Data("Attachment label".utf8), promise: descriptor])], to: pasteboard)
        manager.pollClipboard()
        let partial = try XCTUnwrap(manager.entries.first)
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(partial.canRestore)
        XCTAssertTrue(partial.unavailableTypeNames.contains(promise.rawValue))
        XCTAssertTrue(manager.copy(partial))
        XCTAssertEqual(pasteboard.string(forType: .string), "Attachment label")
        XCTAssertNil(pasteboard.data(forType: promise), "A stale promise must not masquerade as restored file data")

        writeItems([item([promise: descriptor])], to: pasteboard)
        manager.pollClipboard()
        let unavailable = try XCTUnwrap(manager.entries.first)
        XCTAssertFalse(unavailable.isComplete)
        XCTAssertFalse(unavailable.canRestore)
        XCTAssertFalse(unavailable.title.isEmpty)
        let changeCount = pasteboard.changeCount
        XCTAssertFalse(manager.copy(unavailable))
        XCTAssertEqual(pasteboard.changeCount, changeCount, "An unavailable copy must not erase the current clipboard")
    }
}
