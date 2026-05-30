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
            if configManager.config.items.isEmpty {
                emptyView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 6) {
                        ForEach(configManager.config.items) { item in
                            itemRow(item)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                                    removal: .scale(scale: 0.95).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(12)
                }
            }

            Divider().opacity(0.5)
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

    private func itemRow(_ item: PinItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type == .lua ? "chevron.left.forwardslash.chevron.right" : "globe")
                .font(.system(size: 14))
                .foregroundColor(item.pinned ? .primary : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(item.type == .lua ? "Lua" : "URL", systemImage: item.type == .lua ? "doc" : "link")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Label("\(item.intervalMs / 1000)s", systemImage: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    if let state = projectManager.itemStates[item.id] {
                        if let err = state.lastError {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        } else if !state.statusText.isEmpty {
                            Text(state.statusText)
                                .font(.system(size: 9))
                                .foregroundColor(state.statusColor)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { item.pinned },
                set: { newVal in
                    var updated = item
                    updated.pinned = newVal
                    configManager.updateItem(updated)
                    projectManager.restartAll()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = item
                    isAdding = false
                }
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                itemToDelete = item
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredId == item.id ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(hoveredId == item.id ? 0.1 : 0.05), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredId = isHovered ? item.id : nil
            }
            if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = PinItem()
                    isAdding = true
                }
            } label: {
                Label("Add Item", systemImage: "plus.circle.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            Spacer()

            let pinnedCount = configManager.config.items.filter { $0.pinned }.count
            Text("\(configManager.config.items.count) items, \(pinnedCount) pinned")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor.opacity(0.6), .purple.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            VStack(spacing: 4) {
                Text("No Items Yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                Text("Add a Lua script or URL to monitor")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editingItem = PinItem()
                    isAdding = true
                }
            } label: {
                Label("Create First Item", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

