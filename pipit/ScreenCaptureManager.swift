import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit

@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    @Published var availableWindows: [SCWindow] = []
    @Published var availableDisplays: [SCDisplay] = []
    @Published var isCapturing = false
    @Published var capturedFrame: CGImage?
    @Published var lastError: String?
    @Published var captureSize: CGSize?

    private var stream: SCStream?

    var captureMode: CaptureMode = .window
    var selectedWindow: SCWindow?
    var selectedDisplay: SCDisplay?
    // Region in screen coordinates (AppKit bottom-left origin)
    var captureRegion: CGRect?
    // The window found under the region — captured independently so it follows the window
    var regionTargetWindow: SCWindow?
    // Crop rect relative to the target window's frame
    var regionCropRect: CGRect?

    enum CaptureMode {
        case window
        case region
    }

    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableWindows = content.windows.filter { $0.title != nil && !$0.title!.isEmpty }
            availableDisplays = content.displays
        } catch {
            lastError = "Refresh failed: \(error.localizedDescription)"
            print("Failed to get shareable content: \(error)")
        }
    }

    // Call after refreshAvailableContent. Uses CGWindowListCopyWindowInfo for true
    // front-to-back z-order, finds the topmost window at the region's center point,
    // then matches to an SCWindow by windowID for reliable identification.
    func resolveRegionTarget() {
        guard let region = captureRegion else { return }
        let ourPID = ProcessInfo.processInfo.processIdentifier

        // Query WindowServer for windows in front-to-back order
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            regionTargetWindow = nil
            regionCropRect = nil
            return
        }

        // Find topmost window (first in list = frontmost) whose bounds contain the region center
        let center = CGPoint(x: region.midX, y: region.midY)

        // CGWindowListCopyWindowInfo uses top-left origin (flipped from AppKit)
        // Convert center from AppKit coords to CG coords
        let screenHeight = NSScreen.screens.first(where: { $0.frame.contains(center) })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        let cgCenter = CGPoint(x: center.x, y: screenHeight - center.y)

        var matchedWindowID: CGWindowID?
        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ourPID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  w > 0, h > 0 else { continue }

            let cgBounds = CGRect(x: x, y: y, width: w, height: h)
            if cgBounds.contains(cgCenter) {
                matchedWindowID = wid
                break
            }
        }

        guard let wid = matchedWindowID,
              let scWindow = availableWindows.first(where: { $0.windowID == wid }) else {
            // No exact match — fall back to first SCWindow intersecting region by frame
            let fallback = availableWindows.first {
                $0.owningApplication?.processID != ourPID && $0.frame.intersects(region)
            }
            regionTargetWindow = fallback
            if let w = fallback {
                regionCropRect = windowLocalCrop(region: region, window: w, cgWindowBounds: nil)
            } else {
                regionCropRect = nil
            }
            print("Region target (fallback): \(regionTargetWindow?.title ?? "none")")
            return
        }

        regionTargetWindow = scWindow
        regionCropRect = windowLocalCrop(region: region, window: scWindow, cgWindowBounds: nil)
        print("Region target: \(scWindow.title ?? "?") id:\(wid) crop:\(regionCropRect!)")
    }

    func startCapture() async {
        await stopCapture()
        lastError = nil

        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3

        do {
            let filter: SCContentFilter

            switch captureMode {
            case .window:
                guard let target = selectedWindow,
                      let fresh = availableWindows.first(where: { $0.windowID == target.windowID }) ?? selectedWindow else {
                    lastError = "No window selected"
                    return
                }
                filter = SCContentFilter(desktopIndependentWindow: fresh)
                let w = max(2, Int(fresh.frame.width)) & ~1
                let h = max(2, Int(fresh.frame.height)) & ~1
                config.width = w * 2
                config.height = h * 2

            case .region:
                guard let region = captureRegion, region.width > 0, region.height > 0 else {
                    lastError = "No region selected"
                    return
                }

                if let targetWindow = regionTargetWindow, let crop = regionCropRect {
                    // Capture the specific window — follows it regardless of active app
                    filter = SCContentFilter(desktopIndependentWindow: targetWindow)
                    // width/height must match the crop size, not the full window
                    let w = max(2, Int(crop.width)) & ~1
                    let h = max(2, Int(crop.height)) & ~1
                    config.width = w * 2
                    config.height = h * 2
                    config.sourceRect = crop
                } else {
                    // Fallback: display capture with region crop
                    guard let display = selectedDisplay ?? availableDisplays.first else {
                        lastError = "No display found"
                        return
                    }
                    let excluded = excludedSCWindows()
                    filter = SCContentFilter(display: display, excludingWindows: excluded)
                    let w = max(2, Int(region.width)) & ~1
                    let h = max(2, Int(region.height)) & ~1
                    config.sourceRect = region
                    config.width = w * 2
                    config.height = h * 2
                }
            }

            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream?.startCapture()
            isCapturing = true
            print("Capture started OK — mode: \(captureMode)")
        } catch {
            lastError = error.localizedDescription
            print("Failed to start capture: \(error)")
            stream = nil
        }
    }

    func stopCapture() async {
        guard let stream = stream else { return }
        do {
            try await stream.stopCapture()
        } catch {
            print("Failed to stop capture: \(error)")
        }
        self.stream = nil
        isCapturing = false
        capturedFrame = nil
    }

    // Computes sourceRect in window-local coordinates with top-left origin,
    // as required by SCContentFilter(desktopIndependentWindow:) + sourceRect.
    // region: AppKit bottom-left screen coords
    // window: SCWindow whose .frame is also AppKit bottom-left
    private func windowLocalCrop(region: CGRect, window: SCWindow, cgWindowBounds: CGRect?) -> CGRect {
        let intersection = region.intersection(window.frame)
        // x offset from window left edge — same in both coord systems
        let localX = intersection.minX - window.frame.minX
        // y in AppKit: intersection.minY from bottom. Convert to top-left:
        // localY (top-left) = windowHeight - (intersection.minY - window.frame.minY) - intersection.height
        let localYFromBottom = intersection.minY - window.frame.minY
        let localY = window.frame.height - localYFromBottom - intersection.height
        return CGRect(x: localX, y: localY, width: intersection.width, height: intersection.height)
    }

    private func excludedSCWindows() -> [SCWindow] {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        return availableWindows.filter { $0.owningApplication?.processID == ourPID }
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
        Task { @MainActor in
            self.isCapturing = false
            self.lastError = error.localizedDescription
        }
    }
}

private let sharedCIContext = CIContext()

extension ScreenCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = sharedCIContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let w = cgImage.width
        let h = cgImage.height
        Task { @MainActor in
            if self.capturedFrame == nil, w > 0, h > 0 {
                self.captureSize = CGSize(width: w, height: h)
            }
            self.capturedFrame = cgImage
        }
    }
}
