import SwiftUI

/// A cute little Claude character drawn with SwiftUI shapes.
/// Designed to fit in a ~20-40pt circular watch complication.
struct ClaudeCharacterView: View {
    let state: TapState
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Body
            claudeBody

            // Sparkles when working
            if state == .working {
                workingSparkles
            }

            // Attention indicator
            if state.needsTap {
                attentionBadge
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Character Parts

    private var claudeBody: some View {
        ZStack {
            // Head - warm terracotta circle
            Circle()
                .fill(claudeColor)
                .frame(width: size * 0.55, height: size * 0.55)
                .offset(y: -size * 0.1)

            // Eyes
            HStack(spacing: size * 0.1) {
                eye
                eye
            }
            .offset(y: -size * 0.12)

            // Little smile
            if state == .done {
                smileMouth
                    .offset(y: -size * 0.02)
            } else if state == .working {
                concentratingMouth
                    .offset(y: -size * 0.02)
            }

            // Body / torso
            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(claudeColor.opacity(0.8))
                .frame(width: size * 0.4, height: size * 0.25)
                .offset(y: size * 0.2)

            // Arms
            if state == .working {
                workingArms
            } else if state.needsTap {
                wavingArms
            } else {
                restingArms
            }
        }
    }

    private var eye: some View {
        Circle()
            .fill(.white)
            .frame(width: size * 0.1, height: size * 0.1)
            .overlay(
                Circle()
                    .fill(Color(white: 0.15))
                    .frame(width: size * 0.06, height: size * 0.06)
            )
    }

    private var smileMouth: some View {
        Path { path in
            let w = size * 0.12
            path.move(to: CGPoint(x: size / 2 - w, y: size * 0.42))
            path.addQuadCurve(
                to: CGPoint(x: size / 2 + w, y: size * 0.42),
                control: CGPoint(x: size / 2, y: size * 0.48)
            )
        }
        .stroke(.white, lineWidth: 1.2)
    }

    private var concentratingMouth: some View {
        Capsule()
            .fill(.white.opacity(0.8))
            .frame(width: size * 0.1, height: size * 0.03)
    }

    // MARK: - Arms

    private var restingArms: some View {
        HStack(spacing: size * 0.32) {
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(10))
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(-10))
        }
        .offset(y: size * 0.18)
    }

    private var workingArms: some View {
        HStack(spacing: size * 0.32) {
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(-30))
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(30))
        }
        .offset(y: size * 0.12)
    }

    private var wavingArms: some View {
        HStack(spacing: size * 0.36) {
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(10))
                .offset(y: size * 0.18)
            Capsule()
                .fill(claudeColor.opacity(0.7))
                .frame(width: size * 0.06, height: size * 0.18)
                .rotationEffect(.degrees(-60))
                .offset(y: size * 0.06)
        }
    }

    // MARK: - Effects

    private var workingSparkles: some View {
        ForEach(0..<3, id: \.self) { i in
            SparkleShape()
                .fill(claudeColor.opacity(0.6))
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(
                    x: cos(Double(i) * 2.094) * Double(size) * 0.42,
                    y: sin(Double(i) * 2.094) * Double(size) * 0.42 - Double(size) * 0.05
                )
        }
    }

    private var attentionBadge: some View {
        Circle()
            .fill(.blue)
            .frame(width: size * 0.18, height: size * 0.18)
            .overlay(
                Text("!")
                    .font(.system(size: size * 0.11, weight: .bold))
                    .foregroundColor(.white)
            )
            .offset(x: size * 0.25, y: -size * 0.3)
    }

    private var claudeColor: Color {
        Color(red: 0.85, green: 0.55, blue: 0.35) // Warm terracotta
    }
}

/// A 4-pointed sparkle shape
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()

        for i in 0..<4 {
            let angle = Double(i) * .pi / 2
            let tipX = center.x + cos(angle) * r
            let tipY = center.y + sin(angle) * r

            let inAngle1 = angle - .pi / 4
            let inAngle2 = angle + .pi / 4
            let inR = r * 0.3

            if i == 0 {
                path.move(to: CGPoint(x: tipX, y: tipY))
            } else {
                path.addLine(to: CGPoint(x: tipX, y: tipY))
            }
            path.addLine(to: CGPoint(
                x: center.x + cos(inAngle2) * inR,
                y: center.y + sin(inAngle2) * inR
            ))
        }
        // Close back to first inner point
        path.addLine(to: CGPoint(
            x: center.x + cos(-Double.pi / 4) * r * 0.3,
            y: center.y + sin(-Double.pi / 4) * r * 0.3
        ))
        path.closeSubpath()
        return path
    }
}
