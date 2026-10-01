import AppKit
import SwiftUI

/// Frosty's home: the hardware notch, or a black island the app draws itself.
struct IslandGeometry: Equatable {
    var centerX: CGFloat
    var width: CGFloat
    var height: CGFloat
    var isHardwareNotch: Bool
}

extension NSScreen {
    /// Positions are in screen-local points, measured from the top-left corner.
    var islandGeometry: IslandGeometry {
        if safeAreaInsets.top > 0,
           let left = auxiliaryTopLeftArea,
           let right = auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return IslandGeometry(
                centerX: left.width + width / 2,
                width: width,
                height: safeAreaInsets.top,
                isHardwareNotch: true
            )
        }
        return IslandGeometry(centerX: frame.width / 2, width: 200, height: 34, isHardwareNotch: false)
    }
}

// MARK: Choreography

/// Frosty's pose for one frame.
struct FrostyFrame: Equatable {
    /// Where his hands are. Everything else is drawn around this point.
    var hands: CGPoint
    var opacity: Double = 1
    var popScale: CGFloat = 1
    var squash: CGFloat = 1
    var rotation: Double = 0
    var happy = false
    var eyeOpen: CGFloat = 1
    var leftArm: Double = 0
    var rightArm: Double = 0
    /// Straining to climb: sweat drops fly off.
    var effort: Double = 0
    /// Flying: speed lines under his feet.
    var speed: Double = 0
}

/// Everything drawn on one screen at one instant.
struct StageFrame: Equatable {
    /// 0 = the whole screen is visible, 1 = it has all been sucked into the island.
    var drain: CGFloat = 0
    /// Only used with Reduce Motion, which fades instead of draining.
    var blackOpacity: Double?
    var frosty: FrostyFrame?
    var islandOpacity: Double = 1
}

/// Frosty heaves himself up over the bottom edge of the screen like climbing a wall,
/// then flies Superman-style up into the island. As he takes off the screen shrinks
/// up from the bottom into a drop and is sucked in after him, leaving black.
/// Unlocking pours the screen back down and Frosty pops out to wave.
struct DrainChoreography {
    static let entryDuration: Double = 2.3
    static let exitDuration: Double = 1.9
    /// Frosty is drawn in a square box this wide. His arms span about 80% of it,
    /// which keeps him narrower than the notch (about 220 pt) when he flies in.
    static let mascotSize: CGFloat = 180
    /// In his 200-unit canvas the hands sit at y=110.
    private static let handsFromTop: CGFloat = mascotSize * 110 / 200
    /// Standing on the screen, his hands are this far above the bottom edge.
    private static let standing: CGFloat = 70

    let size: CGSize
    let island: IslandGeometry
    let showsFrosty: Bool

    init(size: CGSize, island: IslandGeometry, showsFrosty: Bool) {
        self.size = size
        self.island = island
        self.showsFrosty = showsFrosty
    }

    var coveredFrame: StageFrame { StageFrame(drain: 1, frosty: nil, islandOpacity: 1) }

    /// Hands position for a height measured up from the bottom edge's middle.
    private func climb(_ f: CGFloat) -> CGPoint {
        CGPoint(x: island.centerX, y: size.height - f)
    }

    /// Height at which Frosty is completely inside the island.
    private var insideIsland: CGFloat {
        size.height - island.height + Self.mascotSize * 0.65
    }

    // MARK: Entry

    func entryFrame(at t: Double) -> StageFrame {
        var frosty = FrostyFrame(hands: .zero)
        var f: CGFloat

        switch t {
        case ..<0.35:
            // Eyes peek over the bottom edge.
            f = lerp(-110, -12, ease(t / 0.35, out: true))
        case ..<1.15:
            // Heave up in three goes, slipping back a little each time.
            let heaves: [(Double, Double, CGFloat, CGFloat)] = [(0.35, 0.6, -12, 18), (0.6, 0.85, 18, 44), (0.85, 1.15, 44, Self.standing)]
            let heave = heaves.first { t < $0.1 } ?? heaves[2]
            let k = (t - heave.0) / (heave.1 - heave.0)
            let up = heave.3 + 8
            f = k < 0.7
                ? lerp(heave.2, up, ease(k / 0.7, out: true))
                : lerp(up, heave.3, ease((k - 0.7) / 0.3))
            frosty.happy = true // eyes squeezed shut
            frosty.leftArm = 38
            frosty.rightArm = -38
            frosty.squash = 1 + 0.07 * CGFloat(sin(k * .pi))
            frosty.rotation = 3 * sin(t * 70)
            frosty.effort = 1
        case ..<1.32:
            // Made it: catch a breath, then crouch.
            let k = (t - 1.15) / 0.17
            f = Self.standing
            frosty.squash = 1 - 0.15 * CGFloat(ease(k, in: true))
        case ..<1.72:
            // Fly up into the island like Superman, one fist raised.
            let k = (t - 1.32) / 0.4
            f = lerp(Self.standing, insideIsland, ease(k, in: true))
            frosty.squash = 1.22
            frosty.leftArm = 0
            frosty.rightArm = -40
            frosty.happy = true
            frosty.speed = 1
        default:
            f = insideIsland
            frosty.opacity = 0
        }

        frosty.hands = climb(f)

        // The screen is sucked up after him from the moment he takes off.
        let drain = CGFloat(ease((t - 1.32) / (Self.entryDuration - 1.32)))
        return StageFrame(
            drain: drain,
            frosty: showsFrosty ? frosty : nil,
            islandOpacity: min(t / 0.3, 1)
        )
    }

    // MARK: Exit

    func exitFrame(at t: Double) -> StageFrame {
        let rest = CGPoint(x: island.centerX, y: island.height + 40 + Self.handsFromTop)
        let hidden = CGPoint(x: rest.x, y: island.height - Self.mascotSize * 0.65)
        var frosty = FrostyFrame(hands: hidden, happy: true)
        var islandOpacity = 1.0

        switch t {
        case ..<0.7:
            frosty.opacity = 0
        case ..<1.0:
            // Pop out feet first, with a bounce.
            let k = (t - 0.7) / 0.3
            frosty.hands = CGPoint(x: rest.x, y: hidden.y + (rest.y - hidden.y) * CGFloat(bounceOut(k)))
            frosty.squash = k < 0.7 ? 1.12 : 0.9
            frosty.leftArm = 38 * (1 - k)
            frosty.rightArm = -38 * (1 - k)
        case ..<1.5:
            // Wave.
            let k = (t - 1.0) / 0.5
            frosty.hands = CGPoint(x: rest.x, y: rest.y - 10 * CGFloat(sin(min(k * 2, 1) * .pi)))
            frosty.rightArm = -26 + 14 * sin(k * 4 * .pi)
        default:
            // Fade away.
            let k = min((t - 1.5) / (Self.exitDuration - 1.5), 1)
            frosty.hands = rest
            frosty.opacity = 1 - k
            frosty.popScale = 1 - 0.3 * CGFloat(k)
            islandOpacity = 1 - k
        }

        // The screen pours back down out of the island.
        let drain = CGFloat(1 - ease(t / 0.8, out: true))
        return StageFrame(
            drain: drain,
            frosty: showsFrosty ? frosty : nil,
            islandOpacity: islandOpacity
        )
    }

    // MARK: Screen shape

    /// The outline of what is still visible of the screen, `drain` 0...1. It shrinks up
    /// from the bottom into a drop hanging from the island, which is then sucked in.
    /// Every keyframe is sampled at the same angles (0 = straight up, clockwise) so
    /// the shapes can be blended point by point.
    func visibleOutline(drain p: CGFloat) -> [CGPoint] {
        let w = size.width, h = size.height
        let tip = CGPoint(x: island.centerX, y: island.height)
        let keys: [(CGFloat, (Double) -> CGPoint)] = [
            (0.0, { rectanglePoint($0) }),
            (0.3, { superellipsePoint($0, center: CGPoint(x: tip.x, y: h * 0.4), a: w * 0.47, b: h * 0.4, n: 5) }),
            (0.6, { dropPoint($0, tip: tip, center: CGPoint(x: tip.x, y: tip.y + (h - tip.y) * 0.32), radius: min(w, h) * 0.22) }),
            (0.85, { dropPoint($0, tip: tip, center: CGPoint(x: tip.x, y: tip.y + 64), radius: 34) }),
            (1.0, { _ in tip }),
        ]

        var index = 0
        while index < keys.count - 2 && p > keys[index + 1].0 { index += 1 }
        let (p0, shape0) = keys[index]
        let (p1, shape1) = keys[index + 1]
        let local = Double(min(max((p - p0) / (p1 - p0), 0), 1))
        let k = CGFloat(local * local * (3 - 2 * local))

        // Liquid jiggle, strongest mid-way and gone at both ends.
        let wobble = 12 * sin(Double(p) * .pi)
        let samples = 180

        return (0..<samples).map { i in
            let theta = Double(i) / Double(samples) * 2 * .pi
            let a = shape0(theta), b = shape1(theta)
            let ripple = CGFloat(wobble * sin(6 * theta + Double(p) * 9))
            return CGPoint(
                x: a.x + (b.x - a.x) * k + CGFloat(sin(theta)) * ripple,
                y: a.y + (b.y - a.y) * k - CGFloat(cos(theta)) * ripple
            )
        }
    }

    /// The screen rectangle, reached by a ray from its centre.
    private func rectanglePoint(_ theta: Double) -> CGPoint {
        let c = CGPoint(x: island.centerX, y: size.height / 2)
        let dx = CGFloat(sin(theta)), dy = -CGFloat(cos(theta))
        let tx = dx > 0 ? (size.width - c.x) / dx : dx < 0 ? -c.x / dx : .infinity
        let ty = dy > 0 ? (size.height - c.y) / dy : dy < 0 ? -c.y / dy : .infinity
        let t = min(tx, ty)
        return CGPoint(x: c.x + dx * t, y: c.y + dy * t)
    }

    private func superellipsePoint(_ theta: Double, center: CGPoint, a: CGFloat, b: CGFloat, n: Double) -> CGPoint {
        let sx = sin(theta), sy = -cos(theta)
        let ex = CGFloat(copysign(pow(abs(sx), 2 / n), sx))
        let ey = CGFloat(copysign(pow(abs(sy), 2 / n), sy))
        return CGPoint(x: center.x + a * ex, y: center.y + b * ey)
    }

    /// A round drop whose top is drawn out into a neck ending at the island.
    private func dropPoint(_ theta: Double, tip: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let round = CGPoint(x: center.x + radius * CGFloat(sin(theta)), y: center.y - radius * CGFloat(cos(theta)))
        let pull = CGFloat(pow(pow(cos(theta / 2), 2), 6))
        return CGPoint(x: round.x + (tip.x - round.x) * pull, y: round.y + (tip.y - round.y) * pull)
    }

    // MARK: Helpers

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    private func ease(_ x: Double, in easeIn: Bool = false, out easeOut: Bool = false) -> Double {
        let t = min(max(x, 0), 1)
        if easeIn { return t * t }
        if easeOut { return 1 - (1 - t) * (1 - t) }
        return t * t * (3 - 2 * t)
    }

    private func bounceOut(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 + 0.18 * sin(t * .pi) * (1 - t) - pow(1 - t, 3)
    }
}

// MARK: Stage

@MainActor
final class BlackoutStage: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case entering(Date)
        case covered
        case exiting(Date)
    }

    @Published private(set) var phase: Phase = .waiting
    @Published var masterOpacity: Double = 1

    let choreography: DrainChoreography
    let reduceMotion: Bool
    private(set) var isEntryFinished = false

    init(screenSize: CGSize, island: IslandGeometry, showsFrosty: Bool, reduceMotion: Bool) {
        choreography = DrainChoreography(size: screenSize, island: island, showsFrosty: showsFrosty)
        self.reduceMotion = reduceMotion
    }

    var isAnimating: Bool {
        switch phase {
        case .entering, .exiting: return true
        case .waiting, .covered: return false
        }
    }

    func frame(at date: Date) -> StageFrame {
        switch phase {
        case .waiting:
            return StageFrame(frosty: nil, islandOpacity: 0)
        case .covered:
            return reduceMotion ? StageFrame(blackOpacity: 1, islandOpacity: 0) : choreography.coveredFrame
        case .entering(let start):
            let t = date.timeIntervalSince(start)
            if reduceMotion { return StageFrame(blackOpacity: min(t / 0.4, 1), islandOpacity: 0) }
            return t >= DrainChoreography.entryDuration ? choreography.coveredFrame : choreography.entryFrame(at: t)
        case .exiting(let start):
            let t = date.timeIntervalSince(start)
            if reduceMotion { return StageFrame(blackOpacity: max(1 - t / 0.35, 0), islandOpacity: 0) }
            return choreography.exitFrame(at: min(t, DrainChoreography.exitDuration))
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func playEntry() async {
        phase = .entering(Date())
        await pause(reduceMotion ? 0.45 : DrainChoreography.entryDuration)
        guard !Task.isCancelled else { return }
        phase = .covered
        isEntryFinished = true
    }

    func playExit() async {
        phase = .exiting(Date())
        await pause(reduceMotion ? 0.4 : DrainChoreography.exitDuration)
    }

    /// Used when the lock ends before the entry finished, so nothing is left half drawn.
    func playQuickFade() async {
        withAnimation(.easeOut(duration: 0.2)) { masterOpacity = 0 }
        await pause(0.22)
    }
}

// MARK: Views

struct BlackoutStageView: View {
    @ObservedObject var stage: BlackoutStage

    var body: some View {
        TimelineView(.animation(paused: !stage.isAnimating)) { context in
            StageFrameView(frame: stage.frame(at: context.date), choreography: stage.choreography)
        }
        .opacity(stage.masterOpacity)
    }
}

/// Draws one frame. Separate from the timeline so a frame can be rendered on its own.
struct StageFrameView: View {
    let frame: StageFrame
    let choreography: DrainChoreography

    var body: some View {
        let size = choreography.size
        let island = choreography.island

        ZStack(alignment: .topLeading) {
            if let opacity = frame.blackOpacity {
                Color.black.opacity(opacity)
            } else if frame.drain >= 1 {
                Color.black
            } else if frame.drain > 0 {
                DrainCanvas(outline: choreography.visibleOutline(drain: frame.drain))
            }

            if choreography.showsFrosty {
                if !island.isHardwareNotch {
                    UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                        .fill(Color.black)
                        .frame(width: island.width, height: island.height)
                        .position(x: island.centerX, y: island.height / 2)
                        .opacity(frame.islandOpacity)
                }

                if let frosty = frame.frosty {
                    frostyView(frosty)
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        // Nothing above the island's bottom edge may show: that area is the ceiling.
                        .mask {
                            Rectangle().padding(.top, island.height)
                        }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func frostyView(_ f: FrostyFrame) -> some View {
        let box = DrainChoreography.mascotSize
        // In the mascot's 200-unit canvas his hands sit at (100, 110).
        let center = CGPoint(x: f.hands.x, y: f.hands.y + box * (0.5 - 110.0 / 200.0))
        return ZStack(alignment: .topLeading) {
            if f.speed > 0 {
                // Speed lines streaming below him.
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.8 * f.speed), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: 5, height: [90, 140, 90][i])
                        .position(x: center.x + [-34, 0, 34][i], y: center.y + box * 0.45 + [45, 70, 45][i])
                }
            }

            FrostyMascotView(
                expression: f.happy ? .happy : .calm,
                eyeOpen: f.eyeOpen,
                leftArmAngle: f.leftArm,
                rightArmAngle: f.rightArm,
                squash: f.squash
            )
            .frame(width: box, height: box)
            .scaleEffect(f.popScale, anchor: .bottom)
            .rotationEffect(.degrees(f.rotation), anchor: .bottom)
            .position(center)

            if f.effort > 0 {
                // Sweat drops flicking off both sides of his head.
                ForEach(0..<2) { i in
                    let side: CGFloat = i == 0 ? -1 : 1
                    Image(systemName: "drop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0))
                        .rotationEffect(.degrees(Double(side) * 35))
                        .opacity(f.effort * 0.9)
                        .position(x: center.x + side * box * 0.4, y: center.y - box * 0.32)
                }
            }
        }
        .opacity(f.opacity)
    }
}

/// Black everywhere except the drop of screen that is still left, with a glossy
/// water-like rim on the drop's edge.
private struct DrainCanvas: View {
    let outline: [CGPoint]

    var body: some View {
        Canvas { context, size in
            var drop = Path()
            drop.addLines(outline)
            drop.closeSubpath()

            var black = Path(CGRect(origin: .zero, size: size))
            black.addPath(drop)
            context.fill(black, with: .color(.black), style: FillStyle(eoFill: true))

            var glow = context
            glow.addFilter(.shadow(color: Color(red: 0.36, green: 0.7, blue: 0.97).opacity(0.9), radius: 10))
            glow.stroke(drop, with: .color(Color(red: 0.62, green: 0.84, blue: 1.0)), lineWidth: 3)
            context.stroke(drop, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}
