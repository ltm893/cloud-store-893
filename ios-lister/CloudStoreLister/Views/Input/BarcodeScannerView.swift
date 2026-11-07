import AudioToolbox
import AVFoundation
import SwiftUI

struct BarcodeScannerView: View {
    @EnvironmentObject private var viewModel: InventoryLookupViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectedTab) private var selectedTab

    @State private var scannedCode = ""
    @State private var scannedType = ""
    @State private var isScanning = true
    @State private var zoomFactor: CGFloat = 1
    @State private var exposureBias: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if isScanning {
                CameraPreview(
                    scannedCode: $scannedCode,
                    scannedType: $scannedType,
                    isScanning: $isScanning,
                    zoomFactor: $zoomFactor,
                    exposureBias: $exposureBias
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    BarcodeScanWindowOverlay()
                        .allowsHitTesting(false)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    magnifierBar
                }
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

                    if !scannedType.isEmpty {
                        Text("Code type")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(scannedType)
                            .font(.title3)
                            .fontWeight(.semibold)
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
                        scannedType = ""
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

    private var magnifierBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { zoomFactor = max(1, zoomFactor - 0.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                Slider(value: $zoomFactor, in: 1...5, step: 0.1)
                    .tint(.white)
                Button { zoomFactor = min(5, zoomFactor + 0.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                Text(String(format: "%.1f×", zoomFactor))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 36)
            }
            HStack(spacing: 12) {
                Button { exposureBias = max(-2, exposureBias - 0.5) } label: {
                    Image(systemName: "sun.min")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                Slider(value: $exposureBias, in: -2...2, step: 0.1)
                    .tint(.white)
                Button { exposureBias = min(2, exposureBias + 0.5) } label: {
                    Image(systemName: "sun.max")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                Text(String(format: "%+.1f", exposureBias))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 36)
            }
            Text("Place barcode in the window")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.55))
    }

    private func submitCode() {
        viewModel.submitLookup(scannedCode)
        selectedTab.wrappedValue = 1
        dismiss()
    }
}

private struct CameraPreview: UIViewControllerRepresentable {
    @Binding var scannedCode: String
    @Binding var scannedType: String
    @Binding var isScanning: Bool
    @Binding var zoomFactor: CGFloat
    @Binding var exposureBias: CGFloat

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        controller.onZoomChanged = { newZoom in
            context.coordinator.zoomFactor = newZoom
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.setZoom(zoomFactor)
        uiViewController.setExposure(exposureBias)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scannedCode: $scannedCode,
            scannedType: $scannedType,
            isScanning: $isScanning,
            zoomFactor: $zoomFactor
        )
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        @Binding var scannedCode: String
        @Binding var scannedType: String
        @Binding var isScanning: Bool
        @Binding var zoomFactor: CGFloat

        init(
            scannedCode: Binding<String>,
            scannedType: Binding<String>,
            isScanning: Binding<Bool>,
            zoomFactor: Binding<CGFloat>
        ) {
            _scannedCode = scannedCode
            _scannedType = scannedType
            _isScanning = isScanning
            _zoomFactor = zoomFactor
        }

        private var nonRetailSince: Date?

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard isScanning else { return }
            let reads = metadataObjects.compactMap(productBarcodeRead)
            guard let selection = ProductBarcode.preferred(from: reads) else { return }
            let now = Date()
            switch ProductBarcode.decide(symbology: selection.symbology, pendingSince: nonRetailSince, now: now) {
            case .accept:
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                scannedCode = selection.value
                scannedType = selection.symbology.label
                isScanning = false
            case .wait:
                if nonRetailSince == nil {
                    nonRetailSince = now
                }
            }
        }
    }
}

private func productBarcodeRead(_ object: AVMetadataObject) -> ProductBarcode.Read? {
    guard let readable = object as? AVMetadataMachineReadableCodeObject,
          let value = readable.stringValue else { return nil }
    return ProductBarcode.Read(symbology: symbology(for: readable.type), value: value)
}

private func symbology(for type: AVMetadataObject.ObjectType) -> ProductBarcode.Symbology {
    switch type {
    case .ean13: return .ean13
    case .upce: return .upcE
    case .ean8: return .ean8
    case .code128: return .code128
    case .pdf417: return .pdf417
    case .qr: return .qr
    default: return .other
    }
}

private final class ScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    var onZoomChanged: ((CGFloat) -> Void)?

    private var metadataOutput: AVCaptureMetadataOutput?
    private var appliedZoom: CGFloat = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            failed()
            return
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            failed()
            return
        }

        guard session.canAddInput(videoInput) else {
            failed()
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            failed()
            return
        }
        session.addOutput(metadataOutput)
        self.metadataOutput = metadataOutput
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .upce, .ean8, .code128, .pdf417, .qr]
        let available = metadataOutput.availableMetadataObjectTypes
        let enabled = available.isEmpty ? wanted : wanted.filter { available.contains($0) }
        if !enabled.isEmpty {
            metadataOutput.metadataObjectTypes = enabled
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession = session
        self.previewLayer = previewLayer

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async {
                self.view.setNeedsLayout()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        guard let metadataOutput, let previewLayer, view.bounds.width > 0 else { return }
        let window = BarcodeScanWindow.rect(in: view.bounds.size)
        let converted = previewLayer.metadataOutputRectConverted(fromLayerRect: window)
        if let interest = clampedInterest(converted) {
            metadataOutput.rectOfInterest = interest
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let upper = min(5, device.activeFormat.videoMaxZoomFactor)
        let clamped = factor.clamped(to: 1...upper)
        guard abs(device.videoZoomFactor - clamped) > 0.01 else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            appliedZoom = clamped
        } catch {
            NSLog("Barcode zoom failed: %@", error.localizedDescription)
        }
    }

    /// Negative bias darkens the frame so a glare does not wash out the bars.
    func setExposure(_ bias: CGFloat) {
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        let lower = max(-2, CGFloat(device.minExposureTargetBias))
        let upper = min(2, CGFloat(device.maxExposureTargetBias))
        guard lower < upper else { return }
        let clamped = Float(bias.clamped(to: lower...upper))
        guard abs(device.exposureTargetBias - clamped) > 0.05 else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            NSLog("Barcode exposure failed: %@", error.localizedDescription)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        switch gesture.state {
        case .changed:
            let upper = min(5, device.activeFormat.videoMaxZoomFactor)
            let next = (appliedZoom * gesture.scale).clamped(to: 1...upper)
            setZoom(next)
            gesture.scale = 1
            onZoomChanged?(device.videoZoomFactor)
        case .ended, .cancelled:
            appliedZoom = device.videoZoomFactor
            onZoomChanged?(appliedZoom)
        default:
            break
        }
    }

    private func clampedInterest(_ rect: CGRect) -> CGRect? {
        let standardized = rect.standardized
        guard standardized.width > 0, standardized.height > 0 else { return nil }
        let x = min(max(standardized.origin.x, 0), 0.95)
        let y = min(max(standardized.origin.y, 0), 0.95)
        let width = min(standardized.width, 1 - x)
        let height = min(standardized.height, 1 - y)
        guard width > 0.05, height > 0.05 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func failed() {
        let alert = UIAlertController(
            title: "Scanning Not Available",
            message: "This device does not support barcode scanning. Use manual entry instead.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        captureSession = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
}

private enum BarcodeScanWindow {
    /// Wide window centered slightly above the middle, matching a bottle barcode.
    static func rect(in size: CGSize) -> CGRect {
        let width = size.width * 0.78
        let height = min(max(size.height * 0.20, 96), width / 2.2)
        let x = (size.width - width) / 2
        let y = (size.height - height) / 2 - size.height * 0.05
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Orange stroke sits on the live camera feed so it stays visible in both themes.
private struct BarcodeScanWindowOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let window = BarcodeScanWindow.rect(in: geo.size)
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    path.addRoundedRect(in: window, cornerSize: CGSize(width: 8, height: 8))
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange, lineWidth: 3)
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
