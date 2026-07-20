import SwiftUI

struct PopoverView: View {
    @ObservedObject var projectManager: ProjectManager
    var configManager: ConfigManager

    var body: some View {
        let pinnedItems = configManager.config.items.filter(\.pinned)

        if pinnedItems.isEmpty {
            EmptyState(
                icon: "pin.slash",
                title: "No live signals",
                message: "Pin items in the Items tab to see their output here."
            )
        } else {
            VStack(spacing: 0) {
                if pinnedItems.count > 1 {
                    pinnedPicker(pinnedItems)
                    Rectangle().fill(TP.surfacePressed).frame(height: 1)
                }
                dialogContent
            }
            .background(TP.canvas)
        }
    }

    private func pinnedPicker(_ items: [PinItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TP.sXS) {
                ForEach(items) { item in
                    let selected = projectManager.activeItemId == item.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            projectManager.activeItemId = item.id
                        }
                    } label: {
                        Text(item.name)
                            .font(.tpBody(12, weight: selected ? .medium : .regular))
                            .foregroundColor(selected ? TP.onPrimary : TP.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? TP.primary : TP.canvasSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TP.sLG)
            .padding(.vertical, TP.sMD)
        }
    }

    private var dialogContent: some View {
        let state = projectManager.activeState
        let items = state.dialogItems
        return Group {
            if items.isEmpty && !state.isRunning {
                VStack(spacing: TP.sMD) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.tpBody(12))
                        .foregroundColor(TP.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && state.isRunning {
                VStack(spacing: TP.sSM) {
                    Text(state.statusText.isEmpty ? "No dialog content" : state.statusText)
                        .font(.tpBody(13))
                        .foregroundColor(TP.ink)
                    if let err = state.lastError {
                        Text(err)
                            .font(.tpCaption(11))
                            .foregroundColor(TP.danger)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: TP.sSM) {
                        ForEach(items) { item in
                            dialogItemView(item)
                        }
                    }
                    .padding(TP.sLG)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func dialogItemView(_ item: DialogItemModel) -> some View {
        switch item.kind {
        case .text:
            HStack(spacing: TP.sSM) {
                if let img = item.image {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
                }
                Text(item.text)
                    .font(.system(size: CGFloat(item.fontSize), weight: item.bold ? .bold : .regular))
                    .foregroundColor(item.color)
            }
        case .hr:
            Rectangle()
                .fill(TP.surfacePressed)
                .frame(height: 1)
                .padding(.vertical, TP.sXS)
        case .button:
            PillButton(title: item.text, kind: .primary, compact: true) {
                projectManager.handleButtonClick(item)
            }
        case .image:
            if let img = item.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: CGFloat(item.imageWidth), height: CGFloat(item.imageHeight))
                    .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))
            }
        case .table:
            TableItemView(item: item)
        }
    }
}

struct TableItemView: View {
    let item: DialogItemModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(item.columns.enumerated()), id: \.offset) { _, col in
                    Text(col)
                        .font(.tpBody(11, weight: .medium))
                        .foregroundColor(TP.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TP.sSM)
                }
            }
            .padding(.vertical, TP.sSM)
            .background(TP.canvasSoft)

            ForEach(Array(item.rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.tpBody(12))
                            .foregroundColor(TP.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, TP.sSM)
                    }
                    if let url = row.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(TP.ink)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, TP.sSM)
                    }
                }
                .padding(.vertical, 6)
                .background(idx % 2 == 0 ? TP.canvas : TP.canvasSofter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                .stroke(TP.surfacePressed, lineWidth: 1)
        )
    }
}
