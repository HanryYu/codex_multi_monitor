import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var isPresented: Bool

    var editingAccount: Account?

    @State private var name: String = ""
    @State private var accountEmail: String = ""
    @State private var authToken: String = ""
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
                Image(systemName: isEditing ? "pencil.circle.fill" : "person.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)

                Text(isEditing ? L10n.editAccount : L10n.addAccount)
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 4)

            // Form fields
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.accountName, systemImage: "person")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.accountNamePlaceholder, text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.accountEmail, systemImage: "envelope")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.accountEmailPlaceholder, text: $accountEmail)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.authToken, systemImage: "key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(L10n.authTokenPlaceholder, text: $authToken)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .token)
                        .onChange(of: authToken) { _, newValue in
                            autofillIdentity(from: newValue)
                        }

                    Text(L10n.getAuthTokenHint)
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
            } else {
                focusedField = .name
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }

    func saveAccount() {
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
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
            accountStore.updateAccount(updatedAccount)
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                authToken: trimmedToken,
                accountID: accountID,
                accountEmail: email
            )
            accountStore.addAccount(newAccount)
        }

        isPresented = false

        Task {
            await accountStore.refreshAll()
        }
    }

    private func autofillIdentity(from token: String) {
        guard accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let identity = AuthTokenIdentityParser.parse(accessToken: token)
        if let email = identity.email {
            accountEmail = email
        }
    }
}
