import AppKit
import SwiftUI

@MainActor
final class CodexResetHoverPanelController: ObservableObject {
    enum Placement {
        case leftOfAnchor
        case rightOfAnchor
    }

    @Published private(set) var placement: Placement = .leftOfAnchor
    weak var anchorView: NSView?

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show<Content: View>(_ content: Content) {
        hideTask?.cancel()

        placement = resolvedPlacement(panelWidth: 308)
        let hostingController = NSHostingController(
            rootView: CodexResetHoverPanelContent(
                controller: self,
                content: content
            )
        )
        let panel = panel ?? makePanel()
        panel.contentViewController = hostingController

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let size = NSSize(
            width: 308,
            height: min(max(fittingSize.height, 80), 460)
        )
        panel.setContentSize(size)
        position(panel, size: size)
        panel.orderFrontRegardless()
    }

    func keepVisible() {
        hideTask?.cancel()
    }

    func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
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
        guard let anchorView,
              let window = anchorView.window
        else { return }

        let windowRect = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRect = window.convertToScreen(windowRect)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8

        let originX: CGFloat
        switch placement {
        case .leftOfAnchor:
            originX = anchorRect.minX - size.width - 4
        case .rightOfAnchor:
            originX = anchorRect.maxX + 4
        }

        var origin = NSPoint(x: originX, y: anchorRect.maxY - size.height)

        origin.x = min(
            max(origin.x, visibleFrame.minX + margin),
            visibleFrame.maxX - size.width - margin
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY + margin),
            visibleFrame.maxY - size.height - margin
        )

        panel.setFrameOrigin(origin)
    }

    private func resolvedPlacement(panelWidth: CGFloat) -> Placement {
        guard let anchorView,
              let window = anchorView.window
        else { return .leftOfAnchor }

        let windowRect = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRect = window.convertToScreen(windowRect)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let availableOnLeft = anchorRect.minX - visibleFrame.minX
        let availableOnRight = visibleFrame.maxX - anchorRect.maxX

        if availableOnLeft >= panelWidth + 4 || availableOnLeft >= availableOnRight {
            return .leftOfAnchor
        }
        return .rightOfAnchor
    }
}

private struct CodexResetHoverPanelContent<Content: View>: View {
    @ObservedObject var controller: CodexResetHoverPanelController
    let content: Content

    var body: some View {
        HStack(spacing: -0.5) {
            if controller.placement == .rightOfAnchor {
                arrow(pointing: .leading)
            }

            content

            if controller.placement == .leftOfAnchor {
                arrow(pointing: .trailing)
            }
        }
        .frame(width: 308, alignment: controller.placement == .leftOfAnchor ? .leading : .trailing)
    }

    private func arrow(pointing edge: Edge) -> some View {
        CodexResetHoverArrow(edge: edge)
            .fill(.regularMaterial)
            .overlay {
                CodexResetHoverArrowOutline(edge: edge)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .frame(width: 8, height: 14)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 7)
    }
}

private struct CodexResetHoverArrowOutline: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch edge {
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

private struct CodexResetHoverArrow: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch edge {
        case .leading:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct CodexResetHoverPanelAnchor: NSViewRepresentable {
    let controller: CodexResetHoverPanelController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        controller.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.anchorView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Void) {
        // The owning SwiftUI view hides the panel in onDisappear.
    }
}
