import SwiftUI
import AppKit
import TaskPinLua

enum DialogItemKind: String { case text, hr, button, image, table }

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

class ScriptEngine: ObservableObject {
    @Published var statusText: String = "TaskPin"
    @Published var statusColor: Color = .white
    @Published var statusImage: NSImage? = nil
    @Published var dialogItems: [DialogItemModel] = []

    private var timer: Timer?
    private var scriptPath: String? = nil

    init() {
        tp_lua_init()
        // Try to find a script in app bundle or current dir
        let paths = [
            Bundle.main.path(forResource: "system_monitor", ofType: "lua"),
            "examples/system_monitor.lua",
            "system_monitor.lua"
        ]
        for p in paths {
            if let p = p, FileManager.default.fileExists(atPath: p) {
                scriptPath = p
                break
            }
        }
        startRefresh()
    }

    deinit {
        timer?.invalidate()
        tp_lua_shutdown()
    }

    private func startRefresh() {
        executeScript()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.executeScript()
        }
    }

    func executeScript() {
        guard let path = scriptPath else {
            showDemo()
            return
        }

        let nresults = tp_lua_execute(path, nil)
        if nresults < 0 {
            DispatchQueue.main.async {
                self.statusText = "[error]"
                self.statusColor = .red
            }
            return
        }

        var spans: [TPSpan] = []
        if nresults >= 1 && tp_lua_is_span(1) != 0 {
            let count = tp_lua_span_count(1)
            for i in 0..<count {
                spans.append(tp_lua_get_span(1, Int32(i)))
            }
        }

        let clickable = nresults >= 2 ? tp_lua_get_bool(2) != 0 : false
        _ = clickable

        var items: [DialogItemModel] = []
        if nresults >= 3 && tp_lua_is_dialog(3) != 0 {
            items = self.parseDialog(at: 3)
            items = self.parseDialog(at: 3)
        }

        tp_lua_clear_stack()

        DispatchQueue.main.async {
            // Build status text from spans
            var text = ""
            var color: Color = .white
            for var span in spans {
                if span.is_image == 0 {
                    let t = String(cString: &span.text.0, maxLength: 512)
                    text += t
                    let c = String(cString: &span.color.0, maxLength: 16)
                    if !c.isEmpty { color = self.parseColor(c) }
                }
            }
            self.statusText = text.isEmpty ? "TaskPin" : text
            self.statusColor = color
            if !items.isEmpty { self.dialogItems = items }
        }
    }

    private func showDemo() {
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
                DialogItemModel(kind: .text, text: "No script loaded", color: .gray, fontSize: 10),
                DialogItemModel(kind: .button, text: "Open GitHub", url: URL(string: "https://github.com/bestK/taskpin")),
            ]
        }
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

    private func parseColor(_ hex: String) -> Color {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard let val = UInt64(h, radix: 16) else { return .white }
        if h.count == 6 {
            return Color(red: Double((val >> 16) & 0xFF) / 255,
                         green: Double((val >> 8) & 0xFF) / 255,
                         blue: Double(val & 0xFF) / 255)
        }
        return .white
    }
}

extension String {
    init(cString tuple: UnsafePointer<CChar>, maxLength: Int) {
        self = String(cString: tuple)
    }
}

extension ScriptEngine {
    func parseDialog(at idx: Int32) -> [DialogItemModel] {
        let spec = tp_lua_get_dialog(idx)
        var items: [DialogItemModel] = []

        for i in 0..<Int(spec.item_count) {
            let raw = spec.items.0  // placeholder - need tuple access
            _ = raw
        }

        // Access tuple elements via withUnsafePointer
        withUnsafePointer(to: spec.items) { ptr in
            let base = UnsafeRawPointer(ptr).assumingMemoryBound(to: TPDialogItem.self)
            for i in 0..<Int(spec.item_count) {
                let raw = base[i]
                let type = String(cString: withUnsafePointer(to: raw.type) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })
                let value = String(cString: withUnsafePointer(to: raw.value) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })
                let colorStr = String(cString: withUnsafePointer(to: raw.color) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })
                let urlStr = String(cString: withUnsafePointer(to: raw.url) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })
                let cmdStr = String(cString: withUnsafePointer(to: raw.cmd) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })

                let color = colorStr.isEmpty ? Color.white : parseColor(colorStr)
                let fontSize = Int(raw.font_size) > 0 ? Int(raw.font_size) : 12

                switch type {
                case "text":
                    items.append(DialogItemModel(kind: .text, text: value, color: color, fontSize: fontSize, bold: raw.bold != 0))
                case "hr":
                    items.append(DialogItemModel(kind: .hr))
                case "button":
                    var m = DialogItemModel(kind: .button, text: value, color: color, fontSize: fontSize)
                    if !urlStr.isEmpty { m.url = URL(string: urlStr) }
                    if !cmdStr.isEmpty { m.cmd = cmdStr }
                    items.append(m)
                case "image":
                    let imgStr = String(cString: withUnsafePointer(to: raw.image) { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) })
                    var m = DialogItemModel(kind: .image)
                    m.imageWidth = Int(raw.image_width)
                    m.imageHeight = Int(raw.image_height)
                    if !imgStr.isEmpty, let img = NSImage(contentsOfFile: imgStr) { m.image = img }
                    items.append(m)
                default:
                    break
                }
            }
        }
        return items
    }
}
