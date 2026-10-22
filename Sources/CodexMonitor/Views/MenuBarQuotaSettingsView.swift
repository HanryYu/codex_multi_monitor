import SwiftUI

struct MenuBarQuotaSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @ObservedObject private var localeManager = LocaleManager.shared

    @State private var iconStyle = MenuBarIconStyle.ring
    @State private var displayMode = DisplayMode.remaining
    @State private var showPercentage = false
    @State private var appearance = MenuBarQuotaAppearance()
    @State private var accountRows: [UUID?] = []
    @State private var accountQuotaWindows: [UUID: MenuBarQuotaWindow] = [:]

    private var availableAccounts: [Account] {
        accountStore.accounts.filter { !$0.isHidden }
    }

    private var availableAccountIDs: [UUID] {
        availableAccounts.map(\.id)
    }

    private var availabilitySignature: [String] {
        accountStore.accounts.map { "\($0.id.uuidString):\($0.isHidden)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            MenuBarQuotaAppearanceSettingsView(
                iconStyle: $iconStyle,
                displayMode: $displayMode,
                showPercentage: $showPercentage,
                appearance: $appearance
            )

            SettingGroupCard(label: MenuBarQuotaL10n.accountsSection, systemImage: "person.2") {
                VStack(alignment: .leading, spacing: 9) {
                    Text(MenuBarQuotaL10n.accountRings)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)

                    if availableAccounts.isEmpty {
                        Text(MenuBarQuotaL10n.noAvailableAccounts)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(accountRows.indices), id: \.self) { index in
                            accountSelectionRow(at: index)
                        }

                        Button(action: addAccountRow) {
                            Label(MenuBarQuotaL10n.addAccountRing, systemImage: "plus")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .disabled(accountRows.count >= availableAccounts.count)
                    }

                    Text(MenuBarQuotaL10n.accountSelectionHelp)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(MenuBarQuotaL10n.quotaWindowHelp)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                }
            }
        }
        .onAppear(perform: loadPreferences)
        .onReceive(NotificationCenter.default.publisher(for: .menuBarTextChanged)) { _ in
            loadAccountQuotaWindows()
        }
        .onChange(of: availabilitySignature) { _, _ in
            loadAccountQuotaWindows()
            accountRows = makeAccountRows(
                from: MenuBarQuotaPreferences.selectedAccountIDs(available: availableAccountIDs)
            )
        }
        .onChange(of: localeManager.currentLanguage) { _, _ in
            // Observing the locale refreshes the computed strings in this view.
        }
    }

    private func accountSelectionRow(at index: Int) -> some View {
        let currentID = accountRows.indices.contains(index) ? accountRows[index] : nil
        let selectedElsewhere = Set<UUID>(accountRows.enumerated().compactMap { pair -> UUID? in
            guard pair.offset != index else { return nil }
            return pair.element
        })
        let selectableAccounts = availableAccounts.filter {
            $0.id == currentID || !selectedElsewhere.contains($0.id)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(MenuBarQuotaL10n.accountRing(index + 1))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 58, alignment: .leading)

                Picker(MenuBarQuotaL10n.selectAccount, selection: accountSelectionBinding(at: index)) {
                    Text(MenuBarQuotaL10n.selectAccount).tag(nil as UUID?)
                    ForEach(selectableAccounts) { account in
                        Text(accountLabel(account)).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    removeAccountRow(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help(MenuBarQuotaL10n.removeAccountRing)
                .accessibilityLabel(MenuBarQuotaL10n.removeAccountRing)
            }
            HStack(spacing: 8) {
                Text(MenuBarQuotaL10n.quotaPeriod)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 8)
                SettingsSegmentedControl(
                    selection: quotaWindowBinding(for: currentID),
                    options: [
                        .init(label: MenuBarQuotaL10n.windowLabel(.fiveHour), value: .fiveHour),
                        .init(label: MenuBarQuotaL10n.windowLabel(.weekly), value: .weekly)
                    ]
                )
                .disabled(currentID == nil)
                .opacity(currentID == nil ? 0.55 : 1)
            }
            .padding(.leading, 66)
            .padding(.trailing, 22)
        }
        .padding(.vertical, 4)
    }

    private func quotaWindowBinding(for accountID: UUID?) -> Binding<MenuBarQuotaWindow> {
        Binding(
            get: { accountID.flatMap { accountQuotaWindows[$0] } ?? .fiveHour },
            set: { window in
                guard let accountID else { return }
                accountQuotaWindows[accountID] = window
                MenuBarQuotaPreferences.setQuotaWindow(window, for: accountID)
            }
        )
    }

    private func loadAccountQuotaWindows() {
        accountQuotaWindows = Dictionary(uniqueKeysWithValues: availableAccountIDs.map {
            ($0, MenuBarQuotaPreferences.quotaWindow(for: $0))
        })
    }

    private func accountSelectionBinding(at index: Int) -> Binding<UUID?> {
        Binding(
            get: { accountRows.indices.contains(index) ? accountRows[index] : nil },
            set: { newValue in
                guard accountRows.indices.contains(index) else { return }
                accountRows[index] = newValue
                MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: accountRows.compactMap { $0 })
                MenuBarQuotaPreferences.saveAccountIDs(accountRows.compactMap { $0 })
            }
        )
    }

    private func accountLabel(_ account: Account) -> String {
        let identity = account.accountEmail ?? account.accountID
        let base = "\(account.provider.displayName) · \(account.name)"
        guard let identity, !identity.isEmpty else { return base }
        return "\(base) (\(identity))"
    }

    private func addAccountRow() {
        guard accountRows.count < availableAccounts.count else { return }
        accountRows.append(nil)
    }

    private func removeAccountRow(at index: Int) {
        guard accountRows.indices.contains(index) else { return }
        accountRows.remove(at: index)
        MenuBarQuotaPreferences.saveAccountIDs(accountRows.compactMap { $0 })
        if accountRows.isEmpty, !availableAccounts.isEmpty {
            accountRows = [nil]
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        accountRows = makeAccountRows(
            from: MenuBarQuotaPreferences.selectedAccountIDs(available: availableAccountIDs, defaults: defaults)
        )

        MenuBarQuotaPreferences.migrateLegacyQuotaWindow(for: accountRows.compactMap { $0 }, defaults: defaults)
        loadAccountQuotaWindows()

        // Persist the current effective choice. This keeps an empty multi-account state from
        // silently becoming a different account when visibility or account count changes.
        if defaults.object(forKey: MenuBarQuotaPreferences.accountIDsKey) == nil,
           !availableAccounts.isEmpty {
            MenuBarQuotaPreferences.saveAccountIDs(accountRows.compactMap { $0 }, defaults: defaults)
        }
    }

    private func makeAccountRows(from selectedIDs: [UUID]) -> [UUID?] {
        if selectedIDs.isEmpty, !availableAccounts.isEmpty {
            return [nil]
        }
        return selectedIDs.map(Optional.some)
    }
}
