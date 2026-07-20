import SwiftUI

struct ItemEditView: View {
    @State var item: PinItem
    @ObservedObject var projectManager: ProjectManager
    var onSave: (PinItem) -> Void
    var onCancel: () -> Void
    @State private var showFilePicker = false
    @State private var testResult = ""
    @State private var isTesting = false

    init(item: PinItem, projectManager: ProjectManager, onSave: @escaping (PinItem) -> Void, onCancel: @escaping () -> Void) {
        var parsed = item
        if item.type == .lua && !item.luaPath.isEmpty && item.params.isEmpty {
            if let content = try? String(contentsOfFile: item.luaPath, encoding: .utf8) {
                var params: [ParamEntry] = []
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("-- @param ") else {
                        if !trimmed.hasPrefix("--") { break }
                        continue
                    }
                    let parts = String(trimmed.dropFirst("-- @param ".count)).components(separatedBy: " ")
                    guard parts.count >= 2 else { continue }
                    params.append(ParamEntry(
                        key: parts[0],
                        value: "",
                        label: parts.count >= 3 ? parts[2...].joined(separator: " ") : parts[0],
                        paramType: parts[1]
                    ))
                }
                if !params.isEmpty { parsed.params = params }
            }
        }
        _item = State(initialValue: parsed)
        self.projectManager = projectManager
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(TP.surfacePressed).frame(height: 1)
            formContent
            Rectangle().fill(TP.surfacePressed).frame(height: 1)
            footer
        }
        .background(TP.canvas)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.init(filenameExtension: "lua")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                item.luaPath = url.path
                parseParams(from: url.path)
            }
        }
    }

    private func parseParams(from path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var params: [ParamEntry] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-- @param ") else {
                if !trimmed.hasPrefix("--") { break }
                continue
            }
            let parts = trimmed.dropFirst("-- @param ".count).components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let paramType = parts[1]
            let label = parts.count >= 3 ? parts[2...].joined(separator: " ") : key
            let existing = item.params.first { $0.key == key }
            params.append(ParamEntry(key: key, value: existing?.value ?? "", label: label, paramType: paramType))
        }
        item.params = params
    }

    private var header: some View {
        HStack(spacing: TP.sMD) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TP.ink)
                    .frame(width: 28, height: 28)
                    .background(TP.canvasSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name.isEmpty ? "New signal" : item.name)
                    .font(.tpDisplay(15))
                    .foregroundColor(TP.ink)
                Text(item.type == .lua ? "Lua script" : "HTTP endpoint")
                    .font(.tpCaption(11))
                    .foregroundColor(TP.body)
            }
            Spacer()
        }
        .padding(.horizontal, TP.sLG)
        .padding(.vertical, TP.sMD)
    }

    private var formContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: TP.sLG) {
                generalCard
                sourceCard
                if item.type == .url { clickCard }
                testResultCard
            }
            .padding(TP.sLG)
        }
    }

    private var generalCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: TP.sMD) {
                SectionLabel(text: "General")

                VStack(alignment: .leading, spacing: TP.sXS) {
                    Text("Name")
                        .font(.tpBody(12, weight: .medium))
                        .foregroundColor(TP.body)
                    SoftField(placeholder: "Signal name", text: $item.name)
                }

                HStack(spacing: TP.sMD) {
                    VStack(alignment: .leading, spacing: TP.sXS) {
                        Text("Type")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(TP.body)
                        HStack(spacing: TP.sXS) {
                            typePill("Lua", selected: item.type == .lua) { item.type = .lua }
                            typePill("URL", selected: item.type == .url) { item.type = .url }
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: TP.sXS) {
                        Text("Interval (ms)")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(TP.body)
                        SoftField(
                            placeholder: "5000",
                            text: Binding(
                                get: { String(item.intervalMs) },
                                set: { item.intervalMs = Int($0) ?? item.intervalMs }
                            )
                        )
                        .frame(width: 110)
                    }
                }

                HStack {
                    Text("Pin to menu bar")
                        .font(.tpBody(12, weight: .medium))
                        .foregroundColor(TP.body)
                    Spacer()
                    Button {
                        item.pinned.toggle()
                    } label: {
                        Text(item.pinned ? "Live" : "Idle")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(item.pinned ? TP.onPrimary : TP.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(item.pinned ? TP.primary : TP.canvas)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func typePill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.tpBody(12, weight: .medium))
                .foregroundColor(selected ? TP.onPrimary : TP.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? TP.primary : TP.canvas)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sourceCard: some View {
        if item.type == .lua {
            SoftCard {
                VStack(alignment: .leading, spacing: TP.sMD) {
                    SectionLabel(text: "Script")

                    HStack(spacing: TP.sSM) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TP.body)
                        Text(item.luaPath.isEmpty ? "No file selected" : (item.luaPath as NSString).lastPathComponent)
                            .font(.tpBody(12))
                            .foregroundColor(item.luaPath.isEmpty ? TP.mute : TP.ink)
                            .lineLimit(1)
                        Spacer()
                        PillButton(title: "Browse", kind: .secondary, compact: true) {
                            showFilePicker = true
                        }
                    }
                    .padding(TP.sMD)
                    .background(TP.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))

                    if !item.params.isEmpty {
                        SectionLabel(text: "Parameters")
                        ForEach($item.params) { $param in
                            VStack(alignment: .leading, spacing: TP.sXS) {
                                Text(param.label.isEmpty ? param.key : param.label)
                                    .font(.tpBody(12, weight: .medium))
                                    .foregroundColor(TP.body)
                                if param.paramType == "file" {
                                    HStack {
                                        Text(param.value.isEmpty ? "No file" : (param.value as NSString).lastPathComponent)
                                            .font(.tpBody(12))
                                            .foregroundColor(param.value.isEmpty ? TP.mute : TP.ink)
                                            .lineLimit(1)
                                        Spacer()
                                        PillButton(title: "Browse", kind: .secondary, compact: true) {
                                            let panel = NSOpenPanel()
                                            panel.canChooseFiles = true
                                            panel.canChooseDirectories = false
                                            if panel.runModal() == .OK, let url = panel.url {
                                                param.value = url.path
                                            }
                                        }
                                    }
                                    .padding(TP.sMD)
                                    .background(TP.canvas)
                                    .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))
                                } else {
                                    SoftField(placeholder: "value", text: $param.value)
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        PillButton(
                            title: isTesting ? "Running..." : "Test",
                            icon: "play.fill",
                            kind: .primary,
                            compact: true
                        ) {
                            runTest()
                        }
                        .disabled(item.luaPath.isEmpty || isTesting)
                        .opacity(item.luaPath.isEmpty || isTesting ? 0.5 : 1)
                    }
                }
            }
        } else {
            SoftCard {
                VStack(alignment: .leading, spacing: TP.sMD) {
                    SectionLabel(text: "Endpoint")

                    VStack(alignment: .leading, spacing: TP.sXS) {
                        Text("URL")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(TP.body)
                        SoftField(placeholder: "https://...", text: $item.url)
                    }

                    VStack(alignment: .leading, spacing: TP.sXS) {
                        Text("Headers")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(TP.body)
                        TextEditor(text: $item.reqHeaders)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 48)
                            .scrollContentBackground(.hidden)
                            .padding(TP.sSM)
                            .background(TP.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: TP.sXS) {
                        Text("Expression")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(TP.body)
                        TextEditor(text: $item.fieldExpr)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 48)
                            .scrollContentBackground(.hidden)
                            .padding(TP.sSM)
                            .background(TP.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))
                    }

                    HStack {
                        Spacer()
                        PillButton(
                            title: isTesting ? "Testing..." : "Test",
                            icon: "paperplane.fill",
                            kind: .primary,
                            compact: true
                        ) {
                            runTest()
                        }
                        .disabled(item.url.isEmpty || isTesting)
                        .opacity(item.url.isEmpty || isTesting ? 0.5 : 1)
                    }
                }
            }
        }
    }

    private var clickCard: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: TP.sMD) {
                SectionLabel(text: "Click action")
                HStack(spacing: TP.sSM) {
                    Button {
                        item.clickEnabled.toggle()
                    } label: {
                        Text(item.clickEnabled ? "On" : "Off")
                            .font(.tpBody(12, weight: .medium))
                            .foregroundColor(item.clickEnabled ? TP.onPrimary : TP.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(item.clickEnabled ? TP.primary : TP.canvas)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    SoftField(placeholder: "https://...", text: $item.clickUrl)
                        .disabled(!item.clickEnabled)
                        .opacity(item.clickEnabled ? 1 : 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private var testResultCard: some View {
        if !testResult.isEmpty {
            SoftCard(fill: TP.canvas) {
                VStack(alignment: .leading, spacing: TP.sXS) {
                    SectionLabel(text: "Test result")
                    Text(testResult)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TP.body)
                        .textSelection(.enabled)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                    .stroke(TP.surfacePressed, lineWidth: 1)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: TP.sMD) {
            PillButton(title: "Cancel", kind: .subtle, compact: true) {
                onCancel()
            }
            Spacer()
            PillButton(title: "Save", kind: .primary, compact: true) {
                onSave(item)
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        }
        .padding(.horizontal, TP.sLG)
        .padding(.vertical, TP.sMD)
        .background(TP.canvas)
    }

    private var canSave: Bool {
        !item.name.isEmpty
            && (item.type == .lua ? !item.luaPath.isEmpty : !item.url.isEmpty)
    }

    private func runTest() {
        isTesting = true
        testResult = ""
        if item.type == .lua {
            guard !item.luaPath.isEmpty else { isTesting = false; return }
            LuaExecutor.shared.executeFile(path: item.luaPath, argsJson: nil) { result in
                isTesting = false
                testResult = result?.statusText.isEmpty == false
                    ? result!.statusText
                    : (result == nil ? "Error" : "(no output)")
            }
        } else {
            guard let url = URL(string: item.url) else {
                isTesting = false
                testResult = "Invalid URL"
                return
            }
            URLSession.shared.dataTask(with: url) { data, _, err in
                DispatchQueue.main.async {
                    isTesting = false
                    if let err = err {
                        testResult = "Error: \(err.localizedDescription)"
                    } else if let data = data, let s = String(data: data, encoding: .utf8) {
                        testResult = String(s.prefix(300))
                    } else {
                        testResult = "Empty response"
                    }
                }
            }.resume()
        }
    }
}
