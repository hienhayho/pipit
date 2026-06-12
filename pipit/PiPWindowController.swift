import AppKit
import SwiftUI
import ScreenCaptureKit

class PiPWindowController: NSWindowController {
    private var captureManager: ScreenCaptureManager
    private var hostingView: NSHostingView<PiPContentView>?
    var onClose: (() -> Void)?
    private var didSetInitialSize = false

    init(captureManager: ScreenCaptureManager) {
        self.captureManager = captureManager

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

        super.init(window: window)

        let pipView = PiPContentView(captureManager: captureManager, windowController: self)
        let hosting = NSHostingView(rootView: pipView)
        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hosting)
        hostingView = hosting

        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
    }

    // Called on first frame — resize window to natural content size, lock aspect ratio.
    // Max initial size = 50% of screen, preserving aspect ratio.
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
        onClose?()
    }
}

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
