import AppKit
import Combine
import SwiftUI

public enum IslandTab: String, CaseIterable, Identifiable {
    case music = "Music"
    case clipboard = "Clipboard"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .music: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

@MainActor
public final class IslandViewModel: ObservableObject {
    @Published public private(set) var isExpanded: Bool = false
    /// Окно остаётся видимым до фактического завершения анимации закрытия.
    @Published public private(set) var isPresented: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var activeTab: IslandTab = .music
    @Published public var geometry: NotchGeometry = NotchGeometry.detect()
    
    @Published public var hapticFeedbackEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled")
        }
    }
    
    @Published public var collapseDelay: Double = {
        let saved = UserDefaults.standard.double(forKey: "collapseDelay")
        return saved > 0.05 ? saved : 0.24
    }() {
        didSet {
            UserDefaults.standard.set(collapseDelay, forKey: "collapseDelay")
        }
    }
    
    public let musicManager = MusicManager()
    public let audioManager = AudioControlManager()
    public let clipboardManager = ClipboardManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var presentationRevision: UInt = 0
    
    public init() {
        musicManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        clipboardManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        
        audioManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    public func expand() {
        guard !isExpanded else { return }
        presentationRevision &+= 1
        let revision = presentationRevision
        isPresented = true
        if hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        withAnimation(.smooth(duration: 0.44, extraBounce: 0), completionCriteria: .removed) {
            isExpanded = true
        } completion: { [weak self] in
            guard let self, self.presentationRevision == revision, self.isExpanded else { return }
            self.audioManager.syncCurrentAudioState()
            self.clipboardManager.pollClipboard()
        }
        musicManager.refreshNowPlaying()
    }
    
    public func collapse(force: Bool = false, animated: Bool = true) {
        if isPinned && !force { return }
        guard isExpanded || (!animated && isPresented) else { return }
        presentationRevision &+= 1
        let revision = presentationRevision
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded = false
                isPresented = false
            }
            return
        }
        withAnimation(.smooth(duration: 0.38, extraBounce: 0), completionCriteria: .removed) {
            isExpanded = false
        } completion: { [weak self] in
            guard let self, self.presentationRevision == revision, !self.isExpanded else { return }
            self.isPresented = false
        }
    }
}
