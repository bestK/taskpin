import SwiftUI
import AppKit

// MARK: - Models

enum DialogItemKind: String {
    case text, hr, button, image, table
}

struct TableRow: Identifiable {
    let id = UUID()
    let cells: [String]
    let url: URL?
    let cmd: String?
}

struct DialogItemModel: Identifiable {
    let id = UUID()
    let kind: DialogItemKind
    var text: String = ""
    var color: Color = .white
    var fontSize: Int = 12
    var bold: Bool = false
    var image: NSImage? = nil
    var imageWidth: Int = 16
    var imageHeight: Int = 16
    var url: URL? = nil
    var cmd: String? = nil
    // table
    var columns: [String] = []
    var rows: [TableRow] = []
}

// MARK: - Script Engine

class ScriptEngine: ObservableObject {
    @Published var statusText: String = "TaskPin"
    @Published var statusColor: Color = .white
    @Published var statusImage: NSImage? = nil
    @Published var dialogItems: [DialogItemModel] = []

    private var timer: Timer?
    private var luaState: OpaquePointer?

    init() {
        setupLua()
        startRefresh()
    }

    deinit {
        timer?.invalidate()
    }

    private func setupLua() {
        // TODO: Initialize Lua 5.4 state
        // Register json.decode, http.get/post, sys.*, log(), font(), icon(), dialog()
    }

    private func startRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.executeScript()
        }
        executeScript()
    }

    func executeScript() {
        // TODO: Execute current Lua script
        // Parse return values into statusText/statusColor/statusImage/dialogItems
    }

    func handleButtonClick(_ item: DialogItemModel) {
        if let url = item.url {
            NSWorkspace.shared.open(url)
        } else if let cmd = item.cmd {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", cmd]
            try? task.run()
        }
    }
}
