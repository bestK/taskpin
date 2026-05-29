import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: ScriptEngine

    var body: some View {
        HStack(spacing: 4) {
            if let image = engine.statusImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            if !engine.statusText.isEmpty {
                Text(engine.statusText)
                    .font(.system(size: 12))
                    .foregroundColor(engine.statusColor)
            }
        }
    }
}
