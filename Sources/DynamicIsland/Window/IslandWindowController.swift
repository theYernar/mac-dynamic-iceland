import AppKit
import Combine
import SwiftUI

@MainActor
public final class IslandWindowController {
    public let panel: DynamicIslandPanel
    public let viewModel: IslandViewModel
    
    private var hoverTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    
    public init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        let geometry = NotchGeometry.detect()
        self.viewModel.geometry = geometry
        
        self.panel = DynamicIslandPanel(contentRect: geometry.panelFrame)
        let hostingView = NSHostingView(rootView: DynamicIslandContentView(viewModel: viewModel))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: geometry.panelFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        self.panel.contentView = hostingView
        self.panel.setFrame(geometry.panelFrame, display: true)
        self.panel.ignoresMouseEvents = true
        self.panel.alphaValue = 0.0
        
        setupScreenAndSpaceObservers()
        setupStateObserver()
        setupMouseTracking()
    }
    
    public func show() {
        updatePanelGeometry()
        panel.orderFrontRegardless()
    }
    
    public func updatePanelGeometry() {
        let newGeometry = NotchGeometry.detect()
        viewModel.geometry = newGeometry
        panel.setFrame(newGeometry.panelFrame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: newGeometry.panelFrame.size)
    }
    
    private func setupStateObserver() {
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.panel.ignoresMouseEvents = !expanded
            }
            .store(in: &cancellables)

        viewModel.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    self.panel.alphaValue = 1.0
                    self.panel.orderFrontRegardless()
                } else {
                    self.panel.alphaValue = 0.0
                    self.panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupScreenAndSpaceObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePanelGeometry()
            }
        }
        
        // При переключении между рабочими столами (Spaces) мгновенно скрываем шторку
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.expandWorkItem?.cancel()
                self.expandWorkItem = nil
                self.viewModel.collapse(force: true, animated: false)
                self.panel.ignoresMouseEvents = true
                self.panel.alphaValue = 0.0
            }
        }
    }
    
    private func setupMouseTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateMousePosition()
            }
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateMousePosition()
            }
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.evaluateMousePosition()
            }
            return event
        }
    }
    
    private func evaluateMousePosition() {
        let mouseLoc = NSEvent.mouseLocation
        let activeRect = viewModel.geometry.activeScreenRect(isExpanded: viewModel.isExpanded)
        
        let isInside = activeRect.contains(mouseLoc)
        
        if isInside {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            
            if !viewModel.isExpanded && expandWorkItem == nil {
                let item = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.expandWorkItem = nil
                        self.viewModel.expand()
                    }
                }
                expandWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
            }
        } else {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            
            if viewModel.isExpanded && !viewModel.isPinned {
                if collapseWorkItem == nil {
                    let item = DispatchWorkItem { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            self.collapseWorkItem = nil
                            self.viewModel.collapse()
                        }
                    }
                    collapseWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + viewModel.collapseDelay, execute: item)
                }
            }
        }
    }
}
