import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var regionSelectorController: RegionSelectorWindowController?
    @State private var selectedWindowID: CGWindowID?
    @State private var captureMode: CaptureMode = .window
    @State private var windowSearch = ""

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

            if !sessionManager.permissionGranted {
                permissionBanner
            }

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
        .frame(width: 340, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            sessionManager.refresh() // triggers SCK permission prompt natively if not granted
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.orange)
                Text("Screen recording permission required")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            HStack(spacing: 8) {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                Button("Re-check") {
                    sessionManager.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .cornerRadius(8)
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
                TextField("Search windows...", text: $windowSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                let filtered = sessionManager.availableWindows.filter {
                    windowSearch.isEmpty ||
                    ($0.title ?? "").localizedCaseInsensitiveContains(windowSearch) ||
                    ($0.owningApplication?.applicationName ?? "").localizedCaseInsensitiveContains(windowSearch)
                }

                if filtered.isEmpty {
                    Text("No results for \"\(windowSearch)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered, id: \.windowID) { window in
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
                    .frame(maxHeight: 280)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
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
    ContentView(sessionManager: SessionManager())
}
