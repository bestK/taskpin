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
        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func isInstalled(_ plugin: PluginInfo) -> Bool {
        let dest = configManager.scriptsDir.appendingPathComponent(plugin.file).path
        return configManager.config.items.contains { $0.luaPath == dest }
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            Rectangle().fill(TP.surfacePressed).frame(height: 1)
            searchBar
            Rectangle().fill(TP.surfacePressed.opacity(0.6)).frame(height: 1)
            contentArea
            if !status.isEmpty {
                Rectangle().fill(TP.surfacePressed).frame(height: 1)
                statusBar
            }
        }
        .background(TP.canvas)
        .onAppear { fetchPlugins() }
    }

    private var sourceBar: some View {
        HStack(spacing: TP.sSM) {
            if !configManager.config.sources.isEmpty {
                Picker("", selection: $selectedSourceIndex) {
                    ForEach(Array(configManager.config.sources.enumerated()), id: \.offset) { idx, src in
                        Text(src).tag(idx)
                    }
                }
                .frame(maxWidth: 170)
                .controlSize(.small)
                .labelsHidden()
                .onChange(of: selectedSourceIndex) { fetchPlugins() }
            }

            SoftField(placeholder: "user/repo", text: $newSource)
                .frame(maxWidth: 130)
                .onSubmit { addSource() }

            Button { addSource() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TP.onPrimary)
                    .frame(width: 28, height: 28)
                    .background(newSource.isEmpty ? TP.mute : TP.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(newSource.isEmpty)

            if !configManager.config.sources.isEmpty {
                Button { removeSource() } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TP.ink)
                        .frame(width: 28, height: 28)
                        .background(TP.canvasSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if loading {
                ProgressView().controlSize(.small)
            }

            Button { fetchPlugins() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TP.ink)
                    .frame(width: 28, height: 28)
                    .background(TP.canvasSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(loading)
        }
        .padding(.horizontal, TP.sLG)
        .padding(.vertical, TP.sMD)
    }

    private var searchBar: some View {
        HStack(spacing: TP.sSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TP.body)
            TextField("Search plugins...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.tpBody(13))
                .foregroundColor(TP.ink)
        }
        .padding(.horizontal, TP.sLG)
        .padding(.vertical, TP.sMD)
        .background(TP.canvasSoft.opacity(0.5))
    }

    private var contentArea: some View {
        Group {
            if filteredPlugins.isEmpty && !loading {
                EmptyState(
                    icon: "bag",
                    title: plugins.isEmpty ? "No plugins loaded" : "No results",
                    message: plugins.isEmpty
                        ? "Select a source and refresh to browse community scripts."
                        : "Try a different search term."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: TP.sSM) {
                        ForEach(filteredPlugins) { plugin in
                            pluginCard(plugin)
                        }
                    }
                    .padding(TP.sLG)
                }
            }
        }
    }

    private func pluginCard(_ plugin: PluginInfo) -> some View {
        let installed = isInstalled(plugin)
        return HStack(spacing: TP.sMD) {
            ZStack {
                RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous)
                    .fill(TP.primary)
                    .frame(width: 36, height: 36)
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TP.onPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.tpBody(13, weight: .medium))
                        .foregroundColor(TP.ink)
                    Text("v\(plugin.version)")
                        .font(.tpCaption(10))
                        .foregroundColor(TP.body)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(TP.canvasSoft)
                        .clipShape(Capsule())
                }
                Text(plugin.description)
                    .font(.tpCaption(11))
                    .foregroundColor(TP.body)
                    .lineLimit(1)
                if !plugin.author.isEmpty {
                    Text("by \(plugin.author)")
                        .font(.tpCaption(10))
                        .foregroundColor(TP.mute)
                }
            }

            Spacer(minLength: 4)

            if installed {
                Chip(text: "Installed", active: true, icon: "checkmark")
            } else {
                PillButton(title: "Install", kind: .primary, compact: true) {
                    downloadPlugin(plugin)
                }
            }
        }
        .padding(TP.sMD)
        .background(TP.canvas)
        .clipShape(RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                .stroke(TP.surfacePressed, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBar: some View {
        Text(status)
            .font(.tpCaption(11))
            .foregroundColor(TP.body)
            .padding(.horizontal, TP.sLG)
            .padding(.vertical, TP.sSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TP.canvasSoft.opacity(0.5))
    }

    private func addSource() {
        let src = newSource.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty, !configManager.config.sources.contains(src) else { return }
        configManager.config.sources.append(src)
        configManager.save()
        newSource = ""
        selectedSourceIndex = configManager.config.sources.count - 1
        fetchPlugins()
    }

    private func removeSource() {
        guard selectedSourceIndex < configManager.config.sources.count else { return }
        configManager.config.sources.remove(at: selectedSourceIndex)
        configManager.save()
        selectedSourceIndex = max(0, selectedSourceIndex - 1)
    }

    private func fetchPlugins() {
        guard !configManager.config.sources.isEmpty,
              selectedSourceIndex < configManager.config.sources.count else { return }
        let source = configManager.config.sources[selectedSourceIndex]
        loading = true
        status = ""

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
                return PluginInfo(
                    name: name,
                    file: file,
                    description: s["description"] as? String ?? "",
                    author: s["author"] as? String ?? "",
                    version: s["version"] as? String ?? "1.0"
                )
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
            guard let data = data else {
                DispatchQueue.main.async { status = "Download failed" }
                return
            }
            let dest = configManager.scriptsDir.appendingPathComponent(plugin.file)
            try? data.write(to: dest)
            DispatchQueue.main.async {
                status = "Installed \(plugin.name)"
                var newItem = PinItem()
                newItem.type = .lua
                newItem.name = plugin.name
                newItem.luaPath = dest.path
                newItem.pinned = true
                configManager.addItem(newItem)
                projectManager.startAll()
            }
        }.resume()
    }
}
