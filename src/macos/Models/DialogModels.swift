import SwiftUI

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

struct PinItemState {
    var statusText: String = ""
    var statusColor: Color = .white
    var statusImage: NSImage? = nil
    var dialogItems: [DialogItemModel] = []
    var lastError: String? = nil
    var isRunning: Bool = false
}
