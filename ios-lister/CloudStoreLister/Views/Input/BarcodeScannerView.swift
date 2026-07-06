import AudioToolbox
import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    @State private var scannedCode = ""
    @State private var isScanning = true

    var body: some View {
        VStack {
            if isScanning {
                BarcodeCameraPreview(scannedCode: $scannedCode, isScanning: $isScanning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.listerAccent)
                            .frame(width: 100, height: 100)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.white)
                    }

                    Text("Scanned Code")
                        .font(.headline)

                    Text(scannedCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.listerHighlight)
                        .cornerRadius(10)
                        .colorScheme(.light)

                    Button {
                        submitCode()
                    } label: {
                        Text("Lookup")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(Color.listerAccent)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Button("Scan Again") {
                        scannedCode = ""
                        isScanning = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.listerHighlight)
                    .foregroundStyle(.primary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.listerBackground)
            }
        }
        .navigationTitle("Barcode Scanner")
        .listerNavigationBar()
    }

    private func submitCode() {
        viewModel.submitLookup(scannedCode)
        selectedTab.wrappedValue = 1
        dismiss()
    }
}

private struct BarcodeCameraPreview: UIViewControllerRepresentable {
    @Binding var scannedCode: String
    @Binding var isScanning: Bool

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(scannedCode: $scannedCode, isScanning: $isScanning)
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String
        @Binding var isScanning: Bool

        init(scannedCode: Binding<String>, isScanning: Binding<Bool>) {
            _scannedCode = scannedCode
            _isScanning = isScanning
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard isScanning,
                  let metadataObject = metadataObjects.first,
                  let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            scannedCode = stringValue
            isScanning = false
        }
    }
}

private final class BarcodeScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showFailureAlert()
            return
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            showFailureAlert()
            return
        }

        guard session.canAddInput(videoInput) else {
            showFailureAlert()
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showFailureAlert()
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: .main)
        metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .qr, .code128]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession = session
        self.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    private func showFailureAlert() {
        let alert = UIAlertController(
            title: "Scanning Not Available",
            message: "This device does not support barcode scanning. Use manual entry instead.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BarcodeScannerView()
            .environmentObject(InventoryLookupViewModel())
    }
}
#endif
