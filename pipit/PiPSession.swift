import Foundation
import ScreenCaptureKit
import AppKit

@MainActor
class PiPSession: ObservableObject, Identifiable {
    let id = UUID()
    let captureManager = ScreenCaptureManager()
    var pipController: PiPWindowController?
    var label: String

    init(label: String) {
        self.label = label
    }

    func start() {
        if pipController == nil {
            let controller = PiPWindowController(captureManager: captureManager)
            pipController = controller
            controller.onClose = { [weak self] in
                Task { @MainActor in
                    await self?.captureManager.stopCapture()
                }
            }
            controller.show()
        } else {
            pipController?.show()
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await captureManager.refreshAvailableContent()
            if captureManager.captureMode == .region {
                captureManager.resolveRegionTarget()
            }
            await captureManager.startCapture()
        }
    }

    func stop() {
        Task { await captureManager.stopCapture() }
    }
}

@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [PiPSession] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var availableDisplays: [SCDisplay] = []
    @Published var permissionGranted: Bool = true

    func refresh() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                availableWindows = content.windows.filter { $0.title != nil && !$0.title!.isEmpty }
                availableDisplays = content.displays
                permissionGranted = true
            } catch {
                let code = (error as NSError).code
                if code == -3801 { permissionGranted = false }
                print("Refresh failed: \(error)")
            }
        }
    }

    func addWindowSession(window: SCWindow) -> PiPSession {
        let session = PiPSession(label: window.title ?? window.owningApplication?.applicationName ?? "Window")
        session.captureManager.captureMode = .window
        session.captureManager.selectedWindow = window
        session.captureManager.availableWindows = availableWindows
        session.captureManager.availableDisplays = availableDisplays
        sessions.append(session)
        return session
    }

    func addRegionSession(region: CGRect, display: SCDisplay) -> PiPSession {
        let session = PiPSession(label: "\(Int(region.width))×\(Int(region.height)) region")
        session.captureManager.captureMode = .region
        session.captureManager.captureRegion = region
        session.captureManager.selectedDisplay = display
        session.captureManager.availableWindows = availableWindows
        session.captureManager.availableDisplays = availableDisplays
        sessions.append(session)
        return session
    }

    func remove(_ session: PiPSession) {
        session.stop()
        session.pipController?.close()
        sessions.removeAll { $0.id == session.id }
    }
}
