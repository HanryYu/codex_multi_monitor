import AppKit
import SwiftUI

@MainActor
final class CodexResetDetailsPanelController: ObservableObject {
    @Published private(set) var isShown = false

    weak var anchorView: NSView?

    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    func toggle<Content: View>(_ content: Content) {
        if isShown {
            close()
        } else {
            show(content)
        }
    }

    func show<Content: View>(_ content: Content) {
        guard !isShown, let anchorView, anchorView.window != nil else { return }

        let hostingController = NSHostingController(
            rootView: CodexResetPanelContent(content: content)
        )
        let panel = panel ?? makePanel()
        panel.contentViewController = hostingController

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingHeight = hostingController.view.fittingSize.height
        let size = NSSize(
            width: CodexResetPanelContent<Content>.panelWidth,
            height: min(max(fittingHeight, 120), 460)
        )
        panel.setContentSize(size)
        position(panel, size: size)
        panel.orderFrontRegardless()
        isShown = true
        startEventMonitoring()
    }

    func close() {
        stopEventMonitoring()
        panel?.orderOut(nil)
        isShown = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let anchorView, let window = anchorView.window else { return }

        let windowRect = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRect = window.convertToScreen(windowRect)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let screenMargin: CGFloat = 8
        let anchorGap: CGFloat = 4

        var origin = NSPoint(
            x: anchorRect.minX - size.width - anchorGap,
            y: anchorRect.maxY - size.height
        )
        origin.x = max(origin.x, visibleFrame.minX + screenMargin)
        origin.y = min(
            max(origin.y, visibleFrame.minY + screenMargin),
            visibleFrame.maxY - size.height - screenMargin
        )
        panel.setFrameOrigin(origin)
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.isShown else { return event }
            if self.eventIsInsidePanel(event) || self.eventTargetsAnchor(event) {
                return event
            }
            self.close()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func eventIsInsidePanel(_ event: NSEvent) -> Bool {
        event.window === panel
    }

    private func eventTargetsAnchor(_ event: NSEvent) -> Bool {
        guard let anchorView, event.window === anchorView.window else { return false }
        let point = anchorView.convert(event.locationInWindow, from: nil)
        return anchorView.bounds.contains(point)
    }
}

private struct CodexResetPanelContent<Content: View>: View {
    static var contentWidth: CGFloat { 320 }
    static var pointerWidth: CGFloat { 8 }
    static var panelWidth: CGFloat { contentWidth + pointerWidth }

    let content: Content

    var body: some View {
        HStack(spacing: -0.5) {
            content
                .frame(width: Self.contentWidth)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }

            CodexResetRightPointer()
                .fill(.regularMaterial)
                .overlay {
                    CodexResetRightPointerOutline()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                }
                .frame(width: Self.pointerWidth, height: 12)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 9)
        }
        .frame(width: Self.panelWidth, alignment: .leading)
    }
}

private struct CodexResetRightPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CodexResetRightPointerOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

struct CodexResetPanelAnchor: NSViewRepresentable {
    let controller: CodexResetDetailsPanelController

    func makeNSView(context: Context) -> NSView {
        let view = ClickThroughAnchorView(frame: .zero)
        controller.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.anchorView = nsView
    }

    private final class ClickThroughAnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
