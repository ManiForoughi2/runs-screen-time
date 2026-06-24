import SwiftUI

enum Theme {
    static let bg = adaptive(dark: .black, light: .white)
    static let fg = adaptive(dark: .white, light: .black)
    static let dim = adaptive(dark: .white.opacity(0.5), light: .black.opacity(0.5))
    static let faint = adaptive(dark: .white.opacity(0.15), light: .black.opacity(0.12))
    static let hairline = adaptive(dark: .white.opacity(0.12), light: .black.opacity(0.14))

    // registered via Info.plist UIAppFonts
    static let fontName = "FairfaxHD"

    // run pip display tiers: <7 dots+count, 7-9 dots only, 10+ numeric only
    static let dotsWithCountThreshold = 7
    static let dotsOnlyThreshold = 10

    // FairfaxHD glyphs sit small for their point size, scale up
    private static let scale: CGFloat = 1.18

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        // FairfaxHD ships single weight, .custom ignores weight, hierarchy comes from size
        .custom(fontName, size: size * scale)
    }

    private static func adaptive(dark: Color, light: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(light) : UIColor(dark)
        })
    }
}

struct OutlineButtonStyle: ButtonStyle {
    var filled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(15, .semibold))
            .foregroundStyle(filled ? Theme.bg : Theme.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(filled ? Theme.fg : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.fg, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // clear interior isnt hit-tested, make whole rect tappable
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    func screenBackground() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.ignoresSafeArea())
    }
}
