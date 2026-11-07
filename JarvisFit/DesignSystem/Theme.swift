import SwiftUI
import JarvisCore

/// NOVA design system: deep-space background, "nova lime" energy accent and a violet glow.
enum Theme {
    static let background = Color(red: 0.027, green: 0.024, blue: 0.047)
    static let surface = Color(red: 0.071, green: 0.063, blue: 0.110)
    static let surfaceRaised = Color(red: 0.110, green: 0.098, blue: 0.170)
    static let accent = Color(red: 0.784, green: 1.0, blue: 0.180)
    static let accentSoft = Color(red: 0.784, green: 1.0, blue: 0.180).opacity(0.14)
    static let glow = Color(red: 0.541, green: 0.420, blue: 1.0)
    static let glowSoft = Color(red: 0.541, green: 0.420, blue: 1.0).opacity(0.18)
    static let warning = Color(red: 1.0, green: 0.70, blue: 0.25)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.42)
    static let success = Color(red: 0.24, green: 0.95, blue: 0.64)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.60)

    static let novaGradient = LinearGradient(colors: [accent, glow], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Wide, heavy display type for numbers and screen heroes.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.expanded) }
    static let title = Font.system(.title2).weight(.bold).width(.expanded)
    static let headline = Font.system(.headline).weight(.semibold)
    static let body = Font.system(.body)
    static let caption = Font.system(.caption)
}

/// Screen background: deep space with two soft nebula glows.
struct NovaBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.glow.opacity(0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Theme.accent.opacity(0.07), .clear], center: .bottomLeading, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func novaBackground() -> some View { background(NovaBackground()) }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surfaceRaised.opacity(0.92), Theme.surface.opacity(0.92)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 14, y: 4)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.accentSoft)
                    .overlay(Capsule(style: .continuous).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption).weight(.bold).width(.expanded))
            .tracking(1.4)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// NOVA's state orb (idle, listening, thinking, speaking): a lime star core inside a violet halo
/// with a rotating arc. Kept under the old type name so callers stay unchanged.
struct JarvisOrb: View {
    enum State { case idle, listening, thinking, speaking }
    var state: State
    var size: CGFloat = 80

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || state == .idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse: Double = {
                switch state {
                case .idle: return 0
                case .listening: return 0.08 * sin(t * 4)
                case .thinking: return 0.05 * sin(t * 8)
                case .speaking: return 0.14 * abs(sin(t * 9)) * (0.6 + 0.4 * sin(t * 2.3))
                }
            }()
            let tint = state == .listening ? Theme.glow : Theme.accent
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.glow.opacity(0.55), Theme.glow.opacity(0.0)],
                                         center: .center, startRadius: size * 0.1, endRadius: size * 0.55))
                    .scaleEffect(1 + pulse * 1.4)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(AngularGradient(colors: [tint.opacity(0), tint], center: .center),
                            style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                    .rotationEffect(.degrees(state == .thinking ? t * 260 : t * 45))
                    .padding(size * 0.10)
                NovaStar()
                    .fill(RadialGradient(colors: [.white, tint, tint.opacity(0.6)],
                                         center: .center, startRadius: 0, endRadius: size * 0.22))
                    .frame(width: size * 0.44, height: size * 0.44)
                    .scaleEffect(1 + pulse)
                    .rotationEffect(.degrees(state == .idle ? 0 : sin(t * 1.5) * 8))
                    .shadow(color: tint.opacity(0.8), radius: size * 0.08)
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        switch state {
        case .idle: return "NOVA"
        case .listening: return "NOVA listening"
        case .thinking: return "NOVA thinking"
        case .speaking: return "NOVA speaking"
        }
    }
}

/// Four-pointed star used by the orb and the brand mark.
struct NovaStar: Shape {
    var innerRatio: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : r * innerRatio
            let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Brand lockup: star + "NOVA" word mark + "COACH".
struct NovaWordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            NovaStar().fill(Theme.novaGradient).frame(width: size * 0.9, height: size * 0.9)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - size * 0.08 }
            Text("NOVA").font(.system(size: size, weight: .black).width(.expanded)).tracking(size * 0.08)
                .foregroundStyle(.white)
            Text("COACH").font(.system(size: size * 0.5, weight: .bold).width(.expanded)).tracking(size * 0.12)
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("NOVA Coach"))
    }
}

/// Orb bound to the live voice state.
struct LiveOrb: View {
    @ObservedObject var voice: VoiceCoordinator
    var size: CGFloat = 80

    var body: some View { JarvisOrb(state: voice.orbState, size: size) }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, min(1, progress)))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: lineWidth * 0.6)
                .animation(.easeOut(duration: 0.3), value: progress)
        }
    }
}

struct ChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(selected ? Color.black : Theme.textPrimary)
                .background(Capsule().fill(selected ? Theme.accent : Theme.surfaceRaised))
                .overlay(Capsule().stroke(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
