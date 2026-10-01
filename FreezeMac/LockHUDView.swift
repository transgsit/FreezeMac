import SwiftUI

struct LockHUDView: View {
    @ObservedObject var model: LockHUDViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                timeRing

                VStack(alignment: .leading, spacing: 3) {
                    Text("Frozen")
                        .font(.system(.headline, design: .rounded))
                    Text("Keyboard locked")
                        .font(.subheadline)
                        .foregroundStyle(Frosty.inkSoft)
                }

                Spacer(minLength: 0)

                FrostyLiveMascot(happy: true)
                    .frame(width: 72, height: 72)
            }

            if !model.unlockHints.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.unlockHints, id: \.self) { hint in
                        Label("Unlock: \(hint)", systemImage: "lock.open.fill")
                            .font(.subheadline)
                            .labelStyle(HintLabelStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.pointerLocked {
                SlideToUnlockView(onUnlock: model.onUnlock)
            }
        }
        .padding(18)
        .fontDesign(.rounded)
        .foregroundStyle(Frosty.ink)
        .tint(Frosty.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Frosty.backgroundTop.opacity(0.78), Frosty.backgroundBottom.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Frosty.cardEdge, lineWidth: 1.5)
        }
        .padding(4)
    }

    /// Remaining time as a ring that drains toward the automatic unlock.
    private var timeRing: some View {
        ZStack {
            Circle()
                .stroke(Frosty.accent.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: model.remainingFraction)
                .stroke(
                    LinearGradient(colors: [Frosty.accentLight, Frosty.accentDeep], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.remainingSeconds)
            Text(model.formattedRemainingTime)
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
        }
        .frame(width: 64, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(model.formattedRemainingTime)
    }
}

private struct HintLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(Frosty.accent)
            configuration.title
        }
    }
}
