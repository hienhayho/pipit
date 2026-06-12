import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager()
    @State private var regionSelectorController: RegionSelectorWindowController?
    @State private var selectedWindowID: CGWindowID?
    @State private var captureMode: CaptureMode = .window
    @State private var showingPermissionAlert = false

    enum CaptureMode: String, CaseIterable {
        case window = "Window"
        case region = "Region"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "pip.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Pipit")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(sessionManager.sessions.count) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Mode picker
            Picker("Mode", selection: $captureMode) {
                ForEach(CaptureMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if captureMode == .window {
                windowPickerSection
            } else {
                regionSection
            }

            Divider()

            // Add PiP button
            Button(action: addPiP) {
                Label("Add PiP", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(captureMode == .window && selectedWindowID == nil)

            // Active sessions list
            if !sessionManager.sessions.isEmpty {
                Divider()
                Text("Active PiPs")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(sessionManager.sessions) { session in
                    SessionRowView(session: session) {
                        sessionManager.remove(session)
                    }
                }
            }

            Button(action: sessionManager.refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 320)
        .task {
            await checkPermission()
            sessionManager.refresh()
        }
        .alert("Screen Recording Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pipit needs screen recording permission to capture windows and regions.")
        }
    }

    private var windowPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Window")
                .font(.caption)
                .foregroundColor(.secondary)

            if sessionManager.availableWindows.isEmpty {
                Text("No windows available — tap Refresh")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sessionManager.availableWindows, id: \.windowID) { window in
                            WindowRowView(
                                window: window,
                                isSelected: window.windowID == selectedWindowID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedWindowID = window.windowID
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag to select a region on screen")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: selectRegion) {
                Label("Select Region", systemImage: "selection.pin.in.out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func checkPermission() async {
        do {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            showingPermissionAlert = true
        }
    }

    private func selectRegion() {
        guard let screen = NSScreen.main else { return }
        let selector = RegionSelectorWindowController(screen: screen)
        selector.onRegionSelected = { [weak selector] rect in
            Task { @MainActor in
                if sessionManager.availableDisplays.isEmpty {
                    sessionManager.refresh()
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                guard let display = sessionManager.availableDisplays.first else {
                    selector?.close()
                    return
                }
                selector?.close()
                let session = sessionManager.addRegionSession(region: rect, display: display)
                session.start()
            }
        }
        selector.onCancel = { [weak selector] in selector?.close() }
        regionSelectorController = selector
        selector.show()
    }

    private func addPiP() {
        switch captureMode {
        case .window:
            guard let wid = selectedWindowID,
                  let window = sessionManager.availableWindows.first(where: { $0.windowID == wid }) else { return }
            let session = sessionManager.addWindowSession(window: window)
            session.start()

        case .region:
            selectRegion()
        }
    }
}

struct SessionRowView: View {
    @ObservedObject var session: PiPSession
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.captureManager.isCapturing ? Color.green : Color.gray)
                .frame(width: 7, height: 7)

            Text(session.label)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button {
                session.pipController?.show()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Show PiP window")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct WindowRowView: View {
    let window: SCWindow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title ?? "Untitled")
                    .font(.caption)
                    .lineLimit(1)
                if let app = window.owningApplication?.applicationName {
                    Text(app)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}

#Preview {
    ContentView()
}
