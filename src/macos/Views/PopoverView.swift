import SwiftUI

struct PopoverView: View {
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        let pinnedItems = configManager.config.items.filter { $0.pinned }

        if pinnedItems.isEmpty {
            emptyView
        } else {
            VStack(spacing: 0) {
                if pinnedItems.count > 1 {
                    pinnedPicker(pinnedItems)
                    Divider().opacity(0.3)
                }
                dialogContent
            }
        }
    }

    private func pinnedPicker(_ items: [PinItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            projectManager.activeItemId = item.id
                        }
                    } label: {
                        Text(item.name)
                            .font(.system(size: 10, weight: projectManager.activeItemId == item.id ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(projectManager.activeItemId == item.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                            .foregroundColor(projectManager.activeItemId == item.id ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var dialogContent: some View {
        let items = projectManager.activeState.dialogItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading...").font(.system(size: 11)).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in dialogItemView(item) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func dialogItemView(_ item: DialogItemModel) -> some View {
        switch item.kind {
        case .text:
            HStack(spacing: 6) {
                if let img = item.image {
                    Image(nsImage: img).resizable().frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
                }
                Text(item.text)
                    .font(.system(size: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular))
                    .foregroundColor(item.color)
            }
        case .hr:
            Divider().padding(.vertical, 4)
        case .button:
            Button(item.text) { projectManager.handleButtonClick(item) }
                .buttonStyle(.bordered).controlSize(.small)
        case .image:
            if let img = item.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
            }
        case .table:
            TableItemView(item: item)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "pin.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.linearGradient(
                    colors: [.orange.opacity(0.6), .red.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            VStack(spacing: 4) {
                Text("No Pinned Items").font(.system(size: 14, weight: .semibold)).foregroundColor(.primary.opacity(0.8))
                Text("Pin items in the Items tab to see output here")
                    .font(.system(size: 11)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TableItemView: View {
    let item: DialogItemModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(item.columns.enumerated()), id: \.offset) { _, col in
                    Text(col).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)
            .background(.regularMaterial)

            ForEach(Array(item.rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                    }
                    if let url = row.url {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 9))
                        }.buttonStyle(.borderless).foregroundColor(.accentColor).padding(.trailing, 8)
                    }
                }
                .padding(.vertical, 5)
                .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}
