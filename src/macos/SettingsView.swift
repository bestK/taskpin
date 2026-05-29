import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var engine: ScriptEngine
    @State private var showFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TaskPin Settings")
                .font(.headline)

            Divider()

            HStack {
                Text("Script:")
                    .frame(width: 50, alignment: .leading)
                Text(engine.scriptPath ?? "None")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Browse") { showFilePicker = true }
            }

            HStack {
                Text("Interval:")
                    .frame(width: 50, alignment: .leading)
                Text("\(engine.refreshInterval)s")
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Button("Reload") { engine.executeScript() }
                Button("Clear") { engine.loadScript(nil) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 350)
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.init(filenameExtension: "lua")!],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                engine.loadScript(url.path)
            }
        }
    }
}
