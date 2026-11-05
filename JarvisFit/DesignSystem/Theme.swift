import SwiftUI
import JarvisCore

enum Theme {
    static let background = Color(red: 0.024, green: 0.039, blue: 0.071)
    static let surface = Color(red: 0.06, green: 0.09, blue: 0.14)
    static let surfaceRaised = Color(red: 0.09, green: 0.13, blue: 0.20)
    static let accent = Color(red: 0.25, green: 0.88, blue: 1.0)
    static let accentSoft = Color(red: 0.25, green: 0.88, blue: 1.0).opacity(0.15)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let success = Color(red: 0.35, green: 0.95, blue: 0.6)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static let title = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.06)))
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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentSoft))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Animated orb showing JARVIS's state (idle, listening, thinking, speaking).
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
                case .speaking: return 0.12 * abs(sin(t * 9)) * (0.6 + 0.4 * sin(t * 2.3))
                }
            }()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0.05)], center: .center, startRadius: 2, endRadius: size * 0.6))
                    .scaleEffect(1 + pulse)
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                    .rotationEffect(.degrees(state == .thinking ? t * 240 : t * 40))
                    .padding(size * 0.12)
                Circle()
                    .stroke(Theme.accent.opacity(0.35), lineWidth: size * 0.015)
                    .padding(size * 0.26)
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        switch state {
        case .idle: return "JARVIS"
        case .listening: return "JARVIS listening"
        case .thinking: return "JARVIS thinking"
        case .speaking: return "JARVIS speaking"
        }
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
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
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
        }
        .buttonStyle(.plain)
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
