import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var configManager: ConfigManager
    @State private var fontColor: Color = .white
    @State private var bgColor: Color = .black

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Display")
                settingsCard {
                    HStack {
                        Text("Font Size").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Stepper("\(configManager.config.fontSize) pt", value: $configManager.config.fontSize, in: 8...24)
                            .font(.system(size: 11)).controlSize(.small)
                            .onChange(of: configManager.config.fontSize) { configManager.save() }
                    }
                    Divider().opacity(0.3)
                    HStack {
                        Text("Font Color").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        ColorPicker("", selection: $fontColor, supportsOpacity: false).labelsHidden()
                            .onChange(of: fontColor) { configManager.config.fontColor = fontColor.hexString; configManager.save() }
                    }
                    Divider().opacity(0.3)
                    HStack {
                        Text("Background").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        ColorPicker("", selection: $bgColor, supportsOpacity: false).labelsHidden()
                            .onChange(of: bgColor) { configManager.config.bgColor = bgColor.hexString; configManager.save() }
                    }
                }

                sectionHeader("Behavior")
                settingsCard {
                    HStack {
                        Text("Auto Scroll").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $configManager.config.scrollEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                            .onChange(of: configManager.config.scrollEnabled) { configManager.save() }
                    }
                }

                sectionHeader("System")
                settingsCard {
                    HStack {
                        Text("Launch at Login").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { SMAppService.mainApp.status == .enabled },
                            set: { v in if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
                        )).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                }

                sectionHeader("About")
                settingsCard {
                    HStack {
                        Text("TaskPin").font(.system(size: 11, weight: .medium))
                        Text("v1.0.0").font(.system(size: 10)).foregroundColor(.secondary)
                        Spacer()
                        Button { NSWorkspace.shared.open(URL(string: "https://github.com/bestK/taskpin")!) } label: {
                            Label("GitHub", systemImage: "arrow.up.right.square").font(.system(size: 10))
                        }.buttonStyle(.plain).foregroundColor(.accentColor)
                    }
                }

                settingsCard {
                    HStack {
                        Spacer()
                        Button(role: .destructive) { NSApp.terminate(nil) } label: {
                            Label("Quit TaskPin", systemImage: "power").font(.system(size: 11, weight: .medium))
                        }.controlSize(.small)
                    }
                }
            }
            .padding(16)
        }
        .onAppear { loadColors() }
    }

    private func loadColors() {
        fontColor = Color(hex: configManager.config.fontColor) ?? .white
        bgColor = Color(hex: configManager.config.bgColor) ?? .black
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).textCase(.uppercase)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

extension Color {
    init?(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255, blue: Double(val & 0xFF) / 255)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
