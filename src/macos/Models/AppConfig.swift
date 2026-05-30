import Foundation

struct AppConfig: Codable {
    var items: [PinItem] = []
    var fontSize: Int = 12
    var fontColor: String = "FFFFFF"
    var bgColor: String = "1E1E1E"
    var scrollEnabled: Bool = true
    var sources: [String] = ["bestK/taskpin-plugins"]
}
