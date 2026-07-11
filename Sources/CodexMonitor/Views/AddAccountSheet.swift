import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var isPresented: Bool

    var editingAccount: Account?

    @State private var name: String = ""
    @State private var accountEmail: String = ""
    @State private var authToken: String = ""
    @State private var provider: AccountProvider = .codex
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case name, email, token
    }

    var isEditing: Bool {
        editingAccount != nil
    }

    var body: some View {
        VStack(spacing: 20) {
            // Icon + Title
            VStack(spacing: 8) {
                ProviderIconView(provider: provider, size: 34)

                Text(L10n.accountSheetTitle(provider: provider, editing: isEditing))
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 4)

            // Form fields
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.agentType)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker(L10n.agentType, selection: $provider) {
                        ForEach(AccountProvider.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.providerAccountName(provider), systemImage: "person")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.providerAccountNamePlaceholder(provider), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.providerAccountEmail(provider), systemImage: "envelope")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.accountEmailPlaceholder, text: $accountEmail)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.credentialLabel(provider), systemImage: "key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.credentialPlaceholder(provider), text: $authToken)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .token)
                        .onChange(of: authToken) { _, newValue in
                            autofillIdentity(from: newValue)
                        }

                    Text(tokenHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            // Error
            if showError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Buttons
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
                .disabled(name.isEmpty || authToken.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .onAppear {
            if let account = editingAccount {
                name = account.name
                accountEmail = account.accountEmail ?? ""
                authToken = account.authToken
                provider = account.provider
            } else {
                focusedField = .name
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }

    func saveAccount() {
        let trimmedToken = extractedToken(from: authToken, provider: provider)
        guard !trimmedToken.isEmpty else {
            withAnimation {
                showError = true
                errorMessage = L10n.tokenCannotBeEmpty
            }
            return
        }

        let identity = AuthTokenIdentityParser.parse(accessToken: trimmedToken)
        let email = AuthTokenIdentityParser.normalizedEmail(accountEmail) ?? identity.email
        let accountID = identity.accountID

        if isEditing, let existingAccount = editingAccount {
            var updatedAccount = existingAccount
            updatedAccount.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedAccount.accountEmail = email
            if let accountID {
                updatedAccount.accountID = accountID
            }
            updatedAccount.authToken = trimmedToken
            updatedAccount.provider = provider
            accountStore.updateAccount(updatedAccount)
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                authToken: trimmedToken,
                accountID: accountID,
                accountEmail: email,
                provider: provider
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
