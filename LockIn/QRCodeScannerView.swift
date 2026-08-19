import AVFoundation
import SwiftUI

/// A custom-styled QR code scanner sheet that handles incorrect scans without freezing.
struct QRCodeScannerView: UIViewControllerRepresentable {
    var expectedCode: String
    var onValidScan: () -> Void

    func makeUIViewController(context _: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.expectedCode = expectedCode
        controller.onValidScan = onValidScan
        return controller
    }

    func updateUIViewController(_: QRScannerController, context _: Context) {}
}

class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var expectedCode: String = ""
    var onValidScan: (() -> Void)?

    private var isTorchOn = false
    private let overlayView = UIView()
    private let guideBoxView = UIView()
    private let titleLabel = UILabel()
    private let titleBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let errorFeedbackLabel = UILabel()
    private let errorBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let torchButton = UIButton(type: .system)
    private let torchBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))

    private let cornerLength: CGFloat = 24
    private let cornerThickness: CGFloat = 4
    private var cornerLayers: [CAShapeLayer] = []

    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black

        setupCamera()
        setupUIOverlay()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func setupUIOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlayView.isUserInteractionEnabled = false
        view.addSubview(overlayView)

        guideBoxView.translatesAutoresizingMaskIntoConstraints = false
        guideBoxView.layer.cornerRadius = 16
        // No full border anymore — corner brackets are drawn in updateCornerBrackets()
        view.addSubview(guideBoxView)

        titleBackdrop.translatesAutoresizingMaskIntoConstraints = false
        titleBackdrop.layer.cornerRadius = 12
        titleBackdrop.clipsToBounds = true
        view.addSubview(titleBackdrop)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Align Gym QR Code Inside Frame"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleBackdrop.contentView.addSubview(titleLabel)

        errorBackdrop.translatesAutoresizingMaskIntoConstraints = false
        errorBackdrop.layer.cornerRadius = 10
        errorBackdrop.clipsToBounds = true
        errorBackdrop.alpha = 0 // Hidden by default
        view.addSubview(errorBackdrop)

        errorFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        errorFeedbackLabel.text = "Invalid QR Code. Try Again."
        errorFeedbackLabel.textColor = .systemRed
        errorFeedbackLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        errorFeedbackLabel.textAlignment = .center
        errorBackdrop.contentView.addSubview(errorFeedbackLabel)

        torchBackdrop.translatesAutoresizingMaskIntoConstraints = false
        torchBackdrop.layer.cornerRadius = 22
        torchBackdrop.clipsToBounds = true
        view.addSubview(torchBackdrop)

        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor = .white
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        torchBackdrop.contentView.addSubview(torchButton)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            guideBoxView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guideBoxView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            guideBoxView.widthAnchor.constraint(equalToConstant: 250),
            guideBoxView.heightAnchor.constraint(equalToConstant: 250),

            titleBackdrop.bottomAnchor.constraint(equalTo: guideBoxView.topAnchor, constant: -24),
            titleBackdrop.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleBackdrop.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),

            titleLabel.topAnchor.constraint(equalTo: titleBackdrop.contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: titleBackdrop.contentView.bottomAnchor, constant: -8),
            titleLabel.leadingAnchor.constraint(equalTo: titleBackdrop.contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: titleBackdrop.contentView.trailingAnchor, constant: -16),

            errorBackdrop.topAnchor.constraint(equalTo: guideBoxView.bottomAnchor, constant: 16),
            errorBackdrop.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            errorFeedbackLabel.topAnchor.constraint(equalTo: errorBackdrop.contentView.topAnchor, constant: 6),
            errorFeedbackLabel.bottomAnchor.constraint(equalTo: errorBackdrop.contentView.bottomAnchor, constant: -6),
            errorFeedbackLabel.leadingAnchor.constraint(equalTo: errorBackdrop.contentView.leadingAnchor, constant: 12),
            errorFeedbackLabel.trailingAnchor.constraint(equalTo: errorBackdrop.contentView.trailingAnchor, constant: -12),

            torchBackdrop.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            torchBackdrop.widthAnchor.constraint(equalToConstant: 44),
            torchBackdrop.heightAnchor.constraint(equalToConstant: 44),

            torchButton.centerXAnchor.constraint(equalTo: torchBackdrop.contentView.centerXAnchor),
            torchButton.centerYAnchor.constraint(equalTo: torchBackdrop.contentView.centerYAnchor),
        ])
    }

    @objc private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            let iconName = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            torchButton.setImage(UIImage(systemName: iconName), for: .normal)
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used")
        }
    }

    func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
        guard !isProcessing else { return }

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else { return }
            print(stringValue)
            if stringValue.contains(expectedCode) {
                // Successful Match
                isProcessing = true
                captureSession.stopRunning()
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                setCornerColor(.systemGreen)

                DispatchQueue.main.async { [weak self] in
                    self?.onValidScan?()
                    self?.dismiss(animated: true)
                }
            } else {
                // Wrong QR Code Scanned -> Flash warning and resume scanning instead of freezing
                isProcessing = true
                AudioServicesPlaySystemSound(SystemSoundID(1053)) // Error / beep sound cue

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    UIView.animate(withDuration: 0.2, animations: {
                        self.errorBackdrop.alpha = 1
                        self.setCornerColor(.systemRed)
                    }) { _ in
                        // Reset warning state after 1.2 seconds and allow scanning again
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            UIView.animate(withDuration: 0.2) {
                                self.errorBackdrop.alpha = 0
                                self.setCornerColor(.systemGreen)
                            }
                            self.isProcessing = false
                        }
                    }
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let previewLayer = previewLayer {
            previewLayer.frame = view.layer.bounds
        }
        applyOverlayMask()
        updateCornerBrackets()
    }

    /// Punches a clear hole in the dimmed overlay where the guide box sits,
    /// so the scan region reads brighter than the rest of the frame.
    private func applyOverlayMask() {
        overlayView.layoutIfNeeded()
        let path = UIBezierPath(rect: overlayView.bounds)
        let holePath = UIBezierPath(roundedRect: guideBoxView.frame, cornerRadius: guideBoxView.layer.cornerRadius)
        path.append(holePath)
        path.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer
    }

    /// Draws four L-shaped corner brackets around the guide box instead of a full square border.
    private func updateCornerBrackets() {
        cornerLayers.forEach { $0.removeFromSuperlayer() }
        cornerLayers.removeAll()

        let box = guideBoxView.bounds
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // top-left
            (CGPoint(x: 0, y: cornerLength), CGPoint(x: 0, y: 0), CGPoint(x: cornerLength, y: 0)),
            // top-right
            (CGPoint(x: box.width - cornerLength, y: 0), CGPoint(x: box.width, y: 0), CGPoint(x: box.width, y: cornerLength)),
            // bottom-right
            (CGPoint(x: box.width, y: box.height - cornerLength), CGPoint(x: box.width, y: box.height), CGPoint(x: box.width - cornerLength, y: box.height)),
            // bottom-left
            (CGPoint(x: cornerLength, y: box.height), CGPoint(x: 0, y: box.height), CGPoint(x: 0, y: box.height - cornerLength)),
        ]

        for (start, mid, end) in corners {
            let path = UIBezierPath()
            path.move(to: start)
            path.addLine(to: mid)
            path.addLine(to: end)

            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.strokeColor = UIColor.systemGreen.cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = cornerThickness
            layer.lineCap = .round
            layer.lineJoin = .round
            guideBoxView.layer.addSublayer(layer)
            cornerLayers.append(layer)
        }
    }

    private func setCornerColor(_ color: UIColor) {
        cornerLayers.forEach { $0.strokeColor = color.cgColor }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if captureSession?.isRunning == true {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }
    }
}
