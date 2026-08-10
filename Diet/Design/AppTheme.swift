import SwiftUI

enum AppTheme {
    static let ink = Color(red: 0.08, green: 0.17, blue: 0.15)
    static let secondaryInk = Color(red: 0.34, green: 0.40, blue: 0.38)
    static let background = Color(red: 0.96, green: 0.97, blue: 0.94)
    static let card = Color.white
    static let lime = Color(red: 0.72, green: 0.88, blue: 0.38)
    static let mint = Color(red: 0.40, green: 0.78, blue: 0.65)
    static let coral = Color(red: 1.00, green: 0.48, blue: 0.35)
    static let paleLime = Color(red: 0.91, green: 0.96, blue: 0.80)
    static let divider = Color.black.opacity(0.07)
}
struct CardStyle: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: AppTheme.ink.opacity(0.055), radius: 18, y: 8)
    }
}

extension View {
    func appCard(padding: CGFloat = 18) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

struct RoundIcon: View {
    let symbol: String
    var foreground: Color = AppTheme.ink
    var background: Color = AppTheme.paleLime
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

struct FilledActionButtonStyle: ButtonStyle {
    var color: Color = AppTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(color.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
