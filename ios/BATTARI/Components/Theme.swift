import SwiftUI

enum Theme {
    static let ink = Color(hex: 0x1F2330)
    static let sub = Color(hex: 0x6B6F80)
    static let label = Color(hex: 0x4A4E5E)
    static let background = Color(hex: 0xF6F5FB)
    static let accent = Color(hex: 0x5B5BD6)
    static let red = Color(hex: 0xE5484D)
    static let fieldBorder = Color(hex: 0xDCDCE8)
    static let gray = Color(hex: 0xECECF3)
    /// G5・G6 の背景
    static let deepGradient = LinearGradient(colors: [Color(hex: 0x6A6AE8), Color(hex: 0x3F3FB0)],
                                             startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 画面下部の大きいボタン
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, gray, danger }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1.5))
            .shadow(color: kind == .primary && isEnabled ? Theme.accent.opacity(0.35) : .clear, radius: 8, y: 6)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .ghost: return Theme.accent
        case .gray: return Theme.label
        case .danger: return Theme.red
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .gray: return Theme.gray
        case .ghost, .danger: return .white
        }
    }

    private var border: Color {
        switch kind {
        case .ghost: return Color(hex: 0xCFCFF3)
        case .danger: return Color(hex: 0xF5C2C4)
        case .primary, .gray: return .clear
        }
    }
}

struct Logo: View {
    var size: CGFloat = 34
    var body: some View {
        (Text("BATT").foregroundColor(Theme.ink) + Text("ARI").foregroundColor(Theme.accent))
            .font(.system(size: size, weight: .black))
            .kerning(1)
    }
}

/// 入力欄の見た目
struct FieldBackground: ViewModifier {
    var focused: Bool
    var error: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(error ? Theme.red : (focused ? Theme.accent : Theme.fieldBorder), lineWidth: 1.5))
            .shadow(color: focused ? Theme.accent.opacity(0.12) : .clear, radius: 4)
    }
}

extension View {
    func fieldStyle(focused: Bool, error: Bool = false) -> some View {
        modifier(FieldBackground(focused: focused, error: error))
    }
}

struct FieldLabel: View {
    let text: String
    var required = false
    var body: some View {
        HStack(spacing: 2) {
            Text(text)
            if required { Text("*").foregroundStyle(Theme.red) }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Theme.label)
    }
}

struct ErrorText: View {
    let text: String?
    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
