import SwiftUI

struct OverviewView: View {
    let workspace: WorkspaceModel

    var body: some View {
        WorkspaceScroll {
            WorkspaceHeader(title: "Overview") {
                Button {
                    workspace.notchEnabled.toggle()
                } label: {
                    Label(workspace.notchEnabled ? "Hide Notch" : "Show Notch", systemImage: "macbook")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            hero

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    metric("Battery", workspace.activity.batteryText, icon: "battery.75percent", color: .orbitMint)
                    metric("Available storage", workspace.activity.storageText, icon: "internaldrive", color: .orbitCyan)
                    metric("Active downloads", workspace.downloads.activeCount.formatted(), icon: "arrow.down.to.line", color: .orbitBlue)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                OrbitSectionTitle(title: "Mac tools")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 12) {
                    tool(.notch, status: workspace.notchEnabled ? "Panel visible above your windows" : "System status, timer and media")
                    tool(.gestures, status: workspace.gestures.isRunning ? "Edge gestures enabled" : "Slide to adjust brightness and volume")
                    tool(.cleanup, status: "Scan caches and build files")
                    tool(.downloads, status: "Queue links and manage transfers")
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 23)
                .fill(LinearGradient(
                    colors: [Color(red: 0.105, green: 0.086, blue: 0.247),
                             Color(red: 0.145, green: 0.127, blue: 0.340),
                             Color(red: 0.103, green: 0.166, blue: 0.327)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            OrbitalArtwork()
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 11) {
                Text("Teleprompter")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("Keep your script near the camera\nwhile you present.")
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.79))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    workspace.selected = .teleprompter
                } label: {
                    Label(workspace.prompter.isPresenting ? "Open Controls" : "Open Editor", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.46, green: 0.38, blue: 0.91))
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 23)
        }
        .frame(minHeight: 201)
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func metric(_ name: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            OrbitIcon(name: icon, color: color, size: 33)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 61)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 17))
        .accessibilityElement(children: .combine)
    }

    private func tool(_ page: WorkspacePage, status: String) -> some View {
        Button {
            workspace.selected = page
        } label: {
            OrbitCard(padding: 13) {
                HStack(spacing: 11) {
                    OrbitIcon(name: page.icon, color: page.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 39)
            }
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
    }
}

private struct OrbitalArtwork: View {
    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: size.width * 0.66, y: size.height * 0.5)
            let unit = min(size.width / 365, size.height / 205)
            let lavender = Color(red: 0.67, green: 0.60, blue: 1)
            let mint = Color(red: 0.49, green: 0.97, blue: 0.85)

            var grid = Path()
            for column in 0..<22 {
                let x = CGFloat(column) * 18 + 4
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0..<13 {
                let y = CGFloat(row) * 18 + 5
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .linearGradient(
                Gradient(colors: [.clear, lavender.opacity(0.12)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)
            ), lineWidth: 0.75)

            var drawing = context
            drawing.translateBy(x: origin.x, y: origin.y)
            drawing.scaleBy(x: unit, y: unit)
            let center = Path(ellipseIn: CGRect(x: -48, y: -48, width: 96, height: 96))
            drawing.fill(center, with: .radialGradient(
                Gradient(colors: [lavender.opacity(0.72), Color(red: 0.31, green: 0.27, blue: 0.69), .clear]),
                center: CGPoint(x: -12, y: -12), startRadius: 5, endRadius: 65
            ))
            drawing.stroke(center, with: .color(lavender.opacity(0.58)), lineWidth: 0.8)
            drawing.stroke(Path(ellipseIn: CGRect(x: -59, y: -59, width: 118, height: 118)),
                           with: .color(lavender.opacity(0.25)), style: StrokeStyle(lineWidth: 0.7, dash: [2, 5]))

            for (angle, width, height, color) in [
                (-0.48, 222.0, 71.0, lavender.opacity(0.87)),
                (0.55, 200.0, 65.0, mint.opacity(0.53)),
                (-1.26, 173.0, 58.0, lavender.opacity(0.45))
            ] {
                var ring = drawing
                ring.rotate(by: .radians(angle))
                ring.stroke(Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)),
                            with: .color(color), lineWidth: 0.85)
            }

            for (x, y, diameter, color) in [
                (94.0, -55.0, 7.0, mint),
                (-74.0, -32.0, 5.0, lavender),
                (41.0, 55.0, 4.0, Color.white.opacity(0.8)),
                (-87.0, 49.0, 3.0, mint.opacity(0.65)),
                (116.0, 20.0, 3.0, lavender),
                (70.0, -78.0, 2.0, Color.white.opacity(0.8)),
                (-101.0, -53.0, 2.0, Color.white.opacity(0.7))
            ] {
                drawing.fill(Path(ellipseIn: CGRect(x: x - diameter / 2, y: y - diameter / 2,
                                                  width: diameter, height: diameter)),
                             with: .color(color))
            }
        }
    }
}
