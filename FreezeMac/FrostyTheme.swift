import AppKit
import SwiftUI

// MARK: Palette

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

/// Colors taken from Frosty: ice blue body, navy eyes, white frosted highlights.
enum Frosty {
    static let ink = adaptive(light: rgb(0x12305A), dark: rgb(0xE8F2FF))
    static let inkSoft = adaptive(light: rgb(0x4F6C94), dark: rgb(0xA4BEDD))
    static let accent = adaptive(light: rgb(0x3D93E0), dark: rgb(0x62B1F5))
    static let accentDeep = Color(nsColor: rgb(0x2A74C4))
    static let accentLight = Color(nsColor: rgb(0x5BB6F7))
    static let backgroundTop = adaptive(light: rgb(0xF1F8FF), dark: rgb(0x0F1C30))
    static let backgroundBottom = adaptive(light: rgb(0xD5E8FB), dark: rgb(0x16294A))
    static let card = adaptive(light: rgb(0xFFFFFF, 0.62), dark: rgb(0xFFFFFF, 0.07))
    static let cardEdge = adaptive(light: rgb(0xFFFFFF, 0.9), dark: rgb(0xFFFFFF, 0.14))
    static let shadow = adaptive(light: rgb(0x2A74C4, 0.16), dark: rgb(0x000000, 0.35))
}

// MARK: Character

/// Frosty with a gentle idle loop: blinks every few seconds and sways his arms.
/// With Reduce Motion on he stands still.
struct FrostyLiveMascot: View {
    var happy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(started)
            let blinkTime = t.truncatingRemainder(dividingBy: 3.7)
            let blink: CGFloat = blinkTime < 0.18 ? abs(blinkTime - 0.09) / 0.09 : 1
            FrostyMascotView(
                expression: happy ? .happy : .calm,
                eyeOpen: blink,
                leftArmAngle: sin(t * 2.2) * 6,
                rightArmAngle: sin(t * 2.2 + 1) * 10,
                squash: 1 + sin(t * 2.0) * 0.012
            )
        }
    }
}

// MARK: Surfaces

struct FrostyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Frosty.backgroundTop, Frosty.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}

private struct FrostyCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Frosty.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Frosty.cardEdge, lineWidth: 1)
            )
            .shadow(color: Frosty.shadow, radius: 10, y: 4)
    }
}

extension View {
    /// A frosted-glass card.
    func frostyCard(padding: CGFloat = 14) -> some View {
        modifier(FrostyCardModifier(padding: padding))
    }
}

// MARK: Buttons

struct FrostyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Frosty.accentLight, Frosty.accentDeep], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Frosty.accentDeep.opacity(0.35), radius: 10, y: 5)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct FrostySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Frosty.accent)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Frosty.accent.opacity(configuration.isPressed ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: Switch

extension View {
    /// The standard macOS switch. Snapshot renders draw a lookalike instead, because
    /// AppKit-backed controls do not render offscreen.
    @ViewBuilder
    func frostySwitch() -> some View {
        #if SNAPSHOT_HARNESS
        toggleStyle(SnapshotSwitchStyle())
        #else
        toggleStyle(.switch)
        #endif
    }
}

#if SNAPSHOT_HARNESS
private struct SnapshotSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? Frosty.accent : Color.gray.opacity(0.28))
                .frame(width: 38, height: 22)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .padding(2)
                        .offset(x: configuration.isOn ? 8 : -8)
                )
        }
    }
}
#endif

// MARK: Mode card

struct ModeCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Frosty.accent)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Frosty.accent : Frosty.accent.opacity(0.14), in: Circle())
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Frosty.accent)
                    }
                }

                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Frosty.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Frosty.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                isSelected ? Frosty.accent.opacity(0.13) : Frosty.card,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Frosty.accent : Frosty.cardEdge, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Frosty.shadow, radius: isSelected ? 8 : 4, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Common Shared Components (SPEC-003)

// MARK: Status Chip

struct FrostyStatusChip: View {
    let phase: LockPhase
    let statusText: String

    var body: some View {
        let tint: Color = phase.isBusy ? .orange : Frosty.accent
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: Section Header

struct FrostySectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Frosty.ink)
    }
}

// MARK: Capsule & Chip Buttons

struct FrostyCapsuleButtonStyle: ButtonStyle {
    var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(isHighlighted ? Color.white : Frosty.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                isHighlighted ? Frosty.accent : Frosty.accent.opacity(configuration.isPressed ? 0.22 : 0.12),
                in: Capsule()
            )
    }
}

struct FrostyChipButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded).weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Frosty.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Frosty.accent : Frosty.accent.opacity(configuration.isPressed ? 0.22 : 0.12),
                in: Capsule()
            )
    }
}

// MARK: Compact Mode Card (for 300pt popup)

struct FrostyCompactModeCard: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Frosty.accent)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? Frosty.accent : Frosty.accent.opacity(0.14), in: Circle())

                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Frosty.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Frosty.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Frosty.accent.opacity(0.13) : Frosty.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Frosty.accent : Frosty.cardEdge, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Frosty.shadow, radius: isSelected ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

