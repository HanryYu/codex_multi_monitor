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
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(provider.displayName)
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
                .foregroundStyle(Color(hex: "D97757"))
        case .grok:
            Text("𝕏")
                .font(.system(size: size * 0.74, weight: .semibold))
        }
    }
}
