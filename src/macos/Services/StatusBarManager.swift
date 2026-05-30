import SwiftUI
import AppKit
import Combine

class StatusBarManager: ObservableObject {
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let projectManager: ProjectManager
    private let configManager: ConfigManager

    init(projectManager: ProjectManager, configManager: ConfigManager) {
        self.projectManager = projectManager
        self.configManager = configManager

        projectManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &cancellables)

        configManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildAll() }
        }.store(in: &cancellables)
    }

    func rebuildAll() {
        let pinnedItems = configManager.config.items.filter { $0.pinned }
        let pinnedIds = Set(pinnedItems.map { $0.id })

        for (id, item) in statusItems where !pinnedIds.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
        }

        for item in pinnedItems {
            if statusItems[item.id] == nil {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItems[item.id] = statusItem
            }
            updateStatusItem(item)
        }
    }

    func refresh() {
        let pinnedItems = configManager.config.items.filter { $0.pinned }
        for item in pinnedItems {
            updateStatusItem(item)
        }
    }

    private func updateStatusItem(_ item: PinItem) {
        guard let statusItem = statusItems[item.id] else { return }
        guard let button = statusItem.button else { return }

        let state = projectManager.itemStates[item.id]
        let text = state?.statusText ?? item.name
        let nsColor: NSColor

        if let swiftColor = state?.statusColor {
            nsColor = NSColor(swiftColor)
        } else {
            nsColor = .secondaryLabelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: nsColor
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attrs)

        if let img = state?.statusImage {
            img.size = NSSize(width: 16, height: 16)
            img.isTemplate = false
            button.image = img
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }
    }

    func removeAll() {
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
    }
}
