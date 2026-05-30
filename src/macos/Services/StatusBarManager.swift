import SwiftUI
import AppKit

final class StatusBarManager: NSObject, NSMenuDelegate {
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var popovers: [UUID: NSPopover] = [:]
    private var refreshTimer: Timer?
    private var itemMap: [UUID: PinItem] = [:]

    private let projectManager: ProjectManager
    private let configManager: ConfigManager

    init(projectManager: ProjectManager, configManager: ConfigManager) {
        self.projectManager = projectManager
        self.configManager = configManager
        super.init()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func rebuildAll() {
        let pinnedItems = configManager.config.items.filter { $0.pinned }
        let pinnedIds = Set(pinnedItems.map { $0.id })

        for (id, item) in statusItems where !pinnedIds.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems.removeValue(forKey: id)
            popovers.removeValue(forKey: id)
            itemMap.removeValue(forKey: id)
        }

        for item in pinnedItems {
            itemMap[item.id] = item
            if statusItems[item.id] == nil {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.button?.action = #selector(onStatusItemClick(_:))
                statusItem.button?.target = self
                statusItems[item.id] = statusItem
            }
            updateStatusItem(item)
        }
    }

    func refresh() {
        rebuildAll()
    }

    @objc private func onStatusItemClick(_ sender: NSStatusBarButton) {
        guard let clickedItem = statusItems.first(where: { $0.value.button === sender }) else { return }
        let id = clickedItem.key
        guard let item = itemMap[id] else { return }

        if item.clickEnabled, !item.clickUrl.isEmpty, let url = URL(string: item.clickUrl) {
            NSWorkspace.shared.open(url)
            return
        }

        let state = projectManager.itemStates[id]
        let dialogItems = state?.dialogItems ?? []
        guard !dialogItems.isEmpty else { return }

        showPopover(for: id, dialogItems: dialogItems, state: state)
    }

    private func showPopover(for id: UUID, dialogItems: [DialogItemModel], state: PinItemState?) {
        guard let button = statusItems[id]?.button else { return }

        if let existing = popovers[id], existing.isShown {
            existing.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        let w = state?.dialogWidth ?? 400
        let h = state?.dialogHeight ?? 300
        popover.contentSize = NSSize(width: w, height: h)
        let view = LiveDialogPopoverView(itemId: id, projectManager: projectManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        popover.contentViewController = NSHostingController(rootView: view)
        popovers[id] = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
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
        refreshTimer?.invalidate()
        refreshTimer = nil
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
        popovers.removeAll()
        itemMap.removeAll()
    }
}

struct LiveDialogPopoverView: View {
    let itemId: UUID
    @ObservedObject var projectManager: ProjectManager

    var body: some View {
        let items = projectManager.itemStates[itemId]?.dialogItems ?? []
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    dialogItemView(item)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func dialogItemView(_ item: DialogItemModel) -> some View {
        switch item.kind {
        case .text:
            HStack(spacing: 6) {
                if let img = item.image {
                    Image(nsImage: img).resizable().frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
                }
                Text(item.text)
                    .font(.system(size: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular))
                    .foregroundColor(item.color)
            }
        case .hr:
            Divider().padding(.vertical, 2)
        case .button:
            Button(item.text) { projectManager.handleButtonClick(item) }
                .buttonStyle(.bordered).controlSize(.small)
        case .image:
            if let img = item.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
            }
        case .table:
            TableItemView(item: item)
        }
    }
}
