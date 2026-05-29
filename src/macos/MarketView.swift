import SwiftUI

struct PluginInfo: Identifiable {
    let id = UUID()
    let name: String
    let file: String
    let description: String
    let author: String
    let version: String
}

struct MarketView: View {
    @ObservedObject var engine: ScriptEngine
    @State private var plugins: [PluginInfo] = []
    @State private var loading = false
    @State private var status = ""

    let source = "bestK/taskpin-plugins"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plugin Market")
                    .font(.headline)
                Spacer()
                Button("Refresh") { fetchPlugins() }
                    .disabled(loading)
            }

            Divider()

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if plugins.isEmpty {
                Text("No plugins loaded. Click Refresh.")
                    .foregroundColor(.secondary)
            } else {
                List(plugins) { plugin in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(plugin.description)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("v\(plugin.version)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Button("Install") { downloadPlugin(plugin) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 420, height: 320)
        .onAppear { fetchPlugins() }
    }

    private func fetchPlugins() {
        loading = true
        status = ""
        let urlStr = "https://raw.githubusercontent.com/\(source)/master/manifest.json"
        guard let url = URL(string: urlStr) else { loading = false; return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            defer { DispatchQueue.main.async { loading = false } }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let scripts = json["scripts"] as? [[String: Any]] else {
                DispatchQueue.main.async { status = "Failed to load" }
                return
            }
            let items = scripts.compactMap { s -> PluginInfo? in
                guard let name = s["name"] as? String,
                      let file = s["file"] as? String else { return nil }
                return PluginInfo(
                    name: name, file: file,
                    description: s["description"] as? String ?? "",
                    author: s["author"] as? String ?? "",
                    version: s["version"] as? String ?? "1.0"
                )
            }
            DispatchQueue.main.async { plugins = items }
        }.resume()
    }

    private func downloadPlugin(_ plugin: PluginInfo) {
        let urlStr = "https://raw.githubusercontent.com/\(source)/master/\(plugin.file)"
        guard let url = URL(string: urlStr) else { return }

        status = "Downloading \(plugin.name)..."
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { status = "Download failed" }
                return
            }
            let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".taskpin/scripts")
            try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
            let dest = scriptsDir.appendingPathComponent(plugin.file)
            try? data.write(to: dest)
            DispatchQueue.main.async {
                status = "Installed: \(plugin.file)"
                engine.loadScript(dest.path)
            }
        }.resume()
    }
}
