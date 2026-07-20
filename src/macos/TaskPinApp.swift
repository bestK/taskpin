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

    enum AppTab: String, CaseIterable, Hashable, Identifiable {
        case status = "Status"
        case items = "Items"
        case market = "Market"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .status: return "dot.radiowaves.left.and.right"
            case .items: return "square.stack.3d.up"
            case .market: return "bag"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedTab: AppTab = .status

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                header
                tabBar
                Rectangle()
                    .fill(TP.surfacePressed)
                    .frame(height: 1)

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
            }
            .frame(width: 460, height: 560)
            .background(TP.canvas)
        } label: {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuBarExtraStyle(.window)
    }

    private var header: some View {
        HStack(spacing: TP.sMD) {
            ZStack {
                RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous)
                    .fill(TP.primary)
                    .frame(width: 28, height: 28)
                Text("TP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TP.onPrimary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("TaskPin")
                    .font(.tpDisplay(15))
                    .foregroundColor(TP.ink)
                Text("Pin live signals to your menu bar")
                    .font(.tpCaption(11))
                    .foregroundColor(TP.body)
            }

            Spacer()

            let live = state.configManager.config.items.filter(\.pinned).count
            Chip(text: "\(live) live", active: live > 0, icon: live > 0 ? "circle.fill" : nil)
        }
        .padding(.horizontal, TP.sLG)
        .padding(.top, TP.sLG)
        .padding(.bottom, TP.sSM)
    }

    private var tabBar: some View {
        HStack(spacing: TP.sXS) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, TP.sLG)
        .padding(.bottom, TP.sMD)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                Text(tab.rawValue)
                    .font(.tpBody(12, weight: selected ? .medium : .regular))
            }
            .foregroundColor(selected ? TP.onPrimary : TP.ink)
            .padding(.horizontal, TP.sMD)
            .padding(.vertical, TP.sSM)
            .frame(maxWidth: .infinity)
            .background(selected ? TP.primary : TP.canvasSoft)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
