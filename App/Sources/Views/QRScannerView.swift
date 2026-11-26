import AVFoundation
import LastbookRemoteKit
import SwiftUI
import UIKit
import VisionKit

/// Scan the QR code of an access link (`http://<ip>:<port>/?key=…`) with the camera.
/// The scanned text is only parsed here and handed back; it is never logged or stored.
struct QRScannerSheet: View {
    let onLink: (AccessLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var access: CameraAccess = .checking
    @State private var message: String?

    enum CameraAccess { case checking, allowed, denied, unsupported }

    /// True when this device can scan at all (false in the Simulator and on devices without a capable camera).
    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan access link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await checkAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .checking:
            ProgressView()
        case .allowed:
            ZStack(alignment: .bottom) {
                QRDataScanner(onPayload: handle)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("Camera viewfinder")
                Text(message ?? "Point the camera at the QR code of the access link shown on your Lastbook computer.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: 520)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .accessibilityAddTraits(.updatesFrequently)
            }
        case .denied:
            ContentUnavailableView {
                Label("Camera access is off", systemImage: "camera")
            } description: {
                Text("Lastbook Remote uses the camera only to scan the access link QR code. Turn on Camera for Lastbook Remote in Settings, or paste the link instead.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .unsupported:
            ContentUnavailableView("Can't scan on this device", systemImage: "qrcode.viewfinder",
                                   description: Text("This device can't scan QR codes (for example, the Simulator). Paste the access link instead."))
        }
    }

    private func handle(_ payload: String) {
        switch AccessLink.inspect(payload) {
        case .link(let link):
            onLink(link)
            dismiss()
        case .missingKey:
            message = "That address has no access key. Scan the QR code of the full access link, the one that ends with ?key=…"
        case .notALink:
            message = "That QR code isn't a Lastbook access link. Keep the camera on the access link's code."
        }
    }

    private func checkAccess() async {
        guard DataScannerViewController.isSupported else {
            access = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = DataScannerViewController.isAvailable ? .allowed : .denied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            access = granted ? .allowed : .denied
        default:
            access = .denied
        }
    }
}

/// VisionKit's live scanner, limited to QR codes.
struct QRDataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        if !scanner.isScanning {
            // Start once the view is on screen; startScanning throws if the camera isn't available.
            DispatchQueue.main.async { try? scanner.startScanning() }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void
        private var lastPayload: String?
        private var lastAt = Date.distantPast

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                guard case .barcode(let code) = item, let payload = code.payloadStringValue else { continue }
                // The same code stays in view; don't repeat the same message many times a second.
                if payload == lastPayload && Date().timeIntervalSince(lastAt) < 2 { continue }
                lastPayload = payload
                lastAt = Date()
                onPayload(payload)
                return
            }
        }
    }
}
