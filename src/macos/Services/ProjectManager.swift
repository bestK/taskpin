import SwiftUI
import AppKit

class ProjectManager: ObservableObject {
    @Published var itemStates: [UUID: PinItemState] = [:]
    @Published var activeItemId: UUID? = nil

    private var timers: [UUID: Timer] = [:]
    private var rotationTimer: Timer?
    private var pinnedIndex: Int = 0

    let configManager: ConfigManager

    var activeState: PinItemState {
        guard let id = activeItemId else { return PinItemState() }
        return itemStates[id] ?? PinItemState()
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func startAll() {
        stopAll()
        for item in configManager.config.items where item.pinned {
            startItem(item)
        }
        startRotation()
    }

    func stopAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    func startItem(_ item: PinItem) {
        stopItem(item.id)
        executeItem(item)
        let interval = max(Double(item.intervalMs) / 1000.0, 1.0)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.executeItem(item)
        }
        timers[item.id] = timer
    }

    func stopItem(_ id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
    }

    func restartAll() {
        startAll()
    }

    private func executeItem(_ item: PinItem) {
        switch item.type {
        case .lua: executeLuaItem(item)
        case .url: executeURLItem(item)
        }
    }

    private func executeLuaItem(_ item: PinItem) {
        guard !item.luaPath.isEmpty else { return }
        var argsJson: String? = nil
        if !item.params.isEmpty {
            let dict = Dictionary(uniqueKeysWithValues: item.params.map { ($0.key, $0.value) })
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                argsJson = str
            }
        }
        let itemId = item.id
        LuaExecutor.shared.executeFile(path: item.luaPath, argsJson: argsJson) { [weak self] result in
            guard let self = self else { return }
            if let result = result {
                var state = PinItemState()
                state.statusText = result.statusText
                state.statusColor = result.statusColor
                state.statusImage = result.statusImage
                state.dialogItems = result.dialogItems
                state.dialogWidth = result.dialogWidth
                state.dialogHeight = result.dialogHeight
                state.clickable = result.clickable
                state.isRunning = true
                self.itemStates[itemId] = state

                if result.dialogRefresh > 0 {
                    let newInterval = Double(result.dialogRefresh)
                    if let existing = self.timers[itemId], existing.timeInterval != newInterval {
                        existing.invalidate()
                        self.timers[itemId] = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
                            self?.executeItem(item)
                        }
                    }
                }
            } else {
                var state = self.itemStates[itemId] ?? PinItemState()
                state.lastError = "Script error"
                state.statusText = "[error]"
                state.statusColor = .red
                self.itemStates[itemId] = state
            }
        }
    }

    private func executeURLItem(_ item: PinItem) {
        guard let requestUrl = URL(string: item.url) else { return }
        var request = URLRequest(url: requestUrl)
        for line in item.reqHeaders.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                request.addValue(String(parts[1]).trimmingCharacters(in: .whitespaces),
                               forHTTPHeaderField: String(parts[0]).trimmingCharacters(in: .whitespaces))
            }
        }

        let itemId = item.id
        let fieldExpr = item.fieldExpr
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let body = String(data: data, encoding: .utf8) else { return }

            if fieldExpr.isEmpty {
                DispatchQueue.main.async {
                    var state = PinItemState()
                    state.statusText = String(body.prefix(100))
                    state.isRunning = true
                    self.itemStates[itemId] = state
                }
                return
            }

            let tmpDir = FileManager.default.temporaryDirectory
            let tmpFile = tmpDir.appendingPathComponent("taskpin_url_\(itemId.uuidString).lua")
            let script = "response = [=[\(body)]=]\n\(fieldExpr)"
            try? script.write(to: tmpFile, atomically: true, encoding: .utf8)

            LuaExecutor.shared.executeFile(path: tmpFile.path, argsJson: nil) { [weak self] result in
                guard let self = self else { return }
                if let result = result {
                    var state = PinItemState()
                    state.statusText = result.statusText
                    state.statusColor = result.statusColor
                    state.dialogItems = result.dialogItems
                    state.isRunning = true
                    self.itemStates[itemId] = state
                } else {
                    var state = self.itemStates[itemId] ?? PinItemState()
                    state.lastError = "Expression error"
                    self.itemStates[itemId] = state
                }
            }
        }.resume()
    }

    private func startRotation() {
        let pinned = configManager.config.items.filter { $0.pinned }
        guard !pinned.isEmpty else {
            activeItemId = nil
            return
        }
        activeItemId = pinned[0].id
    }

    func handleButtonClick(_ item: DialogItemModel) {
        if let url = item.url { NSWorkspace.shared.open(url) }
        else if let cmd = item.cmd {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", cmd]
            try? task.run()
        }
    }
}
