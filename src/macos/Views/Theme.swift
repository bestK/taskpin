import SwiftUI

// MARK: - Uber-inspired design tokens (from DESIGN.md)

enum TP {
    // Colors — pure black/white duet from DESIGN.md
    static let primary = Color(red: 0, green: 0, blue: 0)
    static let onPrimary = Color(red: 1, green: 1, blue: 1)
    static let ink = Color(red: 0, green: 0, blue: 0)
    static let body = Color(red: 0.369, green: 0.369, blue: 0.369)       // #5E5E5E
    static let mute = Color(red: 0.686, green: 0.686, blue: 0.686)       // #AFAFAF
    static let hairline = Color(red: 0.294, green: 0.294, blue: 0.294)   // #4B4B4B
    static let canvas = Color(red: 1, green: 1, blue: 1)
    static let canvasSoft = Color(red: 0.937, green: 0.937, blue: 0.937) // #EFEFEF
    static let canvasSofter = Color(red: 0.953, green: 0.953, blue: 0.953) // #F3F3F3
    static let surfacePressed = Color(red: 0.886, green: 0.886, blue: 0.886) // #E2E2E2
    static let blackElevated = Color(red: 0.157, green: 0.157, blue: 0.157) // #282828
    static let link = Color(red: 0, green: 0, blue: 0.933)               // #0000EE
    static let danger = Color(red: 0.706, green: 0.137, blue: 0.094)     // #B42318
    static let dangerSoft = Color(red: 0.996, green: 0.894, blue: 0.886) // #FEE4E2

    // Radius
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12
    static let radiusXL: CGFloat = 16
    static let radiusPill: CGFloat = 999
    static let radiusPillTab: CGFloat = 36

    // Spacing
    static let sXXS: CGFloat = 4
    static let sXS: CGFloat = 6
    static let sSM: CGFloat = 8
    static let sMD: CGFloat = 12
    static let sLG: CGFloat = 16
    static let sXL: CGFloat = 20
    static let s2XL: CGFloat = 24
    static let s3XL: CGFloat = 32
}

// MARK: - Typography helpers

extension Font {
    static func tpDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func tpBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func tpCaption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - Shared components

/// Black / white / soft-gray pill button — the brand signature shape.
struct PillButton: View {
    enum Kind { case primary, secondary, subtle, danger }

    let title: String
    var icon: String? = nil
    var kind: Kind = .primary
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TP.sXS) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                }
                Text(title)
                    .font(.tpBody(compact ? 12 : 14, weight: .medium))
            }
            .foregroundColor(foreground)
            .padding(.horizontal, compact ? TP.sMD : TP.sLG)
            .padding(.vertical, compact ? TP.sXS : TP.sSM + 2)
            .background(background)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return TP.primary
        case .secondary: return TP.canvas
        case .subtle: return TP.canvasSoft
        case .danger: return TP.dangerSoft
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return TP.onPrimary
        case .secondary, .subtle: return TP.ink
        case .danger: return TP.danger
        }
    }
}

/// Soft-tinted card surface (canvas soft, 16 px radius).
struct SoftCard<Content: View>: View {
    var padding: CGFloat = TP.sLG
    var fill: Color = TP.canvasSoft
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous))
    }
}

/// White content card with optional hairline.
struct ContentCard<Content: View>: View {
    var padding: CGFloat = TP.sLG
    var showBorder: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TP.canvas)
            .clipShape(RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TP.radiusXL, style: .continuous)
                    .stroke(showBorder ? TP.surfacePressed : Color.clear, lineWidth: 1)
            )
    }
}

/// Uppercase-muted section eyebrow (rare all-caps exception).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.tpBody(11, weight: .medium))
            .foregroundColor(TP.body)
            .tracking(0.4)
            .textCase(.uppercase)
    }
}

/// Soft gray input row (request-form-input-row style).
struct SoftField: View {
    var placeholder: String
    @Binding var text: String
    var mono: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 12, design: .monospaced) : .tpBody(13))
            .foregroundColor(TP.ink)
            .padding(.horizontal, TP.sMD)
            .padding(.vertical, TP.sSM + 2)
            .background(TP.canvasSoft)
            .clipShape(RoundedRectangle(cornerRadius: TP.radiusMD, style: .continuous))
    }
}

/// Compact category / status chip pill.
struct Chip: View {
    let text: String
    var active: Bool = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
            }
            Text(text)
                .font(.tpBody(11, weight: .medium))
        }
        .foregroundColor(active ? TP.onPrimary : TP.ink)
        .padding(.horizontal, TP.sMD)
        .padding(.vertical, TP.sXS)
        .background(active ? TP.primary : TP.canvasSoft)
        .clipShape(Capsule())
    }
}

/// Empty-state block with black CTA.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TP.sLG) {
            ZStack {
                Circle()
                    .fill(TP.canvasSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(TP.ink)
            }

            VStack(spacing: TP.sXS) {
                Text(title)
                    .font(.tpDisplay(16))
                    .foregroundColor(TP.ink)
                Text(message)
                    .font(.tpBody(12))
                    .foregroundColor(TP.body)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                PillButton(title: actionTitle, icon: "plus", kind: .primary, compact: true, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(TP.s2XL)
    }
}

/// Horizontal form label + control.
struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: TP.sMD) {
            Text(label)
                .font(.tpBody(12, weight: .medium))
                .foregroundColor(TP.body)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }
}

// MARK: - Color hex (shared)

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        return String(
            format: "%02X%02X%02X",
            Int(c.redComponent * 255),
            Int(c.greenComponent * 255),
            Int(c.blueComponent * 255)
        )
    }
}
