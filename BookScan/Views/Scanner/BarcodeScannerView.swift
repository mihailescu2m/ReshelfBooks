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
    private var isSessionRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showNoCameraAlert()
            return
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            return
        }

        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean13, .ean8]
        } else {
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

    private func addScanOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        view.addSubview(overlayView)

        let scanAreaWidth: CGFloat = min(view.bounds.width - 80, 300)
        let scanAreaHeight: CGFloat = 150
        let scanAreaX = (view.bounds.width - scanAreaWidth) / 2
        let scanAreaY = (view.bounds.height - scanAreaHeight) / 2

        let scanArea = CGRect(x: scanAreaX, y: scanAreaY, width: scanAreaWidth, height: scanAreaHeight)

        let borderView = UIView(frame: scanArea)
        borderView.layer.borderColor = UIColor.systemGreen.cgColor
        borderView.layer.borderWidth = 3
        borderView.layer.cornerRadius = 12
        borderView.backgroundColor = .clear
        overlayView.addSubview(borderView)

        let instructionLabel = UILabel()
        instructionLabel.text = "Position barcode within frame"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 16, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 20)
        ])
    }

    private func showNoCameraAlert() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func startScanning() {
        guard let session = captureSession, !isSessionRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            self?.isSessionRunning = true
        }
    }

    func stopScanning() {
        guard let session = captureSession, isSessionRunning else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.stopRunning()
            self?.isSessionRunning = false
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }

        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.didFindCode(stringValue)
    }
}
