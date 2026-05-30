import SwiftUI

class SharedState: ObservableObject {
    static let shared = SharedState()

    let configManager: ConfigManager
    let projectManager: ProjectManager
    let statusBarManager: StatusBarManager

    private init() {
        configManager = ConfigManager.shared
        configManager.load()
        LuaExecutor.shared.initialize()
        projectManager = ProjectManager(configManager: configManager)
        statusBarManager = StatusBarManager(projectManager: projectManager, configManager: configManager)
        projectManager.startAll()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak statusBarManager] _ in
            statusBarManager?.rebuildAll()
        }
    }

    func bootstrap() {}
}

@main
struct TaskPinApp: App {
    @ObservedObject private var state = SharedState.shared

    init() {
        _ = SharedState.shared
    }

    enum AppTab: String, CaseIterable {
        case status = "Status"
        case items = "Items"
        case settings = "Settings"
        case market = "Market"

        var icon: String {
            switch self {
            case .status: return "gauge.open.with.lines.needle.33percent"
            case .items: return "list.bullet.rectangle"
            case .settings: return "gearshape"
            case .market: return "bag"
            }
        }
    }

    @State private var selectedTab: AppTab = .status
    @State private var didBootstrap = false

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                tabBar
                Divider().opacity(0.5)
                Group {
                    switch selectedTab {
                    case .status:
                        PopoverView(projectManager: state.projectManager, configManager: state.configManager)
                    case .items:
                        ItemsListView(configManager: state.configManager, projectManager: state.projectManager)
                    case .settings:
                        SettingsView(configManager: state.configManager)
                    case .market:
                        MarketView(configManager: state.configManager, projectManager: state.projectManager)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: selectedTab)
            }
            .frame(width: 440, height: 520)
            .background(.ultraThinMaterial)
        } label: {
            Image(systemName: "pin.fill")
                .font(.system(size: 11))
                .onAppear {
                    if !didBootstrap {
                        didBootstrap = true
                        state.bootstrap()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: selectedTab == tab ? .medium : .regular))
                    }
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}
