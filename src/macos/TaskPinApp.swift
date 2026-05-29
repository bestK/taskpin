import SwiftUI

@main
struct TaskPinApp: App {
    @StateObject private var engine = ScriptEngine()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(engine: engine)
        } label: {
            StatusBarView(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
