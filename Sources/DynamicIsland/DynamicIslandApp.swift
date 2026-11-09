import AppKit
import ServiceManagement
import SwiftUI

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: IslandWindowController?
    private let viewModel = IslandViewModel()
    private var statusItem: NSStatusItem?
    
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarMenu()
        
        let controller = IslandWindowController(viewModel: viewModel)
        self.windowController = controller
        controller.show()
        
        // Приветственное плавное раскрытие шторки при запуске на 2.5 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.viewModel.expand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
                guard let self else { return }
                let mouseLoc = NSEvent.mouseLocation
                let activeRect = self.viewModel.geometry.activeScreenRect(isExpanded: true)
                if !activeRect.contains(mouseLoc) && !self.viewModel.isPinned {
                    self.viewModel.collapse()
                }
            }
        }
    }
    
    private func setupStatusBarMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "menubar.dock.rectangle",
                accessibilityDescription: "Dynamic Island"
            )
        }
        
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "Expand / Collapse Island",
            action: #selector(toggleIsland),
            keyEquivalent: "d"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let pinItem = NSMenuItem(
            title: "Keep Island Open",
            action: #selector(togglePin(_:)),
            keyEquivalent: "p"
        )
        pinItem.target = self
        menu.addItem(pinItem)
        
        menu.addItem(.separator())
        
        let musicItem = NSMenuItem(title: "Open: Music", action: #selector(openMusicTab), keyEquivalent: "1")
        musicItem.target = self
        menu.addItem(musicItem)
        
        let clipboardItem = NSMenuItem(title: "Open: Clipboard", action: #selector(openClipboardTab), keyEquivalent: "2")
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        
        menu.addItem(.separator())
        
        // Настройки поведения
        let hapticItem = NSMenuItem(
            title: "Trackpad Haptic Feedback",
            action: #selector(toggleHaptics(_:)),
            keyEquivalent: ""
        )
        hapticItem.target = self
        hapticItem.state = viewModel.hapticFeedbackEnabled ? .on : .off
        menu.addItem(hapticItem)
        
        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Dynamic Island",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        item.menu = menu
        self.statusItem = item
    }
    
    @objc private func toggleIsland() {
        if viewModel.isExpanded {
            viewModel.collapse(force: true)
        } else {
            viewModel.expand()
        }
    }
    
    @objc private func togglePin(_ sender: NSMenuItem) {
        viewModel.isPinned.toggle()
        sender.state = viewModel.isPinned ? .on : .off
        if viewModel.isPinned {
            viewModel.expand()
        }
    }
    
    @objc private func toggleHaptics(_ sender: NSMenuItem) {
        viewModel.hapticFeedbackEnabled.toggle()
        sender.state = viewModel.hapticFeedbackEnabled ? .on : .off
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSSound.beep()
        }
    }
    
    @objc private func openMusicTab() {
        viewModel.activeTab = .music
        viewModel.expand()
    }
    
    @objc private func openClipboardTab() {
        viewModel.activeTab = .clipboard
        viewModel.expand()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
