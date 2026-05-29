import SwiftUI

struct PopoverView: View {
    @ObservedObject var engine: ScriptEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(engine.dialogItems) { item in
                switch item.kind {
                case .text:
                    HStack(spacing: 4) {
                        if let img = item.image {
                            Image(nsImage: img)
                                .resizable()
                                .frame(width: CGFloat(item.imageWidth),
                                       height: CGFloat(item.imageHeight))
                        }
                        Text(item.text)
                            .font(.system(size: CGFloat(item.fontSize),
                                          weight: item.bold ? .bold : .regular))
                            .foregroundColor(item.color)
                    }
                case .hr:
                    Divider()
                case .button:
                    Button(item.text) {
                        engine.handleButtonClick(item)
                    }
                    .buttonStyle(.bordered)
                case .image:
                    if let img = item.image {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: CGFloat(item.imageWidth),
                                   height: CGFloat(item.imageHeight))
                    }
                case .table:
                    TableItemView(item: item)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 300, maxWidth: 500)
    }
}

struct TableItemView: View {
    let item: DialogItemModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                ForEach(item.columns, id: \.self) { col in
                    Text(col)
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.2))

            // Rows
            ForEach(Array(item.rows.enumerated()), id: \.offset) { idx, row in
                HStack {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let url = row.url {
                        Button("Open") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 2)
                .background(idx % 2 == 0 ? Color.clear : Color.gray.opacity(0.1))
            }
        }
    }
}
