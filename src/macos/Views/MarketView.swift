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
    var configManager: ConfigManager
    @ObservedObject var projectManager: ProjectManager
    @State private var plugins: [PluginInfo] = []
    @State private var loading = false
    @State private var status = ""
    @State private var selectedSourceIndex: Int = 0
    @State private var newSource = ""
    @State private var searchText = ""
    private var filteredPlugins: [PluginInfo] {
        if searchText.isEmpty { return plugins }
        return plugins.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    private func isInstalled(_ plugin: PluginInfo) -> Bool {
        let dest = configManager.scriptsDir.appendingPathComponent(plugin.file).path
        return configManager.config.items.contains { $0.luaPath == dest }
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Divider().opacity(0.5)
            searchBar
            Divider().opacity(0.3)
            contentArea
            if !status.isEmpty { statusBar }
        }
        .onAppear { fetchPlugins() }
    }

    private var sourceBar: some View {
        HStack(spacing: 6) {
            if !configManager.config.sources.isEmpty {
                Picker("", selection: $selectedSourceIndex) {
                    ForEach(Array(configManager.config.sources.enumerated()), id: \.offset) { idx, src in
                        Text(src).tag(idx)
                    }
                }
                .frame(maxWidth: 160).controlSize(.small).labelsHidden()
                .onChange(of: selectedSourceIndex) { fetchPlugins() }
            }

            TextField("user/repo", text: $newSource)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: 120)
                .onSubmit { addSource() }

            Button { addSource() } label: { Image(systemName: "plus.circle.fill").font(.system(size: 12)) }
                .buttonStyle(.plain).foregroundColor(.accentColor).disabled(newSource.isEmpty)

            if !configManager.config.sources.isEmpty {
                Button { removeSource() } label: { Image(systemName: "minus.circle").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundColor(.red.opacity(0.7))
            }

            Spacer()

            if loading { ProgressView().controlSize(.small) }
            Button { fetchPlugins() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundColor(.secondary).disabled(loading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.secondary)
            TextField("Search plugins...", text: $searchText)
                .textFieldStyle(.plain).font(.system(size: 11))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var contentArea: some View {
        Group {
            if filteredPlugins.isEmpty && !loading {
                VStack(spacing: 12) {
                    Image(systemName: "bag").font(.system(size: 32, weight: .light))
                        .foregroundStyle(.linearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    Text(plugins.isEmpty ? "No plugins loaded" : "No results")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    Text("Select a source and refresh").font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredPlugins) { plugin in pluginCard(plugin) }
                    }.padding(12)
                }
            }
        }
    }

    private func pluginCard(_ plugin: PluginInfo) -> some View {
        let installed = isInstalled(plugin)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "puzzlepiece.fill").font(.system(size: 14)).foregroundColor(.accentColor.opacity(0.7)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(plugin.name).font(.system(size: 12, weight: .medium))
                    Text("v\(plugin.version)").font(.system(size: 9)).foregroundColor(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1)).clipShape(Capsule())
                }
                Text(plugin.description).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                if !plugin.author.isEmpty {
                    Text("by \(plugin.author)").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.7))
                }
            }
            Spacer()

            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundColor(.green)
            } else {
                Button("Install") { downloadPlugin(plugin) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    @ViewBuilder
    private var statusBar: some View {
        Divider().opacity(0.3)
        Text(status).font(.system(size: 10)).foregroundColor(.secondary).padding(.horizontal, 12).padding(.vertical, 5)
    }

    private func addSource() {
        let src = newSource.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty, !configManager.config.sources.contains(src) else { return }
        configManager.config.sources.append(src); configManager.save(); newSource = ""
        selectedSourceIndex = configManager.config.sources.count - 1; fetchPlugins()
    }

    private func removeSource() {
        guard selectedSourceIndex < configManager.config.sources.count else { return }
        configManager.config.sources.remove(at: selectedSourceIndex); configManager.save()
        selectedSourceIndex = max(0, selectedSourceIndex - 1)
    }

    private func fetchPlugins() {
        guard !configManager.config.sources.isEmpty, selectedSourceIndex < configManager.config.sources.count else { return }
        let source = configManager.config.sources[selectedSourceIndex]
        loading = true; status = ""

        let useProxy = Locale.current.region?.identifier == "CN"
        let prefix = useProxy ? "https://gh-proxy.com/" : ""
        let urlStr = "\(prefix)https://raw.githubusercontent.com/\(source)/master/manifest.json"
        guard let url = URL(string: urlStr) else { loading = false; return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { loading = false } }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let scripts = json["scripts"] as? [[String: Any]] else {
                DispatchQueue.main.async { status = "Failed to load manifest" }
                return
            }
            let items = scripts.compactMap { s -> PluginInfo? in
                guard let name = s["name"] as? String, let file = s["file"] as? String else { return nil }
                return PluginInfo(name: name, file: file, description: s["description"] as? String ?? "",
                                  author: s["author"] as? String ?? "", version: s["version"] as? String ?? "1.0")
            }
            DispatchQueue.main.async { plugins = items }
        }.resume()
    }

    private func downloadPlugin(_ plugin: PluginInfo) {
        guard selectedSourceIndex < configManager.config.sources.count else { return }
        let source = configManager.config.sources[selectedSourceIndex]
        let useProxy = Locale.current.region?.identifier == "CN"
        let prefix = useProxy ? "https://gh-proxy.com/" : ""
        let urlStr = "\(prefix)https://raw.githubusercontent.com/\(source)/master/\(plugin.file)"
        guard let url = URL(string: urlStr) else { return }

        status = "Downloading \(plugin.name)..."
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { DispatchQueue.main.async { status = "Download failed" }; return }
            let dest = configManager.scriptsDir.appendingPathComponent(plugin.file)
            try? data.write(to: dest)
            DispatchQueue.main.async {
                status = "Installed \(plugin.name)"
                var newItem = PinItem()
                newItem.type = .lua; newItem.name = plugin.name; newItem.luaPath = dest.path; newItem.pinned = true
                configManager.addItem(newItem)
                projectManager.startAll()
            }
        }.resume()
    }
}
