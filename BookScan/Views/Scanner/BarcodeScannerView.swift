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
    @Binding var cameraPosition: AVCaptureDevice.Position

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let viewController = BarcodeScannerViewController()
        viewController.delegate = context.coordinator
        viewController.cameraPosition = cameraPosition
        return viewController
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        // Flip the camera if the header button changed the requested position.
        uiViewController.setCameraPosition(cameraPosition)

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

    /// Which camera to use. Set by the SwiftUI layer before the view loads, and flipped
    /// at runtime via `setCameraPosition`. Main-thread only.
    var cameraPosition: AVCaptureDevice.Position = .back

    // Session running state — only ever read/written on sessionQueue.
    private let sessionQueue = DispatchQueue(label: "com.bookscan.sessionQueue")
    private var isSessionRunning = false

    // Whether the view wants the session running. Set by start/stopScanning (driven
    // by updateUIViewController), read/written on the main thread. Defaults to false
    // so setup never auto-starts the camera unless scanning has actually been
    // requested — e.g. it stays off while the Scanner tab isn't visible. The session
    // may be requested before setup finishes (e.g. during the permission prompt), so
    // setup consults this flag once it's ready.
    private var shouldBeScanning = false

    // Guards against delivering more than one code per scan: the session keeps
    // feeding frames for a moment after stopScanning() (it stops asynchronously),
    // so the delegate can fire again before it actually halts. Main-thread only.
    private var hasDeliveredCode = false

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

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        // Maps the interface orientation to the capture connection's videoRotationAngle
        // (degrees, clockwise). Same mapping for the back camera (iPhone) and front
        // camera (iPad); mirroring differs but the rotation angle does not:
        // - Portrait: 90°
        // - Portrait Upside Down: 270°
        // - Landscape Left: 0°
        // - Landscape Right: 180°

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

        // A higher-resolution preset sharpens detection of small or worn barcodes.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
                ?? AVCaptureDevice.default(for: .video) else {
            showNoCameraAlert()
            return
        }
        // Adopt the position we actually got (a device may lack the requested camera).
        cameraPosition = videoCaptureDevice.position

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                showSetupErrorAlert(message: String(localized: "Could not add video input to capture session."))
                return
            }
        } catch {
            showSetupErrorAlert(message: String(localized: "Could not create video input: \(error.localizedDescription)"))
            return
        }

        // Tune focus/zoom for close-up barcode scanning (fixes blurry-up-close on
        // iPhone Pro models, whose wide camera has a long minimum focus distance).
        configureForCloseUpScanning(videoCaptureDevice)

        let metadataOutput = AVCaptureMetadataOutput()

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            // Book ISBNs are encoded as Bookland EAN-13 barcodes.
            metadataOutput.metadataObjectTypes = [.ean13]
            self.metadataOutput = metadataOutput
        } else {
            showSetupErrorAlert(message: String(localized: "Could not add metadata output to capture session."))
            return
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        self.previewLayer = previewLayer
        self.captureSession = session

        registerSessionObservers(for: session)
        addScanOverlay()

        // Setup may finish after updateUIViewController already asked us to start
        // (notably on the first launch, once the permission prompt is answered),
        // so kick off scanning here if it's still wanted.
        startSessionIfPossible()
    }

    // MARK: - Camera Switching

    /// Flips the active camera (front ⇆ back) when the header button requests a change.
    /// No-op if already on the requested camera or the session isn't set up yet.
    func setCameraPosition(_ position: AVCaptureDevice.Position) {
        guard position != cameraPosition, let session = captureSession else { return }
        // Update the (main-thread-only) mirror immediately so a re-render that calls this
        // again before the async reconfigure finishes sees the new value and is a no-op —
        // otherwise the guard above would pass twice and trigger a double flip.
        cameraPosition = position

        // Play a 3D flip of the preview (and its overlay), like the system Camera app.
        // Flip left when revealing the front camera, right when going back — so the two
        // directions read as inverse of each other. `.allowAnimatedContent` keeps the
        // live feed animating through the flip instead of freezing on a snapshot.
        let direction: UIView.AnimationOptions =
            position == .front ? .transitionFlipFromLeft : .transitionFlipFromRight
        UIView.transition(with: view, duration: 0.5, options: [direction, .allowAnimatedContent], animations: nil)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            // Remove the current video input(s).
            for input in session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    session.removeInput(deviceInput)
                }
            }

            // Add the camera at the new position; if it can't be added, roll back to
            // whatever input is still attached rather than leaving the session inputless.
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let newInput = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(newInput) else {
                return
            }
            session.addInput(newInput)
            self.configureForCloseUpScanning(device)

            DispatchQueue.main.async { self.updateVideoRotation() }
        }
    }

    // MARK: - Session Interruptions

    /// Observes interruptions (app backgrounded, an incoming call, another app taking
    /// the camera) so the session reliably resumes. Without this the preview can freeze
    /// after returning from the background, and our `isSessionRunning` flag would be
    /// left stale-true — blocking any restart.
    private func registerSessionObservers(for session: AVCaptureSession) {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionWasInterrupted),
                           name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded),
                           name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        // The system stopped the session; clear our flag so we can restart it later.
        sessionQueue.async { [weak self] in self?.isSessionRunning = false }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        // AVFoundation posts this on a background queue; hop to main because
        // startSessionIfPossible() reads the main-thread-only `shouldBeScanning`.
        // It resumes only if scanning is still wanted (e.g. back in the foreground
        // on the Scan tab).
        DispatchQueue.main.async { [weak self] in
            self?.startSessionIfPossible()
        }
    }

    // MARK: - Close-up Focus / Zoom

    /// Configures the capture device for scanning a barcode held close to the camera.
    ///
    /// iPhone 13 Pro and later have a wide camera with a large minimum focus distance
    /// (~20 cm). A barcode brought in close — the natural instinct, to make it bigger —
    /// lands inside that distance and renders blurry, while it focuses fine farther away.
    /// We can't physically focus closer, so we (1) bias autofocus toward near subjects
    /// and (2) apply a self-calibrating zoom so the barcode is large enough to scan at the
    /// *focusable* distance: zoom ≈ minimum focus distance / a comfortable hand distance.
    /// Devices that report a small/unknown minimum focus distance (older iPhones, the iPad
    /// front camera) get no zoom.
    private func configureForCloseUpScanning(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            // We're always scanning something close, so restrict autofocus to near range.
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }

            // minimumFocusDistance is in millimetres; -1 when unknown.
            let minFocusMM = device.minimumFocusDistance
            guard minFocusMM > 0 else { return }

            let comfortableDistanceMM = 100.0   // ~10 cm: a natural scanning distance
            let desiredZoom = Double(minFocusMM) / comfortableDistanceMM
            let deviceMaxZoom = Double(device.activeFormat.videoMaxZoomFactor)
            // Cap at 3× so an unexpectedly large reported focus distance can't over-zoom
            // and shrink the barcode out of usefulness; never exceed the device maximum.
            // Realistic wide-camera values (~100–250 mm → 1–2.5×) are unaffected.
            let zoom = max(1.0, min(desiredZoom, 3.0, deviceMaxZoom))

            // Only apply when it meaningfully helps — skip a pointless ~1.1× on phones
            // whose wide camera already focuses close.
            if zoom >= 1.3 {
                device.videoZoomFactor = CGFloat(zoom)
            }
        } catch {
            // Non-fatal: fall back to the default focus/zoom behaviour.
        }
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
        instructionLabel.text = String(localized: "Position barcode within frame")
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
        showErrorLabel(text: String(localized: "Camera not available"))
    }

    private func showPermissionDeniedAlert() {
        showErrorLabel(text: String(localized: "Camera access denied.\nPlease enable in Settings."))
    }

    private func showSetupErrorAlert(message: String) {
        showErrorLabel(text: String(localized: "Camera setup failed.\n\(message)"))
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
        shouldBeScanning = true
        // A fresh scan may begin; allow the next code to be delivered.
        hasDeliveredCode = false
        startSessionIfPossible()
    }

    func stopScanning() {
        shouldBeScanning = false
        guard let session = captureSession else { return }

        sessionQueue.async { [weak self] in
            guard let self, self.isSessionRunning else { return }
            session.stopRunning()
            self.isSessionRunning = false
        }
    }

    /// Starts the session if scanning is wanted and the session is ready.
    /// Safe to call from setup completion or from `startScanning()`.
    private func startSessionIfPossible() {
        guard shouldBeScanning, let session = captureSession else { return }

        // Check-and-set atomically on the session queue to avoid a TOCTOU race
        // when start/stop are called in quick succession.
        sessionQueue.async { [weak self] in
            guard let self, !self.isSessionRunning else { return }
            session.startRunning()
            self.isSessionRunning = true
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Only deliver one code per scan (delegate queue is main, so this is safe).
        guard !hasDeliveredCode else { return }

        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }

        hasDeliveredCode = true

        // Use modern haptic feedback
        feedbackGenerator.notificationOccurred(.success)
        delegate?.didFindCode(stringValue)
    }
}
