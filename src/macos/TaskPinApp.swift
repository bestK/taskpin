import SwiftUI

@main
struct TaskPinApp: App {
    @StateObject private var engine = ScriptEngine()

    var body: some Scene {
        MenuBarExtra {
            TabView {
                PopoverView(engine: engine)
                    .tabItem { Label("Status", systemImage: "gauge") }
                SettingsView(engine: engine)
                    .tabItem { Label("Settings", systemImage: "gear") }
                MarketView(engine: engine)
                    .tabItem { Label("Market", systemImage: "bag") }
            }
            .frame(width: 420, height: 360)
        } label: {
            StatusBarView(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
