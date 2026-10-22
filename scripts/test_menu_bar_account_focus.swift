import AppKit
import SwiftUI

private struct CardFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private final class Measurements {
    var frames: [UUID: CGRect] = [:]
}

private struct FocusFixture: View {
    let navigation: MenuBarAccountNavigation
    let accountIDs: [UUID]
    let measurements: Measurements

    var body: some View {
        AccountFocusScrollView(navigation: navigation) {
            VStack(spacing: 8) {
                ForEach(Array(accountIDs.enumerated()), id: \.element) { index, accountID in
                    Text("Test account \(index + 1)")
                        .frame(maxWidth: .infinity)
                        .frame(height: index.isMultiple(of: 2) ? 120 : 160)
                        .background(Color.gray.opacity(0.1))
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: CardFrames.self,
                                    value: [accountID: geometry.frame(in: .named("viewport"))])
                            }
                        }
                        .id(accountID)
                }
            }
            .padding(12)
        }
        .coordinateSpace(name: "viewport")
        .onPreferenceChange(CardFrames.self) { measurements.frames = $0 }
    }
}

@main
struct AccountFocusProbe {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let navigation = MenuBarAccountNavigation()
        let ids = (0..<10).map { _ in UUID() }
        let measurements = Measurements()
        navigation.focus(accountID: ids[5])
        let view = NSHostingView(rootView: FocusFixture(navigation: navigation, accountIDs: ids, measurements: measurements))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        verifyVisible(ids[5], in: view, measurements: measurements, label: "initial middle account")
        navigation.focus(accountID: ids[0])
        verifyVisible(ids[0], in: view, measurements: measurements, label: "switch to first account")
        navigation.focus(accountID: ids[9])
        verifyVisible(ids[9], in: view, measurements: measurements, label: "switch to last account")

        // Simulate manual scrolling while keeping the same requested account.
        guard let scrollView = findScrollView(in: view) else { fatalError("Missing native scroll view") }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        verifyVisible(ids[0], in: view, measurements: measurements, label: "manual scroll to top")
        let previousRequest = navigation.request
        navigation.focus(accountID: ids[9])
        precondition(previousRequest != navigation.request)
        verifyVisible(ids[9], in: view, measurements: measurements, label: "reopen same account")

        view.rootView = FocusFixture(navigation: navigation, accountIDs: ids.reversed(), measurements: measurements)
        navigation.focus(accountID: ids[2])
        verifyVisible(ids[2], in: view, measurements: measurements, label: "account identity after reorder")
        navigation.focus(accountID: UUID())
        pump(view)
        navigation.focus(accountID: nil)
        pump(view)
        navigation.focus(accountID: ids[4])
        verifyVisible(ids[4], in: view, measurements: measurements, label: "recover after missing target")
        print("Account focus UI tests passed: first opening, first/last switching, same-account reopening, reordered accounts, missing targets.")
    }

    @MainActor
    private static func pump(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    @MainActor
    private static func verifyVisible(_ id: UUID, in view: NSView, measurements: Measurements, label: String) {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            pump(view)
            if let rect = measurements.frames[id], rect.minY >= -1, rect.maxY <= 301 { return }
        } while Date() < deadline
        fatalError("\(label): target not visible, frame=\(String(describing: measurements.frames[id]))")
    }

    @MainActor
    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }
}
