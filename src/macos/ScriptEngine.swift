import SwiftUI
import AppKit
import CLua

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
    private var L: OpaquePointer?

    init() {
        setupLua()
        startRefresh()
    }

    deinit {
        timer?.invalidate()
        if let L = L { lua_close(L) }
    }

    private func setupLua() {
        L = luaL_newstate()
        guard let L = L else { return }
        luaL_openlibs(L)
    }

    private func startRefresh() {
        executeScript()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.executeScript()
        }
    }

    func executeScript() {
        // Demo content until full Lua integration
        let cpu = Int.random(in: 10...90)
        let mem = Int.random(in: 40...80)

        DispatchQueue.main.async {
            self.statusText = "CPU:\(cpu)% MEM:\(mem)%"
            self.statusColor = cpu > 70 ? .red : .green

            self.dialogItems = [
                DialogItemModel(kind: .text, text: "TaskPin macOS", color: .orange, fontSize: 14, bold: true),
                DialogItemModel(kind: .hr),
                DialogItemModel(kind: .text, text: "CPU: \(cpu)%", color: cpu > 70 ? .red : .green, fontSize: 12),
                DialogItemModel(kind: .text, text: "MEM: \(mem)%", color: mem > 70 ? .orange : .green, fontSize: 12),
                DialogItemModel(kind: .hr),
                DialogItemModel(kind: .text, text: "Lua engine: ready", color: .gray, fontSize: 10),
                DialogItemModel(kind: .button, text: "Open GitHub", url: URL(string: "https://github.com/bestK/taskpin")),
            ]
        }
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
