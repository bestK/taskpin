import SwiftUI

struct ItemsListView: View {
    var configManager: ConfigManager
    @ObservedObject var projectManager: ProjectManager
    @State private var editingItem: PinItem? = nil
    @State private var isAdding = false
    @State private var hoveredId: UUID? = nil
    @State private var itemToDelete: PinItem? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        if let item = editingItem {
            ItemEditView(item: item, projectManager: projectManager, onSave: { updated in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isAdding {
                        configManager.addItem(updated)
                    } else {
                        configManager.updateItem(updated)
                    }
                    projectManager.restartAll()
                    editingItem = nil
                    isAdding = false
                }
            }, onCancel: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = nil
                    isAdding = false
                }
            })
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            listContent
                .transition(.opacity)
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            listHeader

            if configManager.config.items.isEmpty {
                EmptyState(
                    icon: "square.stack.3d.up.slash",
                    title: "No signals yet",
                    message: "Add a Lua script or URL endpoint to pin live data to the menu bar.",
                    actionTitle: "New signal",
                    action: { startAdd() }
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: TP.sSM) {
                        ForEach(configManager.config.items) { item in
                            itemRow(item)
                        }
                    }
                    .padding(TP.sLG)
                }
            }

            Rectangle().fill(TP.surfacePressed).frame(height: 1)
            bottomToolbar
        }
        .alert("Delete \"\(itemToDelete?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configManager.removeItem(id: item.id)
                        projectManager.stopItem(item.id)
                        projectManager.itemStates.removeValue(forKey: item.id)
                    }
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private var listHeader: some View {
        HStack {
            SectionLabel(text: "All signals")
            Spacer()
            Text("\(configManager.config.items.count)")
                .font(.tpBody(12, weight: .medium))
                .foregroundColor(TP.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(TP.canvasSoft)
                .clipShape(Capsule())
        }
        .padding(.horizontal, TP.sLG)
        .padding(.top, TP.sLG)
        .padding(.bottom, TP.sSM)
    }

    private func itemRow(_ item: PinItem) -> some View {
        HStack(spacing: TP.sMD) {
            // Left accent bar for pinned
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.pinned ? TP.primary : TP.mute)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.tpBody(13, weight: .medium))
                    .foregroundColor(TP.ink)
                    .lineLimit(1)

                HStack(spacing: TP.sSM) {
                    Chip(
                        text: item.type == .lua ? "Lua" : "URL",
                        active: false,
                        icon: item.type == .lua ? "doc.text" : "link"
                    )

                    Text("\(item.intervalMs / 1000)s")
                        .font(.tpCaption(11))
                        .foregroundColor(TP.body)

                    if let state = projectManager.itemStates[item.id] {
                        if let err = state.lastError {
                            Text(err)
                                .font(.tpCaption(11))
                                .foregroundColor(TP.danger)
                                .lineLimit(1)
                        } else if !state.statusText.isEmpty {
                            Text(state.statusText)
                                .font(.tpCaption(11))
                                .foregroundColor(TP.body)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Pin toggle as pill
            Button {
                var updated = item
                updated.pinned.toggle()
                configManager.updateItem(updated)
                projectManager.restartAll()
            } label: {
                Text(item.pinned ? "Live" : "Idle")
                    .font(.tpBody(11, weight: .medium))
                    .foregroundColor(item.pinned ? TP.onPrimary : TP.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(item.pinned ? TP.primary : TP.canvasSoft)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = item
                    isAdding = false
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TP.ink)
                    .frame(width: 28, height: 28)
                    .background(TP.canvasSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                itemToDelete = item
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TP.danger)
                    .frame(width: 28, height: 28)
                    .background(TP.dangerSoft)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TP.sMD)
        .padding(.vertical, TP.sMD)
        .background(
            RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                .fill(hoveredId == item.id ? TP.canvasSofter : TP.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                .stroke(TP.surfacePressed, lineWidth: 1)
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredId = isHovered ? item.id : nil
            }
            if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: TP.sMD) {
            PillButton(title: "New signal", icon: "plus", kind: .primary, compact: true) {
                startAdd()
            }

            Spacer()

            let pinnedCount = configManager.config.items.filter(\.pinned).count
            Text("\(configManager.config.items.count) total · \(pinnedCount) live")
                .font(.tpCaption(11))
                .foregroundColor(TP.body)
        }
        .padding(.horizontal, TP.sLG)
        .padding(.vertical, TP.sMD)
        .background(TP.canvas)
    }

    private func startAdd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingItem = PinItem()
            isAdding = true
        }
    }
}
