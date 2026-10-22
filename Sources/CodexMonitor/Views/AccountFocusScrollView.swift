import SwiftUI

/// Each opening gets a new request, including reopening the same account after manual scrolling.
final class MenuBarAccountNavigation: ObservableObject {
    struct Request: Equatable {
        let id = UUID()
        let accountID: UUID?
    }

    @Published private(set) var request = Request(accountID: nil)

    func focus(accountID: UUID?) {
        request = Request(accountID: accountID)
    }
}

struct AccountFocusScrollView<Content: View>: View {
    @ObservedObject var navigation: MenuBarAccountNavigation
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .task(id: navigation.request) {
                guard let accountID = navigation.request.accountID else { return }
                // Let the popover and account cards complete their first layout before scrolling.
                await Task.yield()
                guard !Task.isCancelled else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(accountID, anchor: .top)
                }
            }
        }
    }
}
