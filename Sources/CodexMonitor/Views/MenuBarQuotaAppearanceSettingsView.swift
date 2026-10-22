import AppKit
import SwiftUI

struct MenuBarQuotaAppearanceSettingsView: View {
    @Binding var iconStyle: MenuBarIconStyle
    @Binding var displayMode: DisplayMode
    @Binding var showPercentage: Bool
    @Binding var appearance: MenuBarQuotaAppearance
    @ObservedObject private var localeManager = LocaleManager.shared

    private var usesWhitePreview: Bool {
        iconStyle == .ring && appearance.colorMode == .monochrome
    }

    private var effectivePosition: MenuBarQuotaNumberPosition {
        appearance.effectiveNumberPosition(iconStyle: iconStyle)
    }

    var body: some View {
        SettingGroupCard(label: MenuBarQuotaL10n.menuBarStyleSection, systemImage: "paintpalette") {
            HStack(spacing: 12) {
                SettingTextBlock(title: MenuBarQuotaL10n.iconStyle, description: nil)
                Spacer(minLength: 8)
                SettingsSegmentedControl(
                    selection: $iconStyle,
                    options: [
                        .init(label: MenuBarQuotaL10n.ringIcon, value: .ring),
                        .init(label: MenuBarQuotaL10n.standardIcon, value: .standard)
                    ]
                )
            }

            CardDivider()

            HStack(spacing: 12) {
                SettingTextBlock(title: MenuBarQuotaL10n.quotaDisplay, description: nil)
                Spacer(minLength: 8)
                SettingsSegmentedControl(
                    selection: $displayMode,
                    options: [
                        .init(label: L10n.remaining, value: .remaining),
                        .init(label: L10n.used, value: .used)
                    ]
                )
            }

            SettingsCheckbox(
                title: MenuBarQuotaL10n.showPercent,
                description: MenuBarQuotaL10n.showPercentDescription,
                isChecked: $showPercentage
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    SettingTextBlock(title: MenuBarQuotaL10n.numberPosition, description: nil)
                    Spacer(minLength: 8)
                    SettingsSegmentedControl(
                        selection: numberPositionBinding,
                        options: numberPositionOptions
                    )
                    .opacity(showPercentage ? 1 : 0.55)
                    .disabled(!showPercentage)
                }

                if showPercentage, iconStyle == .ring, effectivePosition == .inside {
                    Text(MenuBarQuotaL10n.insideNumberHelp)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            previewSection

            if iconStyle == .ring {
                CardDivider()
                colorSettings
            }
        }
        .onAppear(perform: loadPreferences)
        .onChange(of: iconStyle) { _, value in
            UserDefaults.standard.set(value.rawValue, forKey: MenuBarQuotaPreferences.iconStyleKey)
            notifyMenuBarSettingsChanged()
        }
        .onChange(of: displayMode) { _, value in
            UserDefaults.standard.set(value.rawValue, forKey: PreferencesKeys.displayMode)
            NotificationCenter.default.post(name: .displayModeChanged, object: nil)
            notifyMenuBarSettingsChanged()
        }
        .onChange(of: showPercentage) { _, value in
            UserDefaults.standard.set(value, forKey: PreferencesKeys.showMenuBarText)
            notifyMenuBarSettingsChanged()
        }
        .onChange(of: appearance) { _, value in
            value.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .displayModeChanged)) { _ in
            let rawValue = UserDefaults.standard.string(forKey: PreferencesKeys.displayMode)
                ?? DisplayMode.remaining.rawValue
            displayMode = DisplayMode(rawValue: rawValue) ?? .remaining
        }
        .onChange(of: localeManager.currentLanguage) { _, _ in
            // Observing the locale refreshes the computed strings in this view.
        }
    }

    private var numberPositionOptions: [SettingsOption<MenuBarQuotaNumberPosition>] {
        var options: [SettingsOption<MenuBarQuotaNumberPosition>] = [
            .init(label: MenuBarQuotaL10n.numberLeading, value: .leading)
        ]
        if iconStyle == .ring {
            options.append(.init(label: MenuBarQuotaL10n.numberInside, value: .inside))
        }
        options.append(.init(label: MenuBarQuotaL10n.numberTrailing, value: .trailing))
        return options
    }

    private var numberPositionBinding: Binding<MenuBarQuotaNumberPosition> {
        Binding(
            get: { effectivePosition },
            set: { appearance.numberPosition = $0 }
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MenuBarQuotaL10n.appearancePreview)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)

            HStack(spacing: 12) {
                ForEach([75, 40, 10], id: \.self) { remaining in
                    previewItem(remainingPercent: remaining)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(usesWhitePreview ? Color.black.opacity(0.8) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func previewItem(remainingPercent: Int) -> some View {
        let snapshot = MenuBarQuotaSnapshot(usedPercent: 100 - remainingPercent)
        let showRemaining = displayMode == .remaining
        let number = snapshot.percentage(showRemaining: showRemaining)
        let showNumberInside = showPercentage && iconStyle == .ring && effectivePosition == .inside

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                if showPercentage && effectivePosition == .leading {
                    previewNumber(number, includePercent: true)
                }

                previewIcon(snapshot: snapshot, showRemaining: showRemaining, showNumberInside: showNumberInside)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: showNumberInside ? 22 : 18, height: showNumberInside ? 22 : 18)

                if showPercentage && effectivePosition == .trailing {
                    previewNumber(number, includePercent: true)
                }
            }
            .frame(height: 22)

            Text(MenuBarQuotaL10n.previewRemaining(remainingPercent))
                .font(.system(size: 9, weight: .regular).monospacedDigit())
                .foregroundStyle(usesWhitePreview ? Color.white.opacity(0.7) : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func previewIcon(
        snapshot: MenuBarQuotaSnapshot,
        showRemaining: Bool,
        showNumberInside: Bool
    ) -> Image {
        if iconStyle == .ring {
            return Image(nsImage: MenuBarQuotaRing.image(
                snapshot: snapshot,
                showRemaining: showRemaining,
                appearance: appearance,
                showNumberInside: showNumberInside
            ))
        }

        if let image = NSImage(
            systemSymbolName: "gauge.with.dots.fill.60percent",
            accessibilityDescription: MenuBarQuotaL10n.menuBarStyleSection
        ) ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: MenuBarQuotaL10n.menuBarStyleSection) {
            return Image(nsImage: image)
        }
        return Image(systemName: "gauge.medium")
    }

    private func previewNumber(_ value: Int?, includePercent: Bool) -> some View {
        Text(value.map { includePercent ? "\($0)%" : "\($0)" } ?? "—")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(usesWhitePreview ? Color.white : Color.primary)
            .fixedSize()
    }

    private var colorSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                SettingTextBlock(title: MenuBarQuotaL10n.colorMode, description: nil)
                Spacer(minLength: 8)
                SettingsSegmentedControl(
                    selection: Binding(
                        get: { appearance.colorMode },
                        set: { appearance.colorMode = $0 }
                    ),
                    options: [
                        .init(label: MenuBarQuotaL10n.colorByQuota, value: .quota),
                        .init(label: MenuBarQuotaL10n.colorSingle, value: .monochrome)
                    ]
                )
            }

            Text(appearance.colorMode == .quota
                ? MenuBarQuotaL10n.colorLegend
                : MenuBarQuotaL10n.monochromeColorLegend)
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        iconStyle = MenuBarQuotaPreferences.iconStyle(defaults: defaults)
        let rawMode = defaults.string(forKey: PreferencesKeys.displayMode) ?? DisplayMode.remaining.rawValue
        displayMode = DisplayMode(rawValue: rawMode) ?? .remaining
        showPercentage = defaults.object(forKey: PreferencesKeys.showMenuBarText) as? Bool ?? false
        appearance = MenuBarQuotaAppearance.load(defaults: defaults)
    }

    private func notifyMenuBarSettingsChanged() {
        NotificationCenter.default.post(name: .menuBarTextChanged, object: nil)
    }
}
