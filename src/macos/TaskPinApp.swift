import SwiftUI
import Observation

@Observable
final class SharedState {
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
        let sbm = statusBarManager
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            sbm.rebuildAll()
        }
    }
}

@main
struct TaskPinApp: App {
    private var state = SharedState.shared

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

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                tabBar
                Divider().opacity(0.5)
                ZStack {
                    PopoverView(projectManager: state.projectManager, configManager: state.configManager)
                        .opacity(selectedTab == .status ? 1 : 0)
                        .allowsHitTesting(selectedTab == .status)
                    ItemsListView(configManager: state.configManager, projectManager: state.projectManager)
                        .opacity(selectedTab == .items ? 1 : 0)
                        .allowsHitTesting(selectedTab == .items)
                    SettingsView(configManager: state.configManager)
                        .opacity(selectedTab == .settings ? 1 : 0)
                        .allowsHitTesting(selectedTab == .settings)
                    MarketView(configManager: state.configManager, projectManager: state.projectManager)
                        .opacity(selectedTab == .market ? 1 : 0)
                        .allowsHitTesting(selectedTab == .market)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 440, height: 520)
            .background(.ultraThinMaterial)
        } label: {
            Image(systemName: "pin.fill")
                .font(.system(size: 11))
        }
        .menuBarExtraStyle(.window)
    }

    @State private var hoveredTab: AppTab? = nil

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                let isHovered = hoveredTab == tab

                VStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    Text(tab.rawValue)
                        .font(.system(size: 9, weight: isSelected ? .medium : .regular))
                }
                .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.primary.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { selectedTab = tab }
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.1)) { hoveredTab = h ? tab : nil }
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}
