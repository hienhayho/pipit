import AppKit
import SwiftUI
import ScreenCaptureKit

class PiPWindowController: NSWindowController {
    private var captureManager: ScreenCaptureManager
    private var hostingView: NSHostingView<PiPContentView>?
    var onClose: (() -> Void)?
    private var didSetInitialSize = false
    private var mouseMonitor: Any?
    private var isTransparent = false
    private let resizeMargin: CGFloat = 12

    init(captureManager: ScreenCaptureManager) {
        self.captureManager = captureManager

        let contentView = TrackingContentView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PiP"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 160, height: 90)
        window.contentView = contentView

        super.init(window: window)

        let pipView = PiPContentView(captureManager: captureManager, windowController: self)
        let hosting = NSHostingView(rootView: pipView)
        hosting.frame = contentView.bounds
        hosting.autoresizingMask = [.width, .height]
        contentView.addSubview(hosting)
        hostingView = hosting

        window.center()
        window.delegate = self
        startMouseMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
        window?.alphaValue = 1.0
    }

    private func startMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.evaluateHover()
        }
        // Also monitor local (when pipit window is key)
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.evaluateHover()
            return event
        }
    }

    private func evaluateHover() {
        guard let window else { return }
        let mouseScreen = NSEvent.mouseLocation          // screen coords, bottom-left origin
        let frame = window.frame
        let inside = frame.contains(mouseScreen)

        if inside {
            // Convert to window-local coords to check resize margin
            let localX = mouseScreen.x - frame.minX
            let localY = mouseScreen.y - frame.minY
            let m = resizeMargin
            let inInterior = localX > m && localY > m &&
                             localX < frame.width - m && localY < frame.height - m

            if inInterior && !isTransparent {
                guard UserDefaults.standard.bool(forKey: "hoverTransparencyEnabled") else { return }
                isTransparent = true
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    window.animator().alphaValue = 0.08
                }
            } else if !inInterior && isTransparent {
                isTransparent = false
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    window.animator().alphaValue = 1.0
                }
            }
        } else if isTransparent {
            isTransparent = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                window.animator().alphaValue = 1.0
            }
        }
    }

    func applyNaturalSize(_ size: CGSize) {
        guard !didSetInitialSize, size.width > 0, size.height > 0 else { return }
        didSetInitialSize = true

        let screen = window?.screen ?? NSScreen.main
        let maxW = (screen?.visibleFrame.width ?? 1200) * 0.5
        let maxH = (screen?.visibleFrame.height ?? 800) * 0.5
        let scale = min(1.0, min(maxW / size.width, maxH / size.height))
        let targetW = max(160, (size.width * scale).rounded())
        let targetH = max(90, (size.height * scale).rounded())

        window?.aspectRatio = NSSize(width: size.width, height: size.height)
        window?.setContentSize(NSSize(width: targetW, height: targetH))
        window?.center()
    }
}

extension PiPWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        window?.alphaValue = 1.0
        onClose?()
    }
}

class TrackingContentView: NSView {}  // plain content view, no tracking needed

struct PiPContentView: View {
    @ObservedObject var captureManager: ScreenCaptureManager
    weak var windowController: PiPWindowController?

    var body: some View {
        ZStack {
            Color.black
            if let frame = captureManager.capturedFrame {
                Image(decorative: frame, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: captureManager.captureSize) { _, size in
                        if let size {
                            windowController?.applyNaturalSize(size)
                        }
                    }
            } else {
                VStack(spacing: 8) {
                    if captureManager.isCapturing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .foregroundColor(.gray)
                            .font(.caption)
                    } else if let err = captureManager.lastError {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(err)
                            .foregroundColor(.orange)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    } else {
                        Text("No source selected")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
