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
        window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        window.isOpaque = false
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard let rect = currentRect, isDragging else {
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath.fill(bounds)

            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 18, weight: .medium)
            ]
            let text = "Drag to select region • Press Escape to cancel"
            let size = text.size(withAttributes: attrs)
            let origin = NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            text.draw(at: origin, withAttributes: attrs)
            return
        }

        // dim outside selection
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: rect).reversed)
        NSColor.black.withAlphaComponent(0.5).setFill()
        path.fill()

        // selection border
        NSColor.white.setStroke()
        let selPath = NSBezierPath(rect: rect)
        selPath.lineWidth = 2
        selPath.stroke()

        // size label
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let labelSize = label.size(withAttributes: attrs)
        let labelOrigin = NSPoint(x: rect.minX, y: rect.maxY + 4)
        label.draw(at: labelOrigin, withAttributes: attrs)
        _ = labelSize
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
        let screenRect = convertToScreen(rect)
        onRegionSelected?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    private func convertToScreen(_ rect: NSRect) -> CGRect {
        // rect is in view-local coords (origin = bottom-left of view)
        // view origin equals screen.frame.origin for the overlay window
        // SCK sourceRect uses same bottom-left AppKit coordinate space — no Y flip needed
        let screenOrigin = window?.screen?.frame.origin ?? .zero
        return CGRect(
            x: rect.minX + screenOrigin.x,
            y: rect.minY + screenOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }
}
