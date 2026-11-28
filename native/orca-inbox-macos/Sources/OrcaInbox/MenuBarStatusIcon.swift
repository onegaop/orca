import AppKit
import InboxCore

enum MenuBarStatusIcon {
    private static let iconSize = NSSize(width: 21, height: 18)

    static func image(for status: InboxMenuStatus) -> NSImage? {
        guard let dotColor = dotColor(for: status.indicator) else {
            let symbol = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: nil)
            symbol?.isTemplate = true
            return symbol
        }

        let symbolName = status.symbolName
        let image = NSImage(size: iconSize, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
            if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let symbolSize = base.size
                let origin = NSPoint(
                    x: floor((rect.width - symbolSize.width) / 2) - 1,
                    y: floor((rect.height - symbolSize.height) / 2)
                )
                let symbolRect = NSRect(origin: origin, size: symbolSize)

                NSGraphicsContext.saveGraphicsState()
                base.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
                NSColor.labelColor.setFill()
                symbolRect.fill(using: .sourceAtop)
                NSGraphicsContext.restoreGraphicsState()
            }

            let dotDiameter: CGFloat = 6.2
            let haloDiameter: CGFloat = 8.4
            let dotCenter = NSPoint(x: rect.maxX - 4.4, y: rect.maxY - 4.6)

            // Punch a clean halo around the status dot so it never blurs into the symbol strokes.
            let haloRect = NSRect(
                x: dotCenter.x - haloDiameter / 2,
                y: dotCenter.y - haloDiameter / 2,
                width: haloDiameter,
                height: haloDiameter
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(ovalIn: haloRect).fill()
            NSGraphicsContext.restoreGraphicsState()

            let dotRect = NSRect(
                x: dotCenter.x - dotDiameter / 2,
                y: dotCenter.y - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    private static func dotColor(for indicator: InboxMenuIndicator) -> NSColor? {
        switch indicator {
        case .blocked, .disconnected:
            return .systemRed
        case .waiting:
            return .systemOrange
        case .unreadDone:
            return .systemGreen
        case .working:
            return .systemBlue
        case .idle, .stale, .loading:
            return nil
        }
    }
}
