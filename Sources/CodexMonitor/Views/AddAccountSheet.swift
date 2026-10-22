import SwiftUI
import AppKit

struct AddAccountSheet: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var isPresented: Bool

    let editingAccount: Account?

    private static let sheetWidth: CGFloat = 430
    private static let horizontalInset: CGFloat = 24

    @State private var name: String = ""
    @State private var accountEmail: String = ""
    @State private var authToken: String = ""
    @State private var openCodeWorkspaceID: String = ""
    @State private var claudeOrganizationID: String = ""
    @State private var provider: AccountProvider = .codex
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    init(accountStore: AccountStore, isPresented: Binding<Bool>, editingAccount: Account? = nil) {
        self.accountStore = accountStore
        self._isPresented = isPresented
        self.editingAccount = editingAccount
        _name = State(initialValue: editingAccount?.name ?? "")
        _accountEmail = State(initialValue: editingAccount?.accountEmail ?? "")
        _authToken = State(initialValue: editingAccount?.authToken ?? "")
        _openCodeWorkspaceID = State(initialValue: editingAccount?.openCodeWorkspaceID ?? "")
        _claudeOrganizationID = State(initialValue: editingAccount?.claudeOrganizationID ?? "")
        _provider = State(initialValue: editingAccount?.provider ?? .codex)
    }

    enum Field {
        case name, email, token, workspace, organization
    }

    var isEditing: Bool {
        editingAccount != nil
    }

    private var showsOpenCodeWorkspace: Bool {
        provider == .openCodeGo
            && !OpenCodeGoUsageService.shared.isAPIKeyCredential(authToken)
    }

    private var claudeCredential: ClaudeUsageCredential? {
        guard provider == .claude else { return nil }
        return try? ClaudeUsageCredential.parse(authToken)
    }

    /// Keep the action row visible while allowing the form to scroll on short
    /// displays or when the optional OpenCode workspace field is present.
    private var sheetMaximumHeight: CGFloat {
        let screenHeight = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return max(360, min(620, screenHeight - 120))
    }

    private var formMaximumHeight: CGFloat {
        max(245, sheetMaximumHeight - 96)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    // Icon + Title
                    VStack(spacing: 8) {
                        ProviderIconView(provider: provider, size: 34)

                        Text(L10n.accountSheetTitle(provider: provider, editing: isEditing))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.top, 4)

                    // Form fields
                    VStack(alignment: .leading, spacing: 16) {
                        if !isEditing {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.agentType)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Picker(L10n.agentType, selection: $provider) {
                                    ForEach(AccountProvider.allCases) { item in
                                        Text(item.displayName).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.providerAccountName(provider), systemImage: "person")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField(L10n.providerAccountNamePlaceholder(provider), text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .lineLimit(1)
                                .focused($focusedField, equals: .name)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.providerAccountEmail(provider), systemImage: "envelope")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField(L10n.accountEmailPlaceholder, text: $accountEmail)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .lineLimit(1)
                                .focused($focusedField, equals: .email)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.credentialLabel(provider), systemImage: "key")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            TextField(L10n.credentialPlaceholder(provider), text: $authToken)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .lineLimit(1)
                                .focused($focusedField, equals: .token)
                                .onChange(of: authToken) { _, newValue in
                                    autofillIdentity(from: newValue)
                                }

                            if let credential = claudeCredential {
                                Text(L10n.claudeDetectedCredential(isCookie: credential.isCookie))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("claudeCredentialType")
                            }

                            Text(tokenHint)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if claudeCredential?.isCookie == true {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(L10n.claudeOrganizationID, systemImage: "building.2")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                TextField(L10n.claudeOrganizationPlaceholder, text: $claudeOrganizationID)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .lineLimit(1)
                                    .focused($focusedField, equals: .organization)
                                    .accessibilityIdentifier("claudeOrganizationID")

                                Text(L10n.claudeOrganizationHint)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if showsOpenCodeWorkspace {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(L10n.openCodeWorkspaceID, systemImage: "square.stack.3d.up")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                TextField(L10n.openCodeWorkspacePlaceholder, text: $openCodeWorkspaceID)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .lineLimit(1)
                                    .focused($focusedField, equals: .workspace)

                                Text(L10n.openCodeWorkspaceHint)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    // Error
                    if showError {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                // Constrain the scroll document itself, not just its outer
                // sheet. Native controls can otherwise report a wider minimum
                // size and push the entire form outside the visible insets.
                .frame(width: Self.sheetWidth - 2 * Self.horizontalInset, alignment: .leading)
                .padding(.horizontal, Self.horizontalInset)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .frame(width: Self.sheetWidth)
            .frame(maxHeight: formMaximumHeight)

            Divider()

            // Buttons stay outside the scroll view so a long token, wrapped
            // hint, or optional workspace field cannot push them off-screen.
            HStack {
                Spacer()

                Button(L10n.cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? L10n.save : L10n.add) {
                    saveAccount()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authToken.isEmpty)
            }
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, 16)
        }
        .frame(width: Self.sheetWidth)
        .frame(maxHeight: sheetMaximumHeight)
        .background(.ultraThinMaterial)
        .onAppear {
            if !isEditing {
                focusedField = .name
            }
        }
        .onChange(of: provider) { _, _ in
            guard !isEditing else { return }
            name = ""
            accountEmail = ""
            authToken = ""
            openCodeWorkspaceID = ""
            claudeOrganizationID = ""
            showError = false
            errorMessage = ""
            focusedField = .name
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }

    func saveAccount() {
        // Editing updates only this account. Its provider is immutable even if
        // a future UI change accidentally mutates the new-account picker state.
        let provider = editingAccount?.provider ?? self.provider
        let trimmedToken = provider == .claude
            ? authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            : extractedToken(from: authToken, provider: provider)
        guard !trimmedToken.isEmpty else {
            withAnimation {
                showError = true
                errorMessage = L10n.tokenCannotBeEmpty
            }
            return
        }

        var normalizedCredential = trimmedToken
        var normalizedWorkspaceID: String?
        var normalizedOrganizationID: String?
        if provider == .claude {
            do {
                let credential = try ClaudeUsageCredential.parse(trimmedToken)
                normalizedCredential = credential.normalizedValue
                if credential.isCookie {
                    normalizedOrganizationID = try ClaudeUsageCredential.normalizedOrganizationID(claudeOrganizationID)
                }
            } catch {
                withAnimation {
                    showError = true
                    errorMessage = error.localizedDescription
                }
                return
            }
        }
        if provider == .openCodeGo {
            do {
                let service = OpenCodeGoUsageService.shared
                normalizedCredential = try service.normalizedCredential(trimmedToken)
                if !service.isAPIKeyCredential(normalizedCredential) {
                    normalizedWorkspaceID = try service.normalizedWorkspaceID(openCodeWorkspaceID)
                }
            } catch {
                withAnimation {
                    showError = true
                    errorMessage = error.localizedDescription
                }
                return
            }
        }

        let identity = AuthTokenIdentityParser.parse(accessToken: normalizedCredential)
        let email = AuthTokenIdentityParser.normalizedEmail(accountEmail) ?? identity.email
        let accountID = identity.accountID

        if isEditing, let existingAccount = editingAccount {
            var updatedAccount = existingAccount
            updatedAccount.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedAccount.accountEmail = email
            if let accountID {
                updatedAccount.accountID = accountID
            }
            updatedAccount.authToken = normalizedCredential
            updatedAccount.openCodeWorkspaceID = provider == .openCodeGo ? normalizedWorkspaceID : nil
            updatedAccount.claudeOrganizationID = normalizedOrganizationID
            if provider == .claude, claudeCredential?.isCookie == true {
                // A manually supplied web session must not be replaced by local CLI discovery.
                updatedAccount.source = .manual
                updatedAccount.localAuthInvalid = false
            }
            accountStore.updateAccount(updatedAccount)
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                authToken: normalizedCredential,
                accountID: accountID,
                accountEmail: email,
                provider: provider,
                openCodeWorkspaceID: normalizedWorkspaceID,
                claudeOrganizationID: normalizedOrganizationID
            )
            accountStore.addAccount(newAccount)
        }

        isPresented = false

        Task {
            await accountStore.refreshAll()
        }
    }

    private var tokenHint: String {
        L10n.credentialHint(provider)
    }

    private func autofillIdentity(from token: String) {
        guard accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let identity = AuthTokenIdentityParser.parse(accessToken: token)
        if let email = identity.email {
            accountEmail = email
        }
    }

    private func extractedToken(from input: String, provider: AccountProvider) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if provider == .claude,
               let oauth = object["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String {
                return token
            }
            if provider == .grok {
                for case let value as [String: Any] in object.values {
                    if let token = value["key"] as? String, !token.isEmpty { return token }
                }
            }
        }

        if let range = trimmed.range(of: "Bearer ", options: [.caseInsensitive]) {
            return String(trimmed[range.upperBound...])
                .split(whereSeparator: { $0.isWhitespace || $0 == "\"" })
                .first.map(String.init) ?? trimmed
        }
        if trimmed.lowercased().hasPrefix("cookie:") {
            return String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
