import AVFoundation
import SwiftUI

/// A custom-styled QR code scanner sheet that handles incorrect scans without freezing.
struct QRCodeScannerView: UIViewControllerRepresentable {
    var expectedCode: String
    var onValidScan: () -> Void
    
    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.expectedCode = expectedCode
        controller.onValidScan = onValidScan
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
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
    private let errorFeedbackLabel = UILabel()
    private let torchButton = UIButton(type: .system)
    
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
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.addSubview(overlayView)
        
        guideBoxView.translatesAutoresizingMaskIntoConstraints = false
        guideBoxView.layer.borderColor = UIColor.systemGreen.cgColor
        guideBoxView.layer.borderWidth = 3
        guideBoxView.layer.cornerRadius = 16
        view.addSubview(guideBoxView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Align Gym QR Code Inside Frame"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        
        errorFeedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        errorFeedbackLabel.text = "Invalid QR Code. Try Again."
        errorFeedbackLabel.textColor = .systemRed
        errorFeedbackLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        errorFeedbackLabel.textAlignment = .center
        errorFeedbackLabel.alpha = 0 // Hidden by default
        view.addSubview(errorFeedbackLabel)
        
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor = .white
        torchButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.7)
        torchButton.layer.cornerRadius = 22
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        view.addSubview(torchButton)
        
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            guideBoxView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guideBoxView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            guideBoxView.widthAnchor.constraint(equalToConstant: 250),
            guideBoxView.heightAnchor.constraint(equalToConstant: 250),
            
            titleLabel.bottomAnchor.constraint(equalTo: guideBoxView.topAnchor, constant: -24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            errorFeedbackLabel.topAnchor.constraint(equalTo: guideBoxView.bottomAnchor, constant: 16),
            errorFeedbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            torchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            torchButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44)
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
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
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
                
                DispatchQueue.main.async { [weak self] in
                    self?.onValidScan?()
                    self?.dismiss(animated: true)
                }
            } else {
                // Wrong QR Code Scanned -> Flash warning and resume scanning instead of freezing
                isProcessing = true
                AudioServicesPlaySystemSound(SystemSoundID(1053)) // Error / beep sound cue
                
                DispatchQueue.main.async { [weak self] in
                    UIView.animate(withDuration: 0.2, animations: {
                        self?.errorFeedbackLabel.alpha = 1
                        self?.guideBoxView.layer.borderColor = UIColor.systemRed.cgColor
                    }) { _ in
                        // Reset warning state after 1.2 seconds and allow scanning again
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            UIView.animate(withDuration: 0.2) {
                                self?.errorFeedbackLabel.alpha = 0
                                self?.guideBoxView.layer.borderColor = UIColor.systemGreen.cgColor
                            }
                            self?.isProcessing = false
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
