import SwiftUI

struct SlideToUnlockView: View {
    let onUnlock: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 54
    private let knobSize: CGFloat = 46
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let maximumOffset = max(0, geometry.size.width - knobSize - inset * 2)
            let progress = maximumOffset > 0 ? offset / maximumOffset : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.14))

                Text("Slide to unlock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary.opacity(1 - progress * 0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knobSize / 2)

                Circle()
                    .fill(Color.accentColor)
                    .overlay {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(isDragging ? 0.22 : 0.12), radius: isDragging ? 7 : 3, y: 2)
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                isDragging = true
                                offset = min(max(0, value.translation.width), maximumOffset)
                            }
                            .onEnded { _ in
                                isDragging = false
                                if maximumOffset > 0, offset / maximumOffset >= 0.88 {
                                    onUnlock()
                                } else {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Slide to unlock")
            .accessibilityHint("Ends the keyboard lock session")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onUnlock()
            }
        }
        .frame(height: trackHeight)
    }
}
