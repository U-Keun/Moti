import AVFoundation
import Vision

final class HandStream: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let q = DispatchQueue(label: "hand.stream.q")
    private let handler = VNSequenceRequestHandler()
    private let req = VNDetectHumanHandPoseRequest()
    private var lastEmit = CFAbsoluteTimeGetCurrent()
    private var fpsEMA: Double = 0
    private var roi: CGRect? = nil

    func start() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else { return }
        if session.canAddInput(input) { session.addInput(input) }

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.setSampleBufferDelegate(self, queue: q)
        if session.canAddOutput(out) { session.addOutput(out) }

        if let c = out.connection(with: .video) {
            if #available(macOS 14.0, *) {
                if c.isVideoRotationAngleSupported(90) {
                    c.videoRotationAngle = 90
                }
            } else if c.isVideoOrientationSupported {
                c.videoOrientation = .portrait
            }
        }

        session.commitConfiguration()
        session.startRunning()

        req.maximumHandCount = 1
    }
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        autoreleasepool {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastEmit < 0.066 { return }

            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            req.regionOfInterest = roi ?? CGRect(x: 0, y: 0, width: 1, height: 1)

            do {
                try handler.perform([req], on: pb)

                if let obs = req.results?.first {
                    let keys: [VNHumanHandPoseObservation.JointName] = [
                        .wrist,
                        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
                        .indexMCP, .indexPIP, .indexDIP, .indexTip,
                        .middleMCP, .middlePIP, .middleDIP, .middleTip,
                        .ringMCP, .ringPIP, .ringDIP, .ringTip,
                        .littleMCP, .littlePIP, .littleDIP, .littleTip
                    ]

                    let ptsVN = keys.compactMap { try? obs.recognizedPoint($0) }
                    let n = max(1, ptsVN.count) // 분모 0 방지
                    let conf = ptsVN.reduce(0.0) { $0 + Double($1.confidence) } / Double(n)

                    let pts = ptsVN.map { p -> [Double] in
                      [Double(p.location.x), Double(1 - p.location.y)]
                    }

                let goodPts = ptsVN.filter { $0.confidence >= 0.3 }
                if !goodPts.isEmpty {
                    let xs = goodPts.map { CGFloat($0.location.x) }
                    let ys = goodPts.map { CGFloat($0.location.y) }
                    var bbox = CGRect(x: xs.min()!, y: ys.min()!,
                                    width: xs.max()! - xs.min()!,
                                    height: ys.max()! - ys.min()!)
                    let pad: CGFloat = 0.1
                    bbox = bbox.insetBy(dx: -pad, dy: -pad)

                    if bbox.width < 0 { bbox.size.width = 0 }
                    if bbox.height < 0 { bbox.size.height = 0 }
                    bbox.origin.x = max(0, min(1 - bbox.size.width,  bbox.origin.x))
                    bbox.origin.y = max(0, min(1 - bbox.size.height, bbox.origin.y))
                    bbox.size.width  = min(1 - bbox.origin.x, bbox.size.width)
                    bbox.size.height = min(1 - bbox.origin.y, bbox.size.height)
                    roi = bbox
                }

                let dt = now - lastEmit
                let inst = 1.0 / dt
                fpsEMA = (fpsEMA == 0) ? inst : (0.2 * inst + 0.8 * fpsEMA)
                lastEmit = now

                let payload: [String: Any] = [
                  "type": "lm",
                  "t": Int(Date().timeIntervalSince1970 * 1000),
                  "fps": Double((fpsEMA * 10).rounded() / 10),
                  "hand": "unknown",
                  "lm": pts,
                  "conf": conf
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let line = String(data: data, encoding: .utf8) { print(line) }
                } else {
                    roi = nil
                }
            } catch {
              roi = nil
            }
        }
    }
}

let s = HandStream()
s.start()
RunLoop.main.run()
