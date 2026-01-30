//
//  BarcodeScannerView.swift
//  BookScan
//
//  Created by Marian Mihailescu on 29/1/2026.
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var isScanning: Bool

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let viewController = BarcodeScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, BarcodeScannerViewControllerDelegate {
        var parent: BarcodeScannerView

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func didFindCode(_ code: String) {
            parent.scannedCode = code
            parent.isScanning = false
        }
    }
}

protocol BarcodeScannerViewControllerDelegate: AnyObject {
    func didFindCode(_ code: String)
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeScannerViewControllerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentRotationAngle: CGFloat = 90
    private var borderView: UIView?
    private var metadataOutput: AVCaptureMetadataOutput?

    // Thread-safe session state
    private let sessionQueue = DispatchQueue(label: "com.bookscan.sessionQueue")
    private var _isSessionRunning = false
    private var isSessionRunning: Bool {
        get { sessionQueue.sync { _isSessionRunning } }
        set { sessionQueue.sync { _isSessionRunning = newValue } }
    }

    // Haptic feedback generator
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        feedbackGenerator.prepare()
        checkCameraPermissionAndSetup()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate { [weak self] _ in
            self?.updateVideoRotation()
            self?.updateScanAreaOfInterest()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        updateScanAreaOfInterest()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateVideoRotation()
        updateScanAreaOfInterest()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    // MARK: - Camera Permission

    private func checkCameraPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCaptureSession()
                    } else {
                        self?.showPermissionDeniedAlert()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDeniedAlert()
        @unknown default:
            showPermissionDeniedAlert()
        }
    }

    // MARK: - Video Rotation

    private func updateVideoRotation() {
        guard let connection = previewLayer?.connection else { return }

        let angle = calculateRotationAngle()

        if angle != currentRotationAngle && connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            currentRotationAngle = angle
        }
    }

    private func calculateRotationAngle() -> CGFloat {
        // For front camera, the rotation angles are:
        // - Portrait: 90°
        // - Portrait Upside Down: 270°
        // - Landscape Left (home button on right): 0°
        // - Landscape Right (home button on left): 180°

        if let windowScene = view.window?.windowScene {
            switch windowScene.interfaceOrientation {
            case .portrait:
                return 90
            case .portraitUpsideDown:
                return 270
            case .landscapeLeft:
                return 0
            case .landscapeRight:
                return 180
            case .unknown:
                return angleFromViewBounds()
            @unknown default:
                return angleFromViewBounds()
            }
        }
        return angleFromViewBounds()
    }

    private func angleFromViewBounds() -> CGFloat {
        return view.bounds.width > view.bounds.height ? 0 : 90
    }

    // MARK: - Scan Area

    private func updateScanAreaOfInterest() {
        guard let previewLayer = previewLayer,
              let borderView = borderView,
              let metadataOutput = metadataOutput else { return }

        // Convert the border view's frame to the coordinate system used by AVCaptureMetadataOutput
        let scanRect = previewLayer.metadataOutputRectConverted(fromLayerRect: borderView.frame)
        metadataOutput.rectOfInterest = scanRect
    }

    // MARK: - Capture Session Setup

    private func setupCaptureSession() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            showNoCameraAlert()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                showSetupErrorAlert(message: "Could not add video input to capture session.")
                return
            }
        } catch {
            showSetupErrorAlert(message: "Could not create video input: \(error.localizedDescription)")
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean13, .ean8]
            self.metadataOutput = metadataOutput
        } else {
            showSetupErrorAlert(message: "Could not add metadata output to capture session.")
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        self.previewLayer = previewLayer
        self.captureSession = session

        addScanOverlay()
    }

    // MARK: - Scan Overlay

    private func addScanOverlay() {
        let overlayView = UIView()
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        let borderView = UIView()
        borderView.layer.borderColor = UIColor.systemGreen.cgColor
        borderView.layer.borderWidth = 3
        borderView.layer.cornerRadius = 12
        borderView.backgroundColor = .clear
        borderView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(borderView)
        self.borderView = borderView

        let instructionLabel = UILabel()
        instructionLabel.text = "Position barcode within frame"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(instructionLabel)

        // Calculate responsive scan area size
        // Use 70% of the smaller dimension for width, with max 300pt
        // Height is 50% of width for barcode aspect ratio
        let scanWidthMultiplier: CGFloat = 0.7
        let maxWidth: CGFloat = 300
        let aspectRatio: CGFloat = 0.5

        NSLayoutConstraint.activate([
            // Overlay fills the entire view
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Border view centered with responsive size
            borderView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            borderView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            borderView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            borderView.widthAnchor.constraint(lessThanOrEqualTo: overlayView.widthAnchor, multiplier: scanWidthMultiplier),
            borderView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            borderView.heightAnchor.constraint(equalTo: borderView.widthAnchor, multiplier: aspectRatio),

            // Instruction label centered below border
            instructionLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: overlayView.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlayView.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Error Alerts

    private func showNoCameraAlert() {
        showErrorLabel(text: "Camera not available")
    }

    private func showPermissionDeniedAlert() {
        showErrorLabel(text: "Camera access denied.\nPlease enable in Settings.")
    }

    private func showSetupErrorAlert(message: String) {
        showErrorLabel(text: "Camera setup failed.\n\(message)")
    }

    private func showErrorLabel(text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    // MARK: - Scanning Control

    func startScanning() {
        guard let session = captureSession, !isSessionRunning else { return }

        sessionQueue.async { [weak self] in
            session.startRunning()
            self?._isSessionRunning = true
        }
    }

    func stopScanning() {
        guard let session = captureSession, isSessionRunning else { return }

        sessionQueue.async { [weak self] in
            session.stopRunning()
            self?._isSessionRunning = false
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }

        // Use modern haptic feedback
        feedbackGenerator.notificationOccurred(.success)
        delegate?.didFindCode(stringValue)
    }
}
