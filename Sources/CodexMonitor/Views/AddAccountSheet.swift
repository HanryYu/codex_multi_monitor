import SwiftUI

struct AddAccountSheet: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var isPresented: Bool
    
    var editingAccount: Account?
    
    @State private var name: String = ""
    @State private var authToken: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isEditing: Bool {
        editingAccount != nil
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isEditing ? "Edit Account" : "Add Account")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., Work, Personal", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authorization Token")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    SecureField("Bearer token from ChatGPT", text: $authToken)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Get token from browser developer tools")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if showError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button(isEditing ? "Save" : "Add") {
                    saveAccount()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || authToken.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            if let account = editingAccount {
                name = account.name
                authToken = account.authToken
            }
        }
    }
    
    func saveAccount() {
        // Validate token format
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            showError = true
            errorMessage = "Token cannot be empty"
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
        
        // Refresh data after adding
        Task {
            await accountStore.refreshAll()
        }
    }
}
