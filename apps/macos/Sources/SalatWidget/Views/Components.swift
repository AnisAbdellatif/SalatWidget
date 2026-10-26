import SwiftUI

extension Color {
    /// Emerald accent used throughout the panel.
    static let brand = Color(red: 0.05, green: 0.56, blue: 0.47)
    static let brandDeep = Color(red: 0.02, green: 0.36, blue: 0.38)
    static let iqama = Color(red: 0.93, green: 0.55, blue: 0.16)
    static let iqamaDeep = Color(red: 0.80, green: 0.31, blue: 0.13)
}

/// Title bar for secondary pages, with an optional back button.
struct PageHeader: View {
    let title: String
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Back")
            }
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

/// A titled, softly filled group of controls.
struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Borderless circular icon button with a hover highlight.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(width: 26, height: 26)
                .contentShape(Circle())
                .background(
                    Circle().fill(.primary.opacity(configuration.isPressed ? 0.16 : isHovering ? 0.08 : 0))
                )
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}

/// A slim capsule progress bar that reads well on a coloured background.
struct CapsuleProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: max(4, proxy.size.width * value))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }
}
