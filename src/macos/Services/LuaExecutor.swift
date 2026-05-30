import SwiftUI
import AppKit
import TaskPinLua

struct LuaResult {
    var statusText: String = ""
    var statusColor: Color = .white
    var statusImage: NSImage? = nil
    var dialogItems: [DialogItemModel] = []
    var dialogWidth: Int = 400
    var dialogHeight: Int = 300
    var dialogRefresh: Int = 0
    var clickable: Bool = false
}

class LuaExecutor {
    static let shared = LuaExecutor()
    private let queue = DispatchQueue(label: "com.taskpin.lua")
    private var initialized = false

    func initialize() {
        queue.sync {
            guard !initialized else { return }
            tp_lua_init()
            initialized = true
        }
    }

    func shutdown() {
        queue.sync {
            guard initialized else { return }
            tp_lua_shutdown()
            initialized = false
        }
    }

    func executeFile(path: String, argsJson: String?,
                     completion: @escaping (LuaResult?) -> Void) {
        queue.async {
            let nresults = tp_lua_execute(path, argsJson)
            if nresults < 0 {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let result = self.parseResults(nresults: Int(nresults))
            tp_lua_clear_stack()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func parseResults(nresults: Int) -> LuaResult {
        var result = LuaResult()

        if nresults >= 1 && tp_lua_is_span(1) != 0 {
            let count = tp_lua_span_count(1)
            var text = ""
            var color: Color = .white
            for i in 0..<count {
                var span = tp_lua_get_span(1, Int32(i))
                if span.is_image == 0 {
                    let t = withUnsafeBytes(of: &span.text) { buf in
                        guard let base = buf.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
                        return String(cString: base)
                    }
                    text += t
                    let c = withUnsafeBytes(of: &span.color) { buf in
                        guard let base = buf.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
                        return String(cString: base)
                    }
                    if !c.isEmpty { color = Self.parseColor(c) }
                } else {
                    let src = withUnsafeBytes(of: &span.text) { buf in
                        guard let base = buf.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
                        return String(cString: base)
                    }
                    if !src.isEmpty, result.statusImage == nil {
                        result.statusImage = Self.loadImage(from: src, width: Int(span.img_w), height: Int(span.img_h))
                    }
                }
            }
            result.statusText = text
            result.statusColor = color
        }

        if nresults >= 2 {
            result.clickable = tp_lua_get_bool(2) != 0
        }

        if nresults >= 3 && tp_lua_is_dialog(3) != 0 {
            let specPtr = UnsafeMutablePointer<TPDialogSpec>.allocate(capacity: 1)
            defer { specPtr.deallocate() }
            memset(specPtr, 0, MemoryLayout<TPDialogSpec>.size)
            tp_lua_get_dialog_into(3, specPtr)
            result.dialogWidth = Int(specPtr.pointee.width)
            result.dialogHeight = Int(specPtr.pointee.height)
            result.dialogRefresh = Int(specPtr.pointee.refresh)
            result.dialogItems = Self.parseDialogItems(from: specPtr)
        }

        return result
    }

    static func parseDialogItems(from specPtr: UnsafeMutablePointer<TPDialogSpec>) -> [DialogItemModel] {
        var items: [DialogItemModel] = []
        let itemCount = Int(specPtr.pointee.item_count)
        guard itemCount > 0 && itemCount <= 8 else { return items }

        for i in 0..<itemCount {
            withUnsafePointer(to: &specPtr.pointee.items) { tuplePtr in
                let base = UnsafeRawPointer(tuplePtr).assumingMemoryBound(to: TPDialogItem.self)
                let rawPtr = base.advanced(by: i)

                let type = withUnsafeBytes(of: rawPtr.pointee.type) { buf in
                    String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                let value = withUnsafeBytes(of: rawPtr.pointee.value) { buf in
                    String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                let colorStr = withUnsafeBytes(of: rawPtr.pointee.color) { buf in
                    String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                let urlStr = withUnsafeBytes(of: rawPtr.pointee.url) { buf in
                    String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                let cmdStr = withUnsafeBytes(of: rawPtr.pointee.cmd) { buf in
                    String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                }

                let color = colorStr.isEmpty ? Color.white : parseColor(colorStr)
                let fontSize = Int(rawPtr.pointee.font_size) > 0 ? Int(rawPtr.pointee.font_size) : 12

                switch type {
                case "text":
                    items.append(DialogItemModel(kind: .text, text: value, color: color, fontSize: fontSize, bold: rawPtr.pointee.bold != 0))
                case "hr":
                    items.append(DialogItemModel(kind: .hr))
                case "button":
                    var m = DialogItemModel(kind: .button, text: value, color: color, fontSize: fontSize)
                    if !urlStr.isEmpty { m.url = URL(string: urlStr) }
                    if !cmdStr.isEmpty { m.cmd = cmdStr }
                    items.append(m)
                case "image":
                    let imgStr = withUnsafeBytes(of: rawPtr.pointee.image) { buf in
                        String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
                    }
                    var m = DialogItemModel(kind: .image)
                    m.imageWidth = Int(rawPtr.pointee.image_width)
                    m.imageHeight = Int(rawPtr.pointee.image_height)
                    if !imgStr.isEmpty {
                        m.image = loadImage(from: imgStr, width: m.imageWidth, height: m.imageHeight)
                    }
                    items.append(m)
                case "table":
                    var m = DialogItemModel(kind: .table)
                    let colCount = Int(rawPtr.pointee.col_count)
                    let rowCount = Int(rawPtr.pointee.row_count)
                    withUnsafeBytes(of: rawPtr.pointee.columns) { buf in
                        let base = buf.baseAddress!
                        for c in 0..<colCount {
                            let ptr = base.advanced(by: c * 64).assumingMemoryBound(to: CChar.self)
                            m.columns.append(String(cString: ptr))
                        }
                    }
                    withUnsafeBytes(of: rawPtr.pointee.cells) { cellsBuf in
                        withUnsafeBytes(of: rawPtr.pointee.row_urls) { urlsBuf in
                            let cellsBase = cellsBuf.baseAddress!
                            let urlsBase = urlsBuf.baseAddress!
                            for r in 0..<rowCount {
                                var cells: [String] = []
                                for c in 0..<colCount {
                                    let ptr = cellsBase.advanced(by: (r * 6 + c) * 64).assumingMemoryBound(to: CChar.self)
                                    cells.append(String(cString: ptr))
                                }
                                let urlPtr = urlsBase.advanced(by: r * 256).assumingMemoryBound(to: CChar.self)
                                let rowUrlStr = String(cString: urlPtr)
                                let rowUrl = rowUrlStr.isEmpty ? nil : URL(string: rowUrlStr)
                                m.rows.append(TableRow(cells: cells, url: rowUrl, cmd: nil))
                            }
                        }
                    }
                    items.append(m)
                default:
                    break
                }
            }
        }
        return items
    }

    static func parseColor(_ hex: String) -> Color {
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

    private static var imageCache: [String: NSImage] = [:]

    static func loadImage(from source: String, width: Int, height: Int) -> NSImage? {
        if let cached = imageCache[source] { return cached }

        var image: NSImage? = nil

        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            guard let url = URL(string: source),
                  let data = try? Data(contentsOf: url) else { return nil }
            image = NSImage(data: data)
        } else {
            image = NSImage(contentsOfFile: source)
        }

        if let img = image {
            let w = width > 0 ? width : 16
            let h = height > 0 ? height : 16
            let resized = NSImage(size: NSSize(width: w, height: h))
            resized.lockFocus()
            img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
            resized.unlockFocus()
            imageCache[source] = resized
            return resized
        }
        return nil
    }
}
