import AppKit

enum MenuBarQuotaRing {
    static func image(
        snapshot: MenuBarQuotaSnapshot,
        showRemaining: Bool,
        appearance: MenuBarQuotaAppearance = .init(),
        showNumberInside: Bool = false
    ) -> NSImage {
        let side: CGFloat = showNumberInside ? 22 : 18
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { _ in
            let color = Self.color(snapshot: snapshot, appearance: appearance)
            let center = NSPoint(x: side / 2, y: side / 2)
            let radius = side / 2 - 2
            let lineWidth: CGFloat = showNumberInside ? 2 : 2.5
            let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: side - 4, height: side - 4))
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.28).setStroke()
            track.stroke()

            if let percent = snapshot.percentage(showRemaining: showRemaining) {
                color.setStroke()
                if percent == 100 {
                    track.stroke()
                } else if percent > 0 {
                    let arc = NSBezierPath()
                    arc.lineWidth = lineWidth
                    arc.lineCapStyle = .round
                    arc.appendArc(withCenter: center, radius: radius,
                                  startAngle: 90, endAngle: 90 - CGFloat(percent) * 3.6,
                                  clockwise: true)
                    arc.stroke()
                } else {
                    // Keep the status color visible even when the selected amount is zero.
                    color.setFill()
                    NSBezierPath(ovalIn: NSRect(x: center.x - lineWidth / 2, y: center.y + radius - lineWidth / 2,
                                              width: lineWidth, height: lineWidth)).fill()
                }
            } else if !showNumberInside {
                let dash = NSBezierPath()
                dash.lineWidth = 1.5
                dash.lineCapStyle = .round
                dash.move(to: NSPoint(x: 6.5, y: 9))
                dash.line(to: NSPoint(x: 11.5, y: 9))
                color.setStroke()
                dash.stroke()
            }
            if showNumberInside {
                let number = snapshot.percentage(showRemaining: showRemaining).map(String.init) ?? "—"
                let fontSize: CGFloat = number.count >= 3 ? 7 : 8.5
                let text = NSAttributedString(string: number, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: appearance.colorMode == .monochrome ? NSColor.white : NSColor.labelColor,
                ])
                let textSize = text.size()
                text.draw(at: NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2))
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func color(snapshot: MenuBarQuotaSnapshot, appearance: MenuBarQuotaAppearance) -> NSColor {
        if appearance.colorMode == .monochrome { return .white }
        switch snapshot.level {
        case .healthy: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }
}
