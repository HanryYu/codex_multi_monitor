import SwiftUI
import AppKit

struct ProviderIconView: View {
    let provider: AccountProvider
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = providerImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(iconBorderColor, lineWidth: max(0.5, size / 40))
                    }
            } else {
                fallback
                    .frame(width: size, height: size)
                    .background(fallbackBackground)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(provider.displayName)
    }

    private var iconBorderColor: Color {
        switch provider {
        case .codex: return Color.black.opacity(0.10)
        case .claude: return Color.black.opacity(0.06)
        case .grok: return Color.white.opacity(0.18)
        }
    }

    private var fallbackBackground: Color {
        switch provider {
        case .codex: return Color.white
        case .claude: return Color(hex: "D97757")
        case .grok: return Color.black
        }
    }

    private var providerImage: NSImage? {
        NSImage(named: NSImage.Name(provider.assetName))
            ?? Bundle.main.url(forResource: provider.assetName, withExtension: "png").flatMap(NSImage.init(contentsOf:))
            ?? Bundle.module.url(forResource: provider.assetName, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    @ViewBuilder
    private var fallback: some View {
        switch provider {
        case .codex:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.72, weight: .semibold))
        case .claude:
            Text("A")
                .font(.system(size: size * 0.72, weight: .bold, design: .serif))
                .foregroundStyle(.white)
        case .grok:
            Text("𝕏")
                .font(.system(size: size * 0.74, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
