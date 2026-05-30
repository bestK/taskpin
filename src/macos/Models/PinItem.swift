import Foundation

enum PinItemType: String, Codable {
    case url
    case lua
}

struct ParamEntry: Codable, Identifiable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
    var label: String = ""
    var paramType: String = "string"
}

struct PinItem: Codable, Identifiable {
    var id = UUID()
    var type: PinItemType = .lua
    var name: String = "Untitled"
    var intervalMs: Int = 5000

    var url: String = ""
    var reqHeaders: String = ""
    var fieldExpr: String = ""
    var clickEnabled: Bool = false
    var clickUrl: String = ""

    var luaPath: String = ""
    var params: [ParamEntry] = []

    var pinned: Bool = false
}
