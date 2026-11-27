import SwiftUI

extension Color {
    static let orbitAccent = Color.adaptive(light: (0.34, 0.27, 0.82), dark: (0.68, 0.61, 1))
    static let orbitCyan = Color.adaptive(light: (0.00, 0.44, 0.51), dark: (0.37, 0.86, 0.93))
    static let orbitAmber = Color.adaptive(light: (0.55, 0.35, 0.02), dark: (1, 0.73, 0.43))
    static let orbitMint = Color.adaptive(light: (0.08, 0.43, 0.29), dark: (0.49, 0.88, 0.68))
    static let orbitBlue = Color.adaptive(light: (0.12, 0.38, 0.73), dark: (0.53, 0.74, 1))

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct OrbitBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            (dark ? Color(red: 0.063, green: 0.072, blue: 0.110) : Color(red: 0.952, green: 0.955, blue: 0.982))

            RadialGradient(colors: [.orbitAccent.opacity(dark ? 0.16 : 0.11), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 550)
            RadialGradient(colors: [.orbitCyan.opacity(dark ? 0.07 : 0.05), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 530)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct OrbitMark: View {
    var size: CGFloat = 34

    var body: some View {
        Canvas { context, frame in
            let scale = frame.width / 40
            var drawing = context
            drawing.scaleBy(x: scale, y: scale)

            let shape = RoundedRectangle(cornerRadius: 11).path(in: CGRect(x: 0, y: 0, width: 40, height: 40))
            drawing.fill(shape, with: .linearGradient(
                Gradient(colors: [Color(red: 0.16, green: 0.11, blue: 0.42), Color(red: 0.37, green: 0.28, blue: 0.75)]),
                startPoint: .zero, endPoint: CGPoint(x: 40, y: 40)
            ))
            drawing.stroke(shape, with: .color(.white.opacity(0.23)), lineWidth: 0.8)

            let center = CGPoint(x: 20, y: 20)
            for (angle, opacity) in [(CGFloat(-0.55), 0.92), (CGFloat(0.68), 0.43)] {
                var ring = drawing
                ring.translateBy(x: center.x, y: center.y)
                ring.rotate(by: .radians(angle))
                ring.stroke(Path(ellipseIn: CGRect(x: -13, y: -6, width: 26, height: 12)),
                            with: .color(.white.opacity(opacity)), lineWidth: 1.15)
            }
            drawing.fill(Path(ellipseIn: CGRect(x: 17, y: 17, width: 6, height: 6)), with: .color(.white))
            drawing.fill(Path(ellipseIn: CGRect(x: 27.5, y: 11.5, width: 4.5, height: 4.5)),
                         with: .color(Color(red: 0.57, green: 0.98, blue: 0.86)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct OrbitIcon: View {
    let name: String
    let color: Color
    var size: CGFloat = 37

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.29))
            .accessibilityHidden(true)
    }
}

struct WorkspaceHeader<Action: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 33, weight: .semibold))
                    .tracking(-1.05)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WorkspaceHeader where Action == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct OrbitCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 19)
                    .fill(scheme == .dark ? .white.opacity(0.045) : .white.opacity(0.69))
                    .strokeBorder(scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.075), lineWidth: 1)
            }
    }
}

struct OrbitSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct OrbitEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .orbitAccent

    var body: some View {
        VStack(spacing: 10) {
            OrbitIcon(name: symbol, color: tint, size: 48)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 285)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 174)
    }
}

struct WorkspaceScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .frame(maxWidth: 1100)
            .padding(.horizontal, 30)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
    }
}
