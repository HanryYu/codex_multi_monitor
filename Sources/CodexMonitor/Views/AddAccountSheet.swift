import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var isPresented: Bool

    var editingAccount: Account?

    @State private var name: String = ""
    @State private var authToken: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case name, token
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

                Text(isEditing ? "Edit Account" : "Add Account")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, 4)

            // Form fields
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Account Name", systemImage: "person")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("e.g., Work, Personal", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Authorization Token", systemImage: "key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Bearer token from ChatGPT", text: $authToken)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .token)

                    Text("Get token from browser developer tools")
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

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? "Save" : "Add") {
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
                errorMessage = "Token cannot be empty"
            }
            return
        }

        if isEditing, let existingAccount = editingAccount {
            var updatedAccount = existingAccount
            updatedAccount.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedAccount.authToken = trimmedToken
            accountStore.updateAccount(updatedAccount)
        } else {
            let newAccount = Account(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                authToken: trimmedToken
            )
            accountStore.addAccount(newAccount)
        }

        isPresented = false

        Task {
            await accountStore.refreshAll()
        }
    }
}
