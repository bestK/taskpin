import SwiftUI

struct ItemEditView: View {
    @State var item: PinItem
    @ObservedObject var projectManager: ProjectManager
    var onSave: (PinItem) -> Void
    var onCancel: () -> Void
    @State private var showFilePicker = false
    @State private var testResult = ""
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            formContent
            Divider().opacity(0.5)
            footer
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.init(filenameExtension: "lua")!],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                item.luaPath = url.path
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: item.type == .lua ? "chevron.left.forwardslash.chevron.right" : "globe")
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
            Text(item.name.isEmpty ? "New Item" : item.name)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var formContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                generalCard
                sourceCard
                if item.type == .url { clickCard }
                testResultCard
            }
            .padding(16)
        }
    }

    private var generalCard: some View {
        CardView {
            FormRow("Name") { TextField("Item name", text: $item.name).textFieldStyle(.plain).font(.system(size: 12)) }
            Divider().opacity(0.3)
            FormRow("Type") {
                Picker("", selection: $item.type) {
                    Text("Lua").tag(PinItemType.lua)
                    Text("URL").tag(PinItemType.url)
                }.pickerStyle(.segmented).frame(maxWidth: 160).labelsHidden()
            }
            Divider().opacity(0.3)
            FormRow("Interval") {
                HStack(spacing: 4) {
                    TextField("", value: $item.intervalMs, format: .number).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 60)
                    Text("ms").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Divider().opacity(0.3)
            FormRow("Pinned") { Toggle("", isOn: $item.pinned).toggleStyle(.switch).controlSize(.mini).labelsHidden() }
        }
    }

    @ViewBuilder
    private var sourceCard: some View {
        if item.type == .lua {
            CardView {
                FormRow("Script") {
                    HStack(spacing: 6) {
                        Text(item.luaPath.isEmpty ? "No file" : (item.luaPath as NSString).lastPathComponent)
                            .font(.system(size: 11)).foregroundColor(item.luaPath.isEmpty ? .secondary : .primary).lineLimit(1)
                        Spacer()
                        Button("Browse") { showFilePicker = true }.controlSize(.small)
                    }
                }
                if !item.params.isEmpty {
                    Divider().opacity(0.3)
                    ForEach($item.params) { $param in
                        FormRow(param.label.isEmpty ? param.key : param.label) {
                            TextField("value", text: $param.value).textFieldStyle(.plain).font(.system(size: 11))
                        }
                    }
                }
                Divider().opacity(0.3)
                HStack {
                    Spacer()
                    Button { runTest() } label: {
                        Label(isTesting ? "Running..." : "Test", systemImage: "play.fill").font(.system(size: 10, weight: .medium))
                    }.controlSize(.small).disabled(item.luaPath.isEmpty || isTesting)
                }
            }
        } else {
            CardView {
                FormRow("URL") { TextField("https://...", text: $item.url).textFieldStyle(.plain).font(.system(size: 11)) }
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Headers").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    TextEditor(text: $item.reqHeaders).font(.system(size: 10, design: .monospaced)).frame(height: 40)
                        .scrollContentBackground(.hidden).padding(4).background(Color.black.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expression").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                    TextEditor(text: $item.fieldExpr).font(.system(size: 10, design: .monospaced)).frame(height: 40)
                        .scrollContentBackground(.hidden).padding(4).background(Color.black.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Divider().opacity(0.3)
                HStack {
                    Spacer()
                    Button { runTest() } label: {
                        Label(isTesting ? "Testing..." : "Test", systemImage: "paperplane.fill").font(.system(size: 10, weight: .medium))
                    }.controlSize(.small).disabled(item.url.isEmpty || isTesting)
                }
            }
        }
    }

    private var clickCard: some View {
        CardView {
            FormRow("Click URL") {
                HStack(spacing: 6) {
                    Toggle("", isOn: $item.clickEnabled).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    TextField("https://...", text: $item.clickUrl).textFieldStyle(.plain).font(.system(size: 11))
                        .disabled(!item.clickEnabled).opacity(item.clickEnabled ? 1 : 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private var testResultCard: some View {
        if !testResult.isEmpty {
            Text(testResult)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel") { onCancel() }.controlSize(.small)
            Spacer()
            Button { onSave(item) } label: { Text("Save").font(.system(size: 11, weight: .medium)) }
                .controlSize(.small).buttonStyle(.borderedProminent).disabled(item.name.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func runTest() {
        isTesting = true; testResult = ""
        if item.type == .lua {
            guard !item.luaPath.isEmpty else { isTesting = false; return }
            LuaExecutor.shared.executeFile(path: item.luaPath, argsJson: nil) { result in
                isTesting = false
                testResult = result?.statusText.isEmpty == false ? result!.statusText : (result == nil ? "Error" : "(no output)")
            }
        } else {
            guard let url = URL(string: item.url) else { isTesting = false; testResult = "Invalid URL"; return }
            URLSession.shared.dataTask(with: url) { data, _, err in
                DispatchQueue.main.async {
                    isTesting = false
                    if let err = err { testResult = "Error: \(err.localizedDescription)" }
                    else if let data = data, let s = String(data: data, encoding: .utf8) { testResult = String(s.prefix(300)) }
                    else { testResult = "Empty response" }
                }
            }.resume()
        }
    }
}

private struct CardView<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }
    var body: some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            content
        }
    }
}
