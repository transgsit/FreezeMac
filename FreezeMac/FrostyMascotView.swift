import SwiftUI
import AppKit

/// Independent layers; add this file and the three PNGs to the app target.
struct FrostyMascotView: View {
    enum Expression { case calm, happy }
    var expression: Expression = .calm
    /// 0 = closed, 1 = open.
    var eyeOpen: CGFloat = 1
    var leftArmAngle: Double = 0
    var rightArmAngle: Double = 0
    var squash: CGFloat = 1
    var assetDirectory: URL? = nil
    private let ink = Color(red: 0.035, green: 0.12, blue: 0.28)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                part("foot").frame(width: 36, height: 27).position(x: 77, y: 160)
                part("foot").frame(width: 36, height: 27)
                    .scaleEffect(x: -1, y: 1).position(x: 121, y: 160)
                part("hand").frame(width: 48, height: 32)
                    .rotationEffect(.degrees(leftArmAngle), anchor: .trailing)
                    .position(x: 43, y: 110)
                part("hand").frame(width: 48, height: 32).scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(rightArmAngle), anchor: .leading)
                    .position(x: 157, y: 110)
                part("body").frame(width: 120, height: 136).position(x: 100, y: 83)
                eye.frame(width: 15, height: 22).position(x: 87, y: 80)
                eye.frame(width: 15, height: 22).position(x: 122, y: 80)
                FrostySmile().stroke(ink, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    .frame(width: expression == .happy ? 23 : 17, height: 9)
                    .position(x: 105, y: 108)
            }
            .frame(width: 200, height: 200)
            .scaleEffect(x: 1 / squash, y: squash, anchor: .bottom)
            .scaleEffect(geometry.size.width / 200, anchor: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Frosty, FreezeMac refrigerator mascot")
        .allowsHitTesting(false)
    }

    @ViewBuilder private var eye: some View {
        if expression == .happy {
            FrostyHappyEye().stroke(ink, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(height: 8).scaleEffect(y: max(0.08, eyeOpen))
        } else {
            ZStack(alignment: .topLeading) {
                Ellipse().fill(LinearGradient(colors: [ink, Color(red: 0.08, green: 0.25, blue: 0.49)],
                                             startPoint: .top, endPoint: .bottom))
                Circle().fill(.white).frame(width: 4.5, height: 4.5).offset(x: 3, y: 3)
            }.scaleEffect(y: max(0.06, eyeOpen))
        }
    }

    private func part(_ name: String) -> Image {
        Image(nsImage: FrostyAssets.image(name, directory: assetDirectory))
            .resizable()
    }
}

private struct FrostySmile: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.width, y: 0),
                          control: CGPoint(x: r.midX, y: r.height * 1.8))
        }
    }
}
private struct FrostyHappyEye: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: r.height))
            p.addQuadCurve(to: CGPoint(x: r.width, y: r.height),
                          control: CGPoint(x: r.midX, y: -r.height))
        }
    }
}

/// Runtime-only crop removes transparent margins; original PNGs stay intact.
private enum FrostyAssets {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String, directory: URL?) -> NSImage {
        var folder = directory
        #if SNAPSHOT_HARNESS
        if folder == nil, let path = ProcessInfo.processInfo.environment["FROSTY_ASSETS"] {
            folder = URL(fileURLWithPath: path)
        }
        #endif

        let key = (folder?.path ?? "bundle") + name
        if let cached = cache[key] { return cached }

        // The app ships the PNGs in its asset catalog; a folder is only used by previews.
        let loaded: NSImage? = folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("frosty-\(name).png")) }
            ?? NSImage(named: "frosty-\(name)")
        guard let original = loaded,
              let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            assertionFailure("Missing Frosty asset: \(name)")
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        let rect: CGRect
        switch name {
        case "body": rect = CGRect(x: 269, y: 147, width: 780, height: 882)
        case "hand": rect = CGRect(x: 427, y: 285, width: 697, height: 456)
        default: rect = CGRect(x: 434, y: 304, width: 669, height: 496)
        }
        guard let cropped = cg.cropping(to: rect) else { return original }
        let result = NSImage(cgImage: cropped, size: rect.size)
        cache[key] = result
        return result
    }
}
