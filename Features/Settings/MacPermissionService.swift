import AppKit
import AVFoundation
import CoreGraphics
import CopilotCore

@MainActor
protocol PermissionService {
    func microphoneStatus() -> PermissionState
    func screenStatus() -> PermissionState
    func requestMicrophone() async
    func requestScreen()
    func openSettings(screen: Bool) -> Bool
}

@MainActor
final class MacPermissionService: PermissionService {
    func microphoneStatus() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notRequested
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unconfirmed
        }
    }
    func screenStatus() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .unconfirmed
    }
    func requestMicrophone() async { _ = await AVCaptureDevice.requestAccess(for: .audio) }
    func requestScreen() { _ = CGRequestScreenCaptureAccess() }
    func openSettings(screen: Bool) -> Bool {
        let pane = screen ? "Privacy_ScreenCapture" : "Privacy_Microphone"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
