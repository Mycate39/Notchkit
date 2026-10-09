import AVFoundation
import AppKit
import SwiftUI
import Observation

/// Module Webcam : retour miroir rapide de la caméra avant une réunion (AVFoundation).
/// La caméra ne s'allume que pendant que la carte est affichée.
@MainActor
@Observable
final class CameraModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "camera",
        name: "Webcam",
        summary: "Un miroir rapide pour vérifier votre allure avant une réunion.",
        systemImage: "web.camera",
        category: .system,
        tier: .free,
        defaultEnabled: false
    )

    private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    init(context: ModuleContext) {}

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.authorization = AVCaptureDevice.authorizationStatus(for: .video) }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 1.5 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "web.camera", value: nil, caption: String(localized: "Webcam")))
    }

    func expandedView() -> AnyView {
        AnyView(CameraExpandedView(module: self))
    }
}

struct CameraExpandedView: View {
    let module: CameraModule

    var body: some View {
        Group {
            switch module.authorization {
            case .authorized:
                if AutomatedRun.isActive {
                    Color.black
                } else {
                    CameraPreview()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            case .notDetermined:
                prompt(symbol: "web.camera", text: "Autorisez la caméra pour voir votre miroir.",
                       button: "Autoriser…", action: module.requestAccess)
            default:
                prompt(symbol: "video.slash", text: "L'accès à la caméra est refusé.",
                       button: "Ouvrir les réglages…", action: module.openPrivacySettings)
            }
        }
        .padding(8)
    }

    private func prompt(symbol: String, text: LocalizedStringKey, button: LocalizedStringKey,
                        action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.standBy(.small))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Aperçu en miroir de la caméra par défaut ; la session s'arrête dès que la vue disparaît.
private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ view: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ view: CameraPreviewView, coordinator: ()) { view.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.andeolchenaux.notchkit.camera")
    private let previewLayer: AVCaptureVideoPreviewLayer

    override init(frame: NSRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)

        session.sessionPreset = .medium
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let session = session
        queue.async { session.startRunning() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
    }

    deinit { stop() }
}
