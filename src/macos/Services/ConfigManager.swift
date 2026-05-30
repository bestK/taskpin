import Foundation
import Observation

@Observable
final class ConfigManager {
    static let shared = ConfigManager()

    var config: AppConfig = AppConfig()

    private let configDir: URL
    private let configFile: URL
    let scriptsDir: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".taskpin")
        configFile = configDir.appendingPathComponent("config.json")
        scriptsDir = configDir.appendingPathComponent("scripts")
    }

    func load() {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        guard let data = try? Data(contentsOf: configFile) else { return }
        if let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configFile, options: .atomic)
    }

    func addItem(_ item: PinItem) {
        config.items.append(item)
        save()
    }

    func removeItem(id: UUID) {
        config.items.removeAll { $0.id == id }
        save()
    }

    func updateItem(_ item: PinItem) {
        if let idx = config.items.firstIndex(where: { $0.id == item.id }) {
            config.items[idx] = item
            save()
        }
    }
}
