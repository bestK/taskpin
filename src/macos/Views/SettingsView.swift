import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var configManager: ConfigManager
    @State private var fontColor: Color = .white
    @State private var bgColor: Color = .black

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: TP.sLG) {
                SoftCard {
                    VStack(alignment: .leading, spacing: TP.sMD) {
                        SectionLabel(text: "Display")

                        settingsRow("Font size") {
                            Stepper(
                                "\(configManager.config.fontSize) pt",
                                value: $configManager.config.fontSize,
                                in: 8...24
                            )
                            .font(.tpBody(12))
                            .controlSize(.small)
                            .onChange(of: configManager.config.fontSize) { configManager.save() }
                        }

                        hairline

                        settingsRow("Font color") {
                            ColorPicker("", selection: $fontColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: fontColor) {
                                    configManager.config.fontColor = fontColor.hexString
                                    configManager.save()
                                }
                        }

                        hairline

                        settingsRow("Background") {
                            ColorPicker("", selection: $bgColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: bgColor) {
                                    configManager.config.bgColor = bgColor.hexString
                                    configManager.save()
                                }
                        }
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: TP.sMD) {
                        SectionLabel(text: "Behavior")
                        settingsRow("Auto scroll") {
                            Toggle("", isOn: $configManager.config.scrollEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .onChange(of: configManager.config.scrollEnabled) { configManager.save() }
                        }
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: TP.sMD) {
                        SectionLabel(text: "System")
                        settingsRow("Launch at login") {
                            Toggle("", isOn: Binding(
                                get: { SMAppService.mainApp.status == .enabled },
                                set: { v in
                                    if v { try? SMAppService.mainApp.register() }
                                    else { try? SMAppService.mainApp.unregister() }
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                    }
                }

                SoftCard {
                    VStack(alignment: .leading, spacing: TP.sMD) {
                        SectionLabel(text: "About")
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TaskPin")
                                    .font(.tpBody(13, weight: .medium))
                                    .foregroundColor(TP.ink)
                                Text("v1.0.0")
                                    .font(.tpCaption(11))
                                    .foregroundColor(TP.body)
                            }
                            Spacer()
                            PillButton(title: "GitHub", icon: "arrow.up.right", kind: .secondary, compact: true) {
                                NSWorkspace.shared.open(URL(string: "https://github.com/bestK/taskpin")!)
                            }
                        }
                    }
                }

                SoftCard {
                    HStack {
                        Spacer()
                        PillButton(title: "Quit TaskPin", icon: "power", kind: .danger, compact: true) {
                            NSApp.terminate(nil)
                        }
                        Spacer()
                    }
                }
            }
            .padding(TP.sLG)
        }
        .background(TP.canvas)
        .onAppear { loadColors() }
    }

    private var hairline: some View {
        Rectangle()
            .fill(TP.surfacePressed)
            .frame(height: 1)
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.tpBody(13))
                .foregroundColor(TP.ink)
            Spacer()
            content()
        }
    }

    private func loadColors() {
        fontColor = Color(hex: configManager.config.fontColor) ?? .white
        bgColor = Color(hex: configManager.config.bgColor) ?? .black
    }
}
