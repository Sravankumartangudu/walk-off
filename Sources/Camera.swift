// The camera: a small 640×480 feed, a few pictures a second through Vision's face finder.
// Pictures are looked at in memory and dropped. Nothing is saved or sent anywhere.
import AVFoundation
import CoreImage
import Vision

/// A face Vision found. `box` is normalised (0…1) with the origin at the bottom left, not mirrored.
struct SeenFace {
    let box: CGRect
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the main thread for every processed picture. The image is only there while a
    /// preview wants it (`showPictures`).
    var onFrame: (([SeenFace], CGImage?) -> Void)?

    private(set) var isOn = false
    /// Why the camera can't run, or nil.
    private(set) var problem: String?
    private(set) var deviceName = ""

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.stangudu.walkoff.camera")
    private let ci = CIContext()
    private var deviceID: String?
    /// The camera `start` was last asked for while it's running, so repeat calls cost nothing.
    private var runningFor: String?
    private var asking = false
    private var rate: Double = 4
    // Only touched on `queue`.
    private var lastPicture: CFTimeInterval = 0
    private var pictures = false
    private var looksPerSecond: Double = 4
    private var lastVisionError: CFTimeInterval = -.infinity

    /// Cameras on this Mac. The iPhone (Continuity Camera) is listed but never picked by default,
    /// because opening it takes over the phone.
    static func all() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    /// The chosen camera, or the built-in one, or the first plain webcam. Never the iPhone unless chosen.
    static func device(for id: String) -> AVCaptureDevice? {
        let cams = all()
        if !id.isEmpty, let d = cams.first(where: { $0.uniqueID == id }) { return d }
        return cams.first { $0.deviceType == .builtInWideAngleCamera }
            ?? cams.first { !$0.isContinuityCamera && $0.deviceType != .continuityCamera }
    }

    func start(_ id: String) {
        if isOn && runningFor == id && problem == nil { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            problem = "Waiting for camera permission"
            if !asking {
                asking = true
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async { self.asking = false; self.problem = nil }
                }
            }
            return
        case .denied, .restricted:
            stop()
            problem = "Camera access is off (System Settings › Privacy & Security › Camera)"
            return
        default:
            break
        }
        guard let dev = Camera.device(for: id) else {
            stop()
            problem = "No camera found (lid closed?)"
            return
        }
        problem = nil
        runningFor = id
        if isOn && deviceID == dev.uniqueID { return }
        isOn = true
        deviceName = dev.localizedName
        let switching = deviceID != dev.uniqueID
        deviceID = dev.uniqueID
        Log.camera.notice("Camera on: \(dev.localizedName, privacy: .public)")
        queue.async { [self] in
            if switching { configure(dev) }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        runningFor = nil
        Log.camera.notice("Camera off")
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    /// How many pictures a second go through the face finder. More while the screen is locked,
    /// so the screen wakes the moment you're back.
    func lookRate(_ perSecond: Double) {
        guard perSecond != rate else { return }
        rate = perSecond
        queue.async { [self] in looksPerSecond = perSecond }
    }

    /// Pictures for the Camera check window, at a smoother rate.
    func showPictures(_ on: Bool) {
        queue.async { [self] in pictures = on }
    }

    private func configure(_ dev: AVCaptureDevice) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach { session.removeInput($0) }
        guard let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) else {
            DispatchQueue.main.async { self.problem = "Couldn't open \(dev.localizedName)" }
            return
        }
        session.addInput(input)
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        if session.outputs.isEmpty {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        // 4 looks a second is plenty to notice you leave; the preview gets 12 so it doesn't stutter.
        guard now - lastPicture >= 1.0 / max(pictures ? 12 : 0, looksPerSecond),
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPicture = now

        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        } catch where now - lastVisionError > 10 {
            lastVisionError = now
            Log.camera.error("Face finder failed: \(error.localizedDescription, privacy: .public)")
        } catch {}
        let faces = (request.results ?? []).map { SeenFace(box: $0.boundingBox) }

        var image: CGImage?
        if pictures {
            let ciImage = CIImage(cvPixelBuffer: pixels)
            image = ci.createCGImage(ciImage, from: ciImage.extent)
        }
        DispatchQueue.main.async { self.onFrame?(faces, image) }
    }
}
