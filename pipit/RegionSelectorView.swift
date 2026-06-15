import AppKit
import SwiftUI

class RegionSelectorWindowController: NSWindowController {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var selectorView: RegionSelectorNSView?

    init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: window)

        let view = RegionSelectorNSView(frame: screen.frame)
        view.onRegionSelected = { [weak self] rect in
            self?.onRegionSelected?(rect)
            self?.close()
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
            self?.close()
        }
        window.contentView = view
        selectorView = view
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }
}

class RegionSelectorNSView: NSView {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dark overlay over entire screen
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(bounds)

        if let rect = currentRect, isDragging {
            // Punch a clear hole for the selected region — shows screen content underneath
            ctx.setBlendMode(.clear)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)

            // Border around selection
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(rect.insetBy(dx: 0.75, dy: 0.75))

            // Corner accents
            drawCorners(ctx: ctx, rect: rect)

            // Size label above selection
            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            drawLabel(label, above: rect, ctx: ctx)
        } else {
            // Hint text centered
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 16, weight: .medium)
            ]
            let text = "Drag to select region  •  Esc to cancel" as NSString
            let size = text.size(withAttributes: attrs)
            let origin = NSPoint(x: (bounds.width - size.width) / 2,
                                 y: (bounds.height - size.height) / 2)
            text.draw(at: origin, withAttributes: attrs)
        }
    }

    private func drawCorners(ctx: CGContext, rect: CGRect) {
        let len: CGFloat = 12
        let lw: CGFloat = 2.5
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(lw)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // top-left
            (CGPoint(x: rect.minX, y: rect.maxY - len),
             CGPoint(x: rect.minX, y: rect.maxY),
             CGPoint(x: rect.minX + len, y: rect.maxY)),
            // top-right
            (CGPoint(x: rect.maxX - len, y: rect.maxY),
             CGPoint(x: rect.maxX, y: rect.maxY),
             CGPoint(x: rect.maxX, y: rect.maxY - len)),
            // bottom-left
            (CGPoint(x: rect.minX + len, y: rect.minY),
             CGPoint(x: rect.minX, y: rect.minY),
             CGPoint(x: rect.minX, y: rect.minY + len)),
            // bottom-right
            (CGPoint(x: rect.maxX - len, y: rect.minY),
             CGPoint(x: rect.maxX, y: rect.minY),
             CGPoint(x: rect.maxX, y: rect.minY + len)),
        ]
        for (a, b, c) in corners {
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.addLine(to: c)
            ctx.strokePath()
        }
    }

    private func drawLabel(_ text: String, above rect: CGRect, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        let nsText = text as NSString
        let size = nsText.size(withAttributes: attrs)
        let padding: CGFloat = 4
        let bgRect = CGRect(
            x: rect.minX,
            y: rect.maxY + 6,
            width: size.width + padding * 2,
            height: size.height + padding
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.fill(bgRect)
        nsText.draw(at: NSPoint(x: bgRect.minX + padding, y: bgRect.minY + padding / 2),
                    withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        isDragging = true
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let rect = currentRect, rect.width > 10, rect.height > 10 else {
            onCancel?()
            return
        }
        onRegionSelected?(convertToScreen(rect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    private func convertToScreen(_ rect: NSRect) -> CGRect {
        let screenOrigin = window?.screen?.frame.origin ?? .zero
        return CGRect(
            x: rect.minX + screenOrigin.x,
            y: rect.minY + screenOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }
}
